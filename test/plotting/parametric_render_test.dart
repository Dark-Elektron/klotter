import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A parametric curve has to reach the canvas, not merely compile.
///
/// Checked by rendering and reading pixels, because every earlier "is it
/// drawn?" test in this suite that asked the painter instead of the image
/// passed against a bug.
void main() {
  const Size canvas = Size(300, 300);
  const double span = 2; // window is -2..2 both ways

  Future<ui.Image> render(
    List<MathNode> nodes, {
    ParameterRange u = defaultParameterRange,
  }) async {
    final field = VectorFieldParser.fromNodes(nodes);
    final colors = AppColors.fromType(ThemeType.classic);
    final painter = Plot2DPainter(
      function: PlotExpression.compile(nodes),
      vectorParser: field,
      xMin: -span,
      xMax: span,
      yMin: -span,
      yMax: span,
      plotMode: PlotMode.function,
      fieldType: FieldType.vector,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
      uRange: u,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(
      canvas.width.toInt(),
      canvas.height.toInt(),
    );
  }

  /// Where the curve's colour lands, as a set of data-space radii.
  Future<List<double>> curveRadii(ui.Image image) async {
    final colors = AppColors.fromType(ThemeType.classic);
    final Color want = PlotThemeData.fromColors(colors).seriesColor(0);
    final data = (await image.toByteData())!;
    final List<double> radii = <double>[];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int o = (y * image.width + x) * 4;
        final int r = data.getUint8(o);
        final int g = data.getUint8(o + 1);
        final int b = data.getUint8(o + 2);
        final int a = data.getUint8(o + 3);
        // Close to the series colour, allowing for antialiasing at the edges.
        if (a > 200 &&
            (r - (want.r * 255)).abs() < 40 &&
            (g - (want.g * 255)).abs() < 40 &&
            (b - (want.b * 255)).abs() < 40) {
          final double dx = (x / image.width) * 2 * span - span;
          final double dy = span - (y / image.height) * 2 * span;
          radii.add(math.sqrt(dx * dx + dy * dy));
        }
      }
    }
    return radii;
  }

  List<MathNode> circleNodes() => <MathNode>[
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  testWidgets('cos(u)x̂ + sin(u)ŷ draws a circle of radius 1', (tester) async {
    await tester.runAsync(() async {
      final radii = await curveRadii(await render(circleNodes()));

      // Something was drawn at all.
      expect(radii.length, greaterThan(400), reason: '${radii.length} px');

      // And all of it sits on the unit circle. The tolerance is one pixel
      // wide in data terms plus the 3px stroke's half-width.
      final double pixel = 2 * span / canvas.width;
      for (final double r in radii) {
        expect(
          r,
          closeTo(1.0, 2.5 * pixel),
          reason: 'a lit pixel sits at radius $r, off the circle',
        );
      }
    });
  });

  testWidgets('the middle stays empty — it is a circle, not a disc', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final radii = await curveRadii(await render(circleNodes()));
      // Both halves matter: an empty canvas also has an empty middle, so the
      // ring has to be there for the hole to mean anything.
      expect(radii.where((r) => r > 0.9), isNotEmpty);
      expect(radii.where((r) => r < 0.8), isEmpty);
    });
  });

  testWidgets('a shorter sweep draws less of it', (tester) async {
    await tester.runAsync(() async {
      final full = await curveRadii(await render(circleNodes()));
      final half = await curveRadii(
        await render(circleNodes(), u: (min: 0.0, max: math.pi)),
      );
      // Half the turn, so roughly half the arc — checked loosely, since the
      // stroke's caps and joins are not proportional.
      expect(half.length, lessThan(full.length * 0.7));
      expect(half.length, greaterThan(full.length * 0.3));
    });
  });
}
