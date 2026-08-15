import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Sweeping u and v has to produce a sheet on screen, not a line.
///
/// Measured by differencing against the bare axes rather than by matching a
/// colour: the mesh is shaded per cell, so there is no single colour to look
/// for — which is itself the point of shading it.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const ParameterRange small = (min: -1.0, max: 1.0);
  const ParameterRange big = (min: -3.0, max: 3.0);

  /// `k·u x̂ + k·v ŷ` — a flat patch in the z = 0 plane.
  List<MathNode> patchNodes() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+v'),
    UnitVectorNode('y'),
  ];

  /// A curve: only u appears.
  List<MathNode> curveNodes() => <MathNode>[
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  Future<ui.Image> render(
    List<MathNode> nodes, {
    ParameterRange u = small,
    ParameterRange v = small,
  }) async {
    final expr = PlotExpression.compile(nodes);
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      vectorParser: VectorFieldParser.fromNodes(nodes),
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: 5,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.vector,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
      uRange: u,
      vRange: v,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(
      canvas.width.toInt(),
      canvas.height.toInt(),
    );
  }

  /// How many pixels [image] differs from the same scene with no mesh in it.
  ///
  /// The baseline is a *parametric* render with a zero-width v sweep, not bare
  /// axes: a parametric cell draws the floor through the depth scene while an
  /// ordinary one draws it directly, and differencing across those two paths
  /// measured the floor rather than the surface.
  Future<int> coverage(ui.Image image) async {
    final ui.Image bare = await render(patchNodes(), v: (min: 0.0, max: 0.0));
    final a = (await image.toByteData())!;
    final b = (await bare.toByteData())!;
    int differing = 0;
    for (int i = 0; i < image.width * image.height; i++) {
      final int o = i * 4;
      for (int ch = 0; ch < 4; ch++) {
        if ((a.getUint8(o + ch) - b.getUint8(o + ch)).abs() > 12) {
          differing++;
          break;
        }
      }
    }
    return differing;
  }

  testWidgets('a u-v patch covers a sheet of the canvas', (tester) async {
    await tester.runAsync(() async {
      final int lit = await coverage(
        await render(patchNodes(), u: big, v: big),
      );
      expect(lit, greaterThan(3000), reason: 'only $lit px changed');
    });
  });

  testWidgets('a wider sweep covers more', (tester) async {
    await tester.runAsync(() async {
      final int narrow = await coverage(await render(patchNodes()));
      final int wide = await coverage(
        await render(patchNodes(), u: big, v: big),
      );
      expect(
        wide,
        greaterThan(narrow * 2),
        reason: '±1 covered $narrow px, ±3 covered $wide',
      );
    });
  });

  testWidgets('a curve is still a curve, not a sheet', (tester) async {
    await tester.runAsync(() async {
      // Only u appears, so this must stay a line — a mesh here would mean the
      // surface path had claimed it.
      final int curve = await coverage(await render(curveNodes()));
      final int sheet = await coverage(await render(patchNodes()));
      expect(
        curve * 3,
        lessThan(sheet),
        reason: 'curve covered $curve px against the sheet\'s $sheet',
      );
    });
  });

  testWidgets('the sheet is shaded, not a flat silhouette', (tester) async {
    await tester.runAsync(() async {
      // A saddle folds away from the viewer, so its cells face different ways
      // and must not all come out the same colour.
      final saddle = <MathNode>[
        LiteralNode(text: 'u'),
        UnitVectorNode('x'),
        LiteralNode(text: '+v'),
        UnitVectorNode('y'),
        LiteralNode(text: '+u*v'),
        UnitVectorNode('z'),
      ];
      final image = await render(saddle, u: big, v: big);
      final data = (await image.toByteData())!;
      final Set<int> tones = <int>{};
      for (int i = 0; i < image.width * image.height; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) > 200) {
          tones.add(data.getUint8(o) ~/ 8);
        }
      }
      expect(tones.length, greaterThan(6), reason: '${tones.length} tones');
    });
  });
}
