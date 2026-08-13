import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The trace marker for an equation lands on the equation.
///
/// Unit tests cover the solver; this covers the wiring, which is where the
/// fault actually was — the painter called evaluate() on every curve alike.
void main() {
  const Size canvas = Size(460, 460);
  const double span = 2.5; // window is -span..span on both axes

  double screenYFor(double dataY) =>
      canvas.height - (dataY + span) / (2 * span) * canvas.height;
  double screenXFor(double dataX) => (dataX + span) / (2 * span) * canvas.width;

  Future<ByteData> render(WidgetTester tester, {double? traceX}) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final colors = AppColors.fromType(ThemeType.classic);
      final curves = <PlotExpression>[
        PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2=1')]),
      ];
      expect(curves.first.isLevelSet, isTrue);

      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.drawRect(
        Offset.zero & canvas,
        Paint()..color = const Color(0xFF1A1A1A),
      );
      Plot2DPainter(
        function: curves.first,
        functions: curves,
        traceX: traceX,
        xMin: -span,
        xMax: span,
        yMin: -span,
        yMax: span,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: PlotThemeData.fromColors(colors),
      ).paint(c, canvas);

      final img = await recorder.endRecording().toImage(460, 460);
      pixels = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      img.dispose();
    });
    return pixels;
  }

  /// Rows where the two renders differ, sampled just beside the trace line.
  ///
  /// The line itself spans every row, so it is stepped over; the marker is a
  /// disc of radius 5 about the same column, so a few pixels across still
  /// falls inside it.
  Set<int> changedRows(ByteData off, ByteData on, double traceX) {
    final int w = canvas.width.toInt();
    final int col = screenXFor(traceX).round() + 3;
    final Set<int> rows = <int>{};
    // Skips the readout box at the top.
    for (int y = 70; y < canvas.height.toInt(); y++) {
      final int o = (y * w + col) * 4;
      for (int ch = 0; ch < 3; ch++) {
        if ((off.getUint8(o + ch) - on.getUint8(o + ch)).abs() > 20) {
          rows.add(y);
          break;
        }
      }
    }
    return rows;
  }

  testWidgets('markers sit on the circle, not at F(x, 0)', (tester) async {
    const double tx = 0.65;
    final ByteData off = await render(tester);
    final ByteData on = await render(tester, traceX: tx);
    final Set<int> rows = changedRows(off, on, tx);

    bool near(double dataY) {
      final int target = screenYFor(dataY).round();
      return rows.any((r) => (r - target).abs() <= 6);
    }

    // ±√(1 − 0.65²)
    expect(near(0.75993), isTrue, reason: 'no marker on the upper arc');
    expect(near(-0.75993), isTrue, reason: 'no marker on the lower arc');

    // F(0.65, 0) = 0.65² − 1, which is what used to be drawn.
    expect(
      near(-0.5775),
      isFalse,
      reason: 'a marker is still being placed at F(x, 0)',
    );
  });

  testWidgets('no marker where the circle does not reach', (tester) async {
    // The screenshots traced to x = 1.331, outside the circle, and a marker
    // was drawn anyway.
    const double tx = 1.331;
    final ByteData off = await render(tester);
    final ByteData on = await render(tester, traceX: tx);
    final Set<int> rows = changedRows(off, on, tx);

    final int bogus = screenYFor(1.331 * 1.331 - 1).round();
    expect(
      rows.any((r) => (r - bogus).abs() <= 6),
      isFalse,
      reason: 'the circle has no y here, so nothing should be marked',
    );
  });
}
