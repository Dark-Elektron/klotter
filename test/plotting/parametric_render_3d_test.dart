import 'dart:math' as math;
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

/// A parametric sweep has to reach the 3D canvas too, and join the same
/// back-to-front order as the floor so the box can occlude it.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  /// `cos(u) x̂ + sin(u) ŷ` scaled by [radius] — a circle in the z = 0 plane.
  List<MathNode> circleNodes({String radius = ''}) => <MathNode>[
    if (radius.isNotEmpty) LiteralNode(text: radius),
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+$radius'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  Future<ui.Image> render(
    List<MathNode> nodes, {
    // A full turn, not the [0, 1] default: these are circles.
    ParameterRange u = fullTurn,
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
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(
      canvas.width.toInt(),
      canvas.height.toInt(),
    );
  }

  /// Pixels close to the curve's colour.
  Future<int> curvePixels(ui.Image image) async {
    final Color want = theme.seriesColor(0);
    final data = (await image.toByteData())!;
    int count = 0;
    for (int i = 0; i < image.width * image.height; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) > 200 &&
          (data.getUint8(o) - want.r * 255).abs() < 30 &&
          (data.getUint8(o + 1) - want.g * 255).abs() < 30 &&
          (data.getUint8(o + 2) - want.b * 255).abs() < 30) {
        count++;
      }
    }
    return count;
  }

  testWidgets('a parametric circle is drawn in 3D', (tester) async {
    await tester.runAsync(() async {
      final int lit = await curvePixels(await render(circleNodes()));
      // A radius-1 circle inside a range-5 box is small on screen; measured
      // at 139 px on the square test canvas, so this catches it
      // disappearing, not it being thin.
      expect(lit, greaterThan(90), reason: 'only $lit px of curve colour');
    });
  });

  testWidgets('a larger circle covers more of the box', (tester) async {
    await tester.runAsync(() async {
      final int small = await curvePixels(await render(circleNodes()));
      final int big = await curvePixels(await render(circleNodes(radius: '3')));
      expect(
        big,
        greaterThan(small * 2),
        reason: 'radius 1 lit $small px, radius 3 lit $big',
      );
    });
  });

  testWidgets('a sweep of zero width draws nothing', (tester) async {
    await tester.runAsync(() async {
      // Every sample lands on the same point, so there is no segment to draw.
      final int lit = await curvePixels(
        await render(circleNodes(), u: (min: 1.0, max: 1.0)),
      );
      expect(lit, lessThan(20), reason: '$lit px from a zero-width sweep');
    });
  });

  testWidgets('a curve outside the box is clipped, not clamped to the wall', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Radius 8 against a range of 5: the parts beyond the box must vanish
      // rather than pile up along its edge.
      final int lit = await curvePixels(await render(circleNodes(radius: '8')));
      final int inside = await curvePixels(
        await render(circleNodes(radius: '3')),
      );
      expect(
        lit,
        lessThan(inside),
        reason: 'clipped circle lit $lit px, the contained one $inside',
      );
    });
  });

  test('the sweep itself closes on the unit circle', () {
    final field = VectorFieldParser.fromNodes(circleNodes())!;
    final pts = sampleParametricCurve(field);
    for (final p in pts) {
      expect(math.sqrt(p!.x * p.x + p.y * p.y), closeTo(1, 1e-9));
    }
  });
}
