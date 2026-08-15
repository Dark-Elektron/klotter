import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The colorbar runs along the top of the plot, low value at the left.
///
/// Checked by reading the ramp's own end colours off the canvas, which pins
/// down both where the bar is and which way round it runs — a bar drawn
/// backwards would still be a bar in the right place.
void main() {
  const Size canvas = Size(400, 300);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  Future<ui.Image> render() async {
    final expr = PlotExpression.compile(<MathNode>[LiteralNode(text: 'x+y')]);
    final painter = Plot2DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      xMin: -5,
      xMax: 5,
      yMin: -5,
      yMax: 5,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.magnitude,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(400, 300);
  }

  late ui.Image image;
  late ByteData pixels;

  setUpAll(() async {
    image = await render();
    pixels = (await image.toByteData())!;
  });

  Color at(int x, int y) {
    final int o = (y * image.width + x) * 4;
    return Color.fromARGB(
      pixels.getUint8(o + 3),
      pixels.getUint8(o),
      pixels.getUint8(o + 1),
      pixels.getUint8(o + 2),
    );
  }

  /// How far apart two colours are, 0..1 per channel summed.
  double distance(Color a, Color b) =>
      (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

  // 45% of 400 = 180, inside the 80..220 clamp.
  const double barWidth = 180;
  const double barLeft = (400 - barWidth) / 2;
  const int mid = 16; // 10px margin + half of a 12px bar

  test('the bar sits across the top centre', () {
    // Its left end carries the bottom of the ramp.
    expect(
      distance(at(barLeft.toInt() + 3, mid), plotColormapStops.first),
      lessThan(0.35),
      reason: 'left end is ${at(barLeft.toInt() + 3, mid)}',
    );
  });

  test('it runs low to high, left to right', () {
    expect(
      distance(
        at((barLeft + barWidth).toInt() - 3, mid),
        plotColormapStops.last,
      ),
      lessThan(0.35),
      reason: 'right end is ${at((barLeft + barWidth).toInt() - 3, mid)}',
    );
  });

  test('the old spot down the left edge is clear', () {
    // Where the vertical bar used to be — now the parameter panels' corner.
    for (int y = 100; y < 200; y += 10) {
      expect(
        distance(at(14, y), plotColormapStops.first),
        greaterThan(0.15),
        reason: 'ramp colour still at (14, $y)',
      );
    }
  });
}
