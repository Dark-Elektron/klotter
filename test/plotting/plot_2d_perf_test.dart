import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A 2D plot has to stay affordable while the window is moving.
///
/// Implicit curves and shaded regions are the expensive ones, and their
/// caches key on the window — so a pan misses on every frame and pays the full
/// sampling cost each time. That is exactly when smoothness matters, so these
/// measure a moving window rather than a still one.
///
/// Debug-build timings on a CPU canvas, and a median rather than a worst
/// frame: the slowest frame measures whatever else the machine was doing.
void main() {
  const Size canvas = Size(400, 700);
  final Map<String, PlotExpression> compiled = <String, PlotExpression>{};

  Future<double> medianFrame(WidgetTester tester, String expr) async {
    final colors = AppColors.fromType(ThemeType.classic);
    final theme = PlotThemeData.fromColors(colors);
    final PlotExpression curve = compiled.putIfAbsent(
      expr,
      () => PlotExpression.compile(<MathNode>[LiteralNode(text: expr)]),
    );

    final List<double> frames = <double>[];
    await tester.runAsync(() async {
      Plot2DPainter painter(double shift) => Plot2DPainter(
        function: curve,
        functions: <PlotExpression>[curve],
        xMin: -5 - shift,
        xMax: 5 - shift,
        yMin: -5,
        yMax: 5,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: theme,
      );

      final warm = ui.PictureRecorder();
      painter(0).paint(Canvas(warm), canvas);
      warm.endRecording().dispose();

      for (int i = 1; i <= 9; i++) {
        // A different window each frame, as a pan gives: the cache cannot
        // help, which is the case worth measuring.
        final p = painter(i * 0.02);
        final r = ui.PictureRecorder();
        final sw = Stopwatch()..start();
        p.paint(Canvas(r), canvas);
        sw.stop();
        r.endRecording().dispose();
        frames.add(sw.elapsedMicroseconds / 1000);
      }
    });
    frames.sort();
    return frames[frames.length ~/ 2];
  }

  /// The sampling grids, which are what the frame cost is made of.
  ///
  /// This is the guard that actually holds. A wall-clock limit cannot do the
  /// job here: tight enough to catch the regression these numbers fixed
  /// (19.3 ms for an implicit curve, over a 60 Hz frame) and it fails whenever
  /// the rest of the suite is running alongside; loose enough to survive that
  /// and it would not have caught the regression at all. The grid sizes are
  /// the cause, and they are deterministic.
  group('the sampling grids stay proportionate to the screen', () {
    test('marching squares samples about as finely as pixels', () {
      // 150 on a side over a plot ~400 px wide is ~2.7 px per cell, finer than
      // the 3 px curve drawn through it. It was 220 — 48,000 samples a frame,
      // and the cache cannot help during a pan because its key is the window.
      // Dropping to 150 took the frame from 19.3 ms to 7.6 ms.
      // Two grids, because the two situations are different. A still plot
      // can afford a fine one — its geometry is cached and costs nothing to
      // redraw — while a moving one re-samples every frame and cannot.
      expect(
        marchingSquaresDraggingResolution,
        lessThanOrEqualTo(160),
        reason: 'a finer grid while dragging costs frames a pan cannot spare',
      );
      expect(
        marchingSquaresDefaultResolution,
        greaterThanOrEqualTo(240),
        reason:
            'at rest the curve should be as smooth as it can be; '
            'r = 1 + cos(θ) turns visibly polygonal below this',
      );
      expect(
        marchingSquaresDraggingResolution,
        lessThan(marchingSquaresDefaultResolution),
      );
    });
  });

  group('smoke: nothing has become wildly slow', () {
    // Deliberately very loose. These run alongside the rest of the suite, and
    // a wall clock there measures whatever else the machine is doing more
    // than it measures the painter — tighter numbers flapped twice. The real
    // guard is the grid size above, which is deterministic; these only catch
    // something becoming slow by an order of magnitude.
    testWidgets('an ordinary curve', (tester) async {
      final double ms = await medianFrame(tester, 'x^2');
      expect(ms, lessThan(120), reason: '${ms.toStringAsFixed(1)} ms');
    });

    testWidgets('an implicit curve', (tester) async {
      final double ms = await medianFrame(tester, 'x^2+y^2=4');
      expect(ms, lessThan(180), reason: '${ms.toStringAsFixed(1)} ms');
    });

    testWidgets('a shaded region', (tester) async {
      final double ms = await medianFrame(tester, 'x^2+y^2<4');
      expect(ms, lessThan(240), reason: '${ms.toStringAsFixed(1)} ms');
    });
  });
}
