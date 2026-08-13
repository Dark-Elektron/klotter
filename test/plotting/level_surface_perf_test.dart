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

/// A level surface must stay affordable to drag once its floor and axes are
/// merged into the same back-to-front order as its triangles.
///
/// These are debug-build timings on a CPU canvas, not device timings. They
/// exist to catch an order-of-magnitude regression, so the limits are loose.
void main() {
  const Size canvas = Size(400, 400);

  /// Compiled once and reused, which is what the app does — a cell compiles on
  /// edit, not on every frame.
  ///
  /// This matters more than it looks. The marched mesh is cached against the
  /// expression's *identity*, so building a fresh PlotExpression per frame
  /// re-marches the surface and times the marching algorithm instead of the
  /// painter. Measured that way a 1,700-triangle sphere came out at 67 ms and
  /// looked like a drawing problem; with the cache warm it is 5 ms.
  final Map<String, PlotExpression> compiled = <String, PlotExpression>{};

  Plot3DPainter painterFor(String expr, double rotation) {
    final colors = AppColors.fromType(ThemeType.classic);
    final PlotExpression curve = compiled.putIfAbsent(
      expr,
      () => PlotExpression.compile(<MathNode>[LiteralNode(text: expr)]),
    );
    return Plot3DPainter(
      function: curve,
      functions: <PlotExpression>[curve],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: rotation,
      rangeX: 5,
      rangeY: 5,
      rangeZ: 5,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
    );
  }

  /// Median frame time, not the worst.
  ///
  /// The worst frame is whichever one the operating system chose to interrupt.
  /// Run on its own this test passed and under the full suite it did not, which
  /// measured the machine's load rather than the painter. The median ignores a
  /// single stalled frame while still moving if the painter genuinely slows.
  Future<double> medianFrame(WidgetTester tester, String expr) async {
    final List<double> frames = <double>[];
    await tester.runAsync(() async {
      // Warm-up frame pays for marching the mesh, as the first frame after an
      // edit does. Dragging only ever repaints an already-marched mesh.
      final warm = ui.PictureRecorder();
      painterFor(expr, 0.8).paint(Canvas(warm), canvas);
      warm.endRecording().dispose();

      for (int i = 0; i < 10; i++) {
        // A new angle each time, so no sort result can be reused.
        final painter = painterFor(expr, 0.8 + i * 0.05);
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

  testWidgets('a sphere repaints cheaply', (tester) async {
    // 1,656 triangles: the ordinary case, and the one a user drags.
    final double worst = await medianFrame(tester, 'x^2+y^2+z^2=1');
    expect(
      worst,
      lessThan(25),
      reason: 'median frame was ${worst.toStringAsFixed(1)} ms',
    );
  });

  testWidgets('the heaviest level surface stays in range', (tester) async {
    // 33,272 triangles, the worst in the suite. Interleaving the chrome costs
    // nothing measurable here — batching the flushes between 1 and 1,000,000
    // moved this by less than the run-to-run noise, so the cost is the
    // triangles themselves.
    final double worst = await medianFrame(tester, 'x^2+y^2-z^2=1');
    expect(
      worst,
      lessThan(90),
      reason: 'median frame was ${worst.toStringAsFixed(1)} ms',
    );
  });
}
