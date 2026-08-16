import 'dart:math';
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

/// The parametric mesh is drawn at one resolution whether the plot is moving
/// or not, so a spin does not visibly coarsen it.
///
/// These are debug-build timings on a CPU canvas, not device timings. They
/// exist to catch an order-of-magnitude regression, so the limits are loose.
void main() {
  const Size canvas = Size(400, 400);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  List<MathNode> torusish() => <MathNode>[
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'v')]),
    UnitVectorNode('y'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u+v')]),
    UnitVectorNode('z'),
  ];

  // Compiled once and reused, which is what the app does: a cell parses on
  // edit, not per frame. It also matters for what is measured — the sweep is
  // cached against the parser's identity, so a fresh one each frame would
  // time the sampler rather than the painter.
  final nodes = torusish();
  final expr = PlotExpression.compile(nodes);
  final field = VectorFieldParser.fromNodes(nodes);

  Plot3DPainter painterFor({
    required bool interacting,
    required double rotation,
  }) {
    return Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      vectorParser: field,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: rotation,
      rangeX: 5,
      rangeY: 5,
      rangeZ: 5,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.vector,
      showContour: false,
      surfaceMode: SurfaceMode.magnitude,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
      interacting: interacting,
    );
  }

  /// Median frame, not the worst.
  ///
  /// The worst frame is whichever one the operating system chose to interrupt.
  /// Under the full suite that measures the machine's load rather than the
  /// painter.
  Future<double> medianFrame(
    WidgetTester tester, {
    required bool moving,
  }) async {
    final List<double> frames = <double>[];
    await tester.runAsync(() async {
      for (int i = 0; i < 7; i++) {
        final painter = painterFor(
          interacting: moving,
          rotation: 0.8 + i * 0.05,
        );
        final r = ui.PictureRecorder();
        final sw = Stopwatch()..start();
        painter.paint(Canvas(r), canvas);
        sw.stop();
        r.endRecording().dispose();
        frames.add(sw.elapsedMicroseconds / 1000);
      }
    });
    frames.sort();
    return frames[frames.length ~/ 2];
  }

  testWidgets('a still parametric surface repaints in range', (tester) async {
    // The budget is spent to land near 8,100 cells however it is split, so
    // this is close to the 9,216-cell figure of 23 ms measured while tuning.
    final double t = await medianFrame(tester, moving: false);
    expect(
      t,
      lessThan(60),
      reason: 'median frame was ${t.toStringAsFixed(1)} ms',
    );
  });

  testWidgets('moving and still cost the same', (tester) async {
    // They are the same mesh. The surface used to thin out under a finger,
    // which is the usual bargain for geometry with no cache behind it — but a
    // spin outlives the finger, so the plot visibly degraded and stayed that
    // way until it stopped. One resolution, sized to be affordable while
    // moving, is the price of not doing that.
    final double still = await medianFrame(tester, moving: false);
    final double moving = await medianFrame(tester, moving: true);
    expect(
      (moving - still).abs(),
      lessThan(still * 0.75 + 5),
      reason:
          'still ${still.toStringAsFixed(1)} ms, '
          'moving ${moving.toStringAsFixed(1)} ms',
    );
  });

  test('the two parameters are given steps in proportion to their travel', () {
    // The fix for the faceting: one count for both directions gave a spiral
    // over u in [0, 35] only eleven samples per revolution, while v — which
    // barely moves — got just as many. The budget now follows the geometry.
    final field = VectorFieldParser.fromNodes(torusish())!;
    final spiral =
        VectorFieldParser.fromNodes(<MathNode>[
          TrigNode(
            function: 'sin',
            argument: <MathNode>[LiteralNode(text: 'u')],
          ),
          UnitVectorNode('x'),
          LiteralNode(text: '+'),
          TrigNode(
            function: 'cos',
            argument: <MathNode>[LiteralNode(text: 'u')],
          ),
          UnitVectorNode('y'),
          LiteralNode(text: '+v'),
          UnitVectorNode('z'),
        ])!;

    final wide = parametricGridFor(
      spiral,
      u: (min: 0.0, max: 35.0),
      v: (min: 1.0, max: 7.0),
    );
    // Five and a half turns in u against almost nothing in v.
    expect(wide.u, greaterThan(wide.v * 2), reason: 'u ${wide.u} v ${wide.v}');
    // Enough per revolution that the circle is not a polygon. At the old
    // shared count of 64 this was eleven.
    expect(wide.u / (35 / (2 * pi)), greaterThan(25));

    // Whatever the split, the cost stays put.
    for (final f in <VectorFieldParser>[field, spiral]) {
      final g = parametricGridFor(f);
      expect(g.u * g.v, lessThan(parametricCellBudget * 1.3));
      expect(g.u * g.v, greaterThan(parametricCellBudget * 0.7));
    }
  });

  test('a direction that never moves still gets enough steps to shade', () {
    // A flat patch travels the same distance either way, so neither runs to
    // the floor of the clamp — but the clamp is what stops one collapsing.
    final flat =
        VectorFieldParser.fromNodes(<MathNode>[
          LiteralNode(text: 'u'),
          UnitVectorNode('x'),
          LiteralNode(text: '+v'),
          UnitVectorNode('y'),
        ])!;
    final g = parametricGridFor(flat);
    expect(g.u, greaterThanOrEqualTo(parametricMinSteps));
    expect(g.v, greaterThanOrEqualTo(parametricMinSteps));
  });

  test('the sweep is cached, so turning the plot does not re-sample it', () {
    // Sampling was never the cost of a frame — projecting and sorting is —
    // but re-walking the expression 4,225 times per frame is still waste.
    final nodes = torusish();
    final field = VectorFieldParser.fromNodes(nodes)!;
    final a = cachedParametricSurface(field);
    final b = cachedParametricSurface(field);
    expect(identical(a, b), isTrue);
  });
}
