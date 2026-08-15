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

/// The parametric mesh has no cache behind it — a drag re-sweeps the whole
/// grid every frame — so raising the still-frame resolution has to be paid for
/// by dropping it again while a finger is down.
///
/// These are debug-build timings on a CPU canvas, not device timings. They
/// exist to catch an order-of-magnitude regression, so the limits are loose;
/// the tight guarantee is the grid-size assertion at the bottom, which is
/// deterministic.
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

  Plot3DPainter painterFor({
    required bool interacting,
    required double rotation,
  }) {
    final nodes = torusish();
    final expr = PlotExpression.compile(nodes);
    return Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      vectorParser: VectorFieldParser.fromNodes(nodes),
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
    // Measured at 32 ms for the 96-step grid, against 5 ms while dragging.
    // A still frame is only repainted when something changes, so 32 ms buys
    // the resolution without costing anyone a gesture.
    final double t = await medianFrame(tester, moving: false);
    expect(
      t,
      lessThan(120),
      reason: 'median frame was ${t.toStringAsFixed(1)} ms',
    );
  });

  testWidgets('dragging one costs less than holding it still', (tester) async {
    // The whole point of the coarser moving grid. Measured together in one
    // test so both numbers come from the same machine under the same load.
    final double still = await medianFrame(tester, moving: false);
    final double moving = await medianFrame(tester, moving: true);
    expect(
      moving,
      lessThan(still),
      reason:
          'still ${still.toStringAsFixed(1)} ms, '
          'moving ${moving.toStringAsFixed(1)} ms',
    );
  });

  test('the moving grid is the coarser of the two', () {
    // The deterministic half of this file: whatever the timings do on a
    // loaded machine, dragging must never sweep more finely than resting.
    expect(parametricSurfaceStepsMoving, lessThan(parametricSurfaceSteps));
  });
}
