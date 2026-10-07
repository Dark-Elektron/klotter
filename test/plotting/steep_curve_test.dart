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

/// Where a curve y = f(x) is joined between samples and where it is broken.
///
/// A rise of more than half the window between two neighbouring samples used
/// to break the curve, which is right at a pole and wrong on a steep line:
/// y = 2000x rises that far on every step, so it was never drawn at all. And
/// points past |y| = 1e6 were dropped, so zoomed out far enough the same line
/// stopped short of the edges.
void main() {
  const Size canvas = Size(300, 300);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression fn(String t) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

  Plot2DPainter painter(
    PlotExpression f, {
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
  }) => Plot2DPainter(
    function: f,
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
    plotMode: PlotMode.function,
    fieldType: FieldType.scalar,
    showContour: false,
    showAxes: false,
    surfaceMode: SurfaceMode.none,
    colors: colors,
    plotTheme: theme,
  );

  Future<ByteData> rasterise(WidgetTester tester, CustomPainter p) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(
        canvas.width.toInt(),
        canvas.height.toInt(),
      );
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return pixels;
  }

  /// Which pixels the curve covers: where a render of [line] differs from a
  /// render of the same window with nothing in it. [line] is the text of a
  /// plain expression, or its nodes where it needs more than text — a trig
  /// function is a node of its own.
  Future<bool Function(int x, int y)> curveOf(
    WidgetTester tester,
    Object line, {
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
  }) async {
    final PlotExpression f =
        line is List<MathNode> ? PlotExpression.compile(line) : fn('$line');
    expect(f.isValid, isTrue, reason: '$line: ${f.error}');
    final ByteData drawn = await rasterise(
      tester,
      painter(f, xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax),
    );
    final ByteData empty = await rasterise(
      tester,
      painter(
        PlotExpression.invalid,
        xMin: xMin,
        xMax: xMax,
        yMin: yMin,
        yMax: yMax,
      ),
    );
    final int w = canvas.width.toInt();
    return (int x, int y) {
      final int o = (y * w + x) * 4;
      for (int c = 0; c < 3; c++) {
        if ((drawn.getUint8(o + c) - empty.getUint8(o + c)).abs() > 24) {
          return true;
        }
      }
      return false;
    };
  }

  /// Whether the curve covers any pixel within [r] of (x, y).
  bool near(bool Function(int, int) curve, int x, int y, {int r = 3}) {
    for (int dy = -r; dy <= r; dy++) {
      for (int dx = -r; dx <= r; dx++) {
        final int px = x + dx, py = y + dy;
        if (px < 0 || py < 0 || px >= 300 || py >= 300) continue;
        if (curve(px, py)) return true;
      }
    }
    return false;
  }

  testWidgets('a steep line is drawn, not broken at every step', (
    tester,
  ) async {
    // Over x in ±10 a step is 0.02, which y = 2000x climbs by 40 — twice the
    // height of the window. The line crosses it in the middle, top to bottom.
    final bool Function(int, int) curve = await curveOf(
      tester,
      '2000x',
      xMin: -10,
      xMax: 10,
      yMin: -10,
      yMax: 10,
    );
    int rows = 0;
    for (int y = 20; y < 280; y++) {
      if (near(curve, 150, y)) rows++;
    }
    expect(rows, 260, reason: 'the line was drawn in only $rows of 260 rows');
  });

  testWidgets('zoomed far out, a steep line still runs edge to edge', (
    tester,
  ) async {
    // The diagonal of the window. Past x = 500, y = 2000x is over 1e6, which
    // is where points used to be dropped — the line stopped a twentieth of
    // the way out from the middle.
    final bool Function(int, int) curve = await curveOf(
      tester,
      '2000x',
      xMin: -1e4,
      xMax: 1e4,
      yMin: -2e7,
      yMax: 2e7,
    );
    expect(near(curve, 30, 270), isTrue, reason: 'missing near bottom left');
    expect(near(curve, 270, 30), isTrue, reason: 'missing near top right');
    expect(near(curve, 150, 150), isTrue, reason: 'missing in the middle');
  });

  testWidgets('a pole is still not joined across', (tester) async {
    // Asymmetric, so no sample lands on x = 0 itself and the two either side
    // of the pole have to be told apart by looking between them.
    final bool Function(int, int) curve = await curveOf(
      tester,
      '1/x',
      xMin: -1,
      xMax: 1.001,
      yMin: -10,
      yMax: 10,
    );
    // Through the middle rows 1/x is out near x = ±1. A join across the pole
    // is a vertical line down the middle column.
    for (int y = 120; y <= 180; y++) {
      for (int x = 140; x <= 160; x++) {
        expect(curve(x, y), isFalse, reason: 'drawn across the pole at $x,$y');
      }
    }
    // While the curve itself is there: at x = -0.9, y = 1/x is about -1.1.
    expect(near(curve, 15, 167, r: 6), isTrue, reason: '1/x itself is missing');
  });

  testWidgets('nor is tan across its asymptotes', (tester) async {
    final bool Function(int, int) curve = await curveOf(
      tester,
      <MathNode>[
        TrigNode(function: 'tan', argument: <MathNode>[LiteralNode(text: 'x')]),
      ],
      xMin: -2,
      xMax: 2.003,
      yMin: -10,
      yMax: 10,
    );
    // x = ±π/2 lands at columns 32 and 268; the branches that pass through
    // the middle rows are nowhere near either.
    for (final int column in <int>[32, 268]) {
      for (int y = 120; y <= 180; y++) {
        for (int x = column - 5; x <= column + 5; x++) {
          expect(curve(x, y), isFalse, reason: 'joined across at $x,$y');
        }
      }
    }
    expect(near(curve, 150, 150), isTrue, reason: 'tan itself is missing');
  });
}
