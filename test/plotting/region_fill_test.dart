import 'dart:math';
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

/// Where the shading of a 2D inequality ends.
///
/// It was whole cells of a lattice, each shaded or not by the value at its
/// centre, so every curved edge was a staircase — up to a cell's half-diagonal
/// out from the boundary, on either side. On a tablet a cell was a dozen
/// pixels across and the steps showed well past the boundary line drawn over
/// them. The shading is now cut along the boundary.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression fn(String t) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: t),
    ]);
    expect(e.isValid, isTrue, reason: '$t: ${e.error}');
    return e;
  }

  Plot2DPainter painter(PlotExpression f, double half) => Plot2DPainter(
    function: f,
    xMin: -half,
    xMax: half,
    yMin: -half,
    yMax: half,
    plotMode: PlotMode.function,
    fieldType: FieldType.scalar,
    showContour: false,
    showAxes: false,
    surfaceMode: SurfaceMode.none,
    colors: colors,
    plotTheme: theme,
  );

  /// Whether the shading of [line], over ±[half] on a [size] canvas, covers
  /// the point of the plane at radius [r] and angle [a].
  bool Function(double r, double a) shadingOf(
    String line, {
    double half = 1.2,
    Size size = const Size(300, 300),
  }) {
    final Path region = painter(fn(line), half).regionPath(fn(line), size);
    return (double r, double a) => region.contains(
      Offset(
        (r * cos(a) + half) / (2 * half) * size.width,
        (half - r * sin(a)) / (2 * half) * size.height,
      ),
    );
  }

  /// Every whole degree round the circle.
  final List<double> angles = <double>[
    for (int d = 0; d < 360; d++) d * pi / 180,
  ];

  test('a disc is shaded up to its edge and no further', () {
    // A lattice cell here is 0.022 across, so the staircase reached 0.015
    // either side of the circle; 0.01 is well inside it.
    final bool Function(double, double) disc = shadingOf('x^2+y^2<1');
    for (final double a in angles) {
      expect(disc(0.99, a), isTrue, reason: 'unshaded inside, at $a');
      expect(disc(1.01, a), isFalse, reason: 'shaded outside, at $a');
    }
  });

  test('and outside it, for the other direction', () {
    final bool Function(double, double) outside = shadingOf('x^2+y^2>1');
    for (final double a in angles) {
      expect(outside(1.01, a), isTrue, reason: 'unshaded outside, at $a');
      expect(outside(0.99, a), isFalse, reason: 'shaded inside, at $a');
    }
  });

  test('an annulus, on a tablet-sized panel', () {
    // The case that was reported: 1 < x² + y² < 3, on a wide panel.
    final bool Function(double, double) ring = shadingOf(
      '1<x^2+y^2<3',
      half: 2,
      size: const Size(1200, 1200),
    );
    final double outer = sqrt(3);
    for (final double a in angles) {
      expect(ring(1.01, a), isTrue, reason: 'inner edge, at $a');
      expect(ring(outer - 0.01, a), isTrue, reason: 'outer edge, at $a');
      expect(ring(0.99, a), isFalse, reason: 'the hole, at $a');
      expect(ring(outer + 0.01, a), isFalse, reason: 'past the ring, at $a');
    }
  });

  test('a straight edge is exactly where it is', () {
    // y < 0.37x + 0.05 is linear, and interpolating a linear value between
    // corners finds its zero exactly: within a hair of the line on both sides.
    final Path region = painter(
      fn('y<0.37x+0.05'),
      1.2,
    ).regionPath(fn('y<0.37x+0.05'), const Size(300, 300));
    Offset at(double x, double y) =>
        Offset((x + 1.2) / 2.4 * 300, (1.2 - y) / 2.4 * 300);
    for (double x = -1.15; x < 1.15; x += 0.0137) {
      final double y = 0.37 * x + 0.05;
      expect(region.contains(at(x, y - 0.002)), isTrue, reason: 'below at $x');
      expect(region.contains(at(x, y + 0.002)), isFalse, reason: 'above at $x');
    }
  });

  testWidgets('the shading is one even tint, without seams between cells', (
    tester,
  ) async {
    // Cells cut along the boundary meet whole ones beside and above them; if
    // they met with a hairline gap or overlap, it would show as a line of a
    // different shade within a cell of the boundary. At this size a cell is
    // not a whole number of pixels, so where cells meet is partway across a
    // pixel, and antialiasing has something to get wrong.
    const Size size = Size(1210, 1210);
    const double half = 1.2;
    late ByteData pixels;
    await tester.runAsync(() async {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painter(fn('y<0.37x+0.05'), half).paint(Canvas(recorder), size);
      final ui.Image image = await recorder.endRecording().toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    int channel(int x, int y, int c) =>
        pixels.getUint8((y * size.width.toInt() + x) * 4 + c);

    // Deep in the region, and the boundary as a line on screen: y = m x + k.
    final double perUnit = size.width / (2 * half);
    const double m = 0.37, k = 0.05;
    double below(int px, int py) {
      final double x = px / perUnit - half, y = half - py / perUnit;
      return (m * x + k - y) * perUnit / sqrt(1 + m * m);
    }

    const int refX = 605, refY = 1000;
    expect(below(refX, refY), greaterThan(100));
    int uneven = 0;
    String? first;
    for (int py = 40; py < 1170; py++) {
      for (int px = 40; px < 1170; px++) {
        // Clear of the 3 px boundary stroke and its antialiasing, and within
        // two cells of the boundary, where the cut cells are.
        final double d = below(px, py);
        if (d < 3.5 || d > 14) continue;
        for (int c = 0; c < 3; c++) {
          if ((channel(px, py, c) - channel(refX, refY, c)).abs() > 2) {
            uneven++;
            first ??= '($px, $py), ${d.toStringAsFixed(1)} px from the edge';
            break;
          }
        }
      }
    }
    expect(uneven, 0, reason: '$uneven pixels off the tint, first at $first');
  });
}
