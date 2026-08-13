import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Renders multi-surface 3D plots to PNGs so they can be looked at.
///
/// Set KLOTTER_RENDER_DIR to collect them; without it these are no-ops. Nothing
/// here asserts on the images — the pixel assertions live in
/// multi_surface_3d_test.dart. A pixel count told me a surface had changed
/// three times running without telling me it was right; opening the file is
/// what settled it.
void main() {
  final String? outDir = Platform.environment['KLOTTER_RENDER_DIR'];

  /// Rendering runs inside [WidgetTester.runAsync]: `toImage` and `toByteData`
  /// need the real async zone, and awaiting them under the test's fake clock
  /// deadlocks rather than failing.
  Future<void> shootNodes(
    WidgetTester tester,
    String name,
    List<List<MathNode>> lines, {
    bool levelSet = false,
    double? rangeZ,
    double? range,
  }) async {
    if (outDir == null) return;
    await tester.runAsync(() async {
      const Size size = Size(420, 420);
      final colors = AppColors.fromType(ThemeType.classic);
      final curves = lines.map(PlotExpression.compile).toList();
      for (int i = 0; i < curves.length; i++) {
        // A line that does not compile draws nothing, which in a render-only
        // test is indistinguishable from a painter bug.
        expect(
          curves[i].isValid,
          isTrue,
          reason: '$name line ${i + 1}: ${curves[i].error}',
        );
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF12161C),
      );
      Plot3DPainter(
        function: curves.first,
        functions: curves,
        is3DFunction: true,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: range ?? 5,
        rangeY: range ?? 5,
        rangeZ: rangeZ ?? range ?? (levelSet ? 5 : 12),
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: PlotThemeData.fromColors(colors),
      ).paint(canvas, size);

      final ui.Image img = await recorder.endRecording().toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(outDir).createSync(recursive: true);
      File(
        '$outDir/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
    });
  }

  /// Convenience for expressions a plain literal can express.
  Future<void> shoot(
    WidgetTester tester,
    String name,
    List<String> exprs, {
    bool levelSet = false,
    double? range,
  }) => shootNodes(
    tester,
    name,
    <List<MathNode>>[
      for (final String e in exprs) <MathNode>[LiteralNode(text: e)],
    ],
    levelSet: levelSet,
    range: range,
  );

  testWidgets('render one surface', (tester) async {
    await shoot(tester, 'surf_1', <String>['x^2+y^2']);
  });

  testWidgets('render two surfaces', (tester) async {
    await shoot(tester, 'surf_2', <String>['x^2+y^2', '20-x^2-y^2']);
  });

  testWidgets('render three surfaces', (tester) async {
    await shoot(tester, 'surf_3', <String>['x^2+y^2', '20-x^2-y^2', 'x*y']);
  });

  testWidgets('render two intersecting planes', (tester) async {
    await shoot(tester, 'surf_cross', <String>['2x', '2y']);
  });

  // sin/cos have to be built as TrigNodes. A LiteralNode holding the text
  // "sin(x)" does not compile — the engine reads "sin" as an unknown variable —
  // so writing them that way renders nothing at all and looks like a bug in the
  // painter.
  testWidgets('render sin(x) beside cos(y)', (tester) async {
    await shootNodes(tester, 'curves_xy', <List<MathNode>>[
      <MathNode>[
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'x')]),
      ],
      <MathNode>[
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'y')]),
      ],
    ]);
  });

  testWidgets('render sin(x), cos(y) and sin(z)', (tester) async {
    await shootNodes(tester, 'curves_xyz', <List<MathNode>>[
      <MathNode>[
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'x')]),
      ],
      <MathNode>[
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'y')]),
      ],
      <MathNode>[
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'z')]),
      ],
    ], rangeZ: 5);
  });

  testWidgets('render a curve beside a surface', (tester) async {
    await shootNodes(tester, 'curve_and_sheet', <List<MathNode>>[
      <MathNode>[
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'x')]),
      ],
      <MathNode>[LiteralNode(text: 'x^2+y^2')],
    ]);
  });

  testWidgets('render a unit sphere', (tester) async {
    await shoot(tester, 'level_sphere', <String>[
      'x^2+y^2+z^2=1',
    ], levelSet: true);
  });

  testWidgets('render a unit sphere framed close', (tester) async {
    // The box zoomed in to just past the sphere, which is how it looks on a
    // device once the plot has been pinched in. At this size the floor plane
    // cutting the equator is unmistakable.
    await shoot(
      tester,
      'level_sphere_close',
      <String>['x^2+y^2+z^2=1'],
      levelSet: true,
      range: 1.3,
    );
  });

  testWidgets('render a hyperboloid', (tester) async {
    await shoot(tester, 'level_hyper', <String>[
      'x^2+y^2-z^2=1',
    ], levelSet: true);
  });

  testWidgets('render two level surfaces', (tester) async {
    // Offset so they intersect. Concentric spheres would prove nothing: the
    // inner one is hidden by the outer whether or not the sort works.
    await shoot(tester, 'level_2', <String>[
      '(x-1.2)^2+y^2+z^2=4',
      '(x+1.2)^2+y^2+z^2=4',
    ], levelSet: true);
  });
}
