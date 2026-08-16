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

/// The colour ramp is scaled over what is on screen, not over every value the
/// function reaches.
///
/// This is what went wrong when cells began being cut at the box wall: the
/// range was taken before the window was applied, so a function that climbs
/// far above the box mapped its whole visible part into the bottom of the
/// ramp. |(x + yi)²| reaches 50 at the corners of a ±5 floor while only the
/// first 5 of that is inside the box, and the surface came out uniformly blue.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  /// A steep bowl, so most of what it reaches lies outside any modest box.
  PlotExpression bowl() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2')]);

  Future<ui.Image> render({required double rangeZ}) async {
    final expr = bowl();
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: rangeZ,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.magnitude,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(320, 320);
  }

  /// The share of the surface's colour falling in whichever hue is commonest.
  ///
  /// A ramp scaled over what is drawn spreads across the wheel; one scaled
  /// over values that are mostly off screen piles into the bottom of it.
  Future<double> concentration(ui.Image image) async {
    final data = (await image.toByteData())!;
    final List<int> buckets = List<int>.filled(18, 0);
    int total = 0;
    for (int i = 0; i < 320 * 320; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) < 200) continue;
      final HSVColor hsv = HSVColor.fromColor(
        Color.fromARGB(
          255,
          data.getUint8(o),
          data.getUint8(o + 1),
          data.getUint8(o + 2),
        ),
      );
      if (hsv.saturation < 0.3 || hsv.value < 0.2) continue;
      buckets[(hsv.hue / 20).floor() % 18]++;
      total++;
    }
    if (total == 0) return 1;
    return buckets.reduce((a, b) => a > b ? a : b) / total;
  }

  test('the expression under test plots as a surface', () {
    final e = bowl();
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isSurface, isTrue);
  });

  testWidgets('a surface cut by the box still uses the whole ramp', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Only a tenth of what the bowl reaches is inside this box. Scaled over
      // everything it reaches, the visible part would be one colour.
      final double tight = await concentration(await render(rangeZ: 5));
      // Measured at 0.52 with the range taken over what is drawn, against
      // effectively 1 when it was taken over everything the function reaches.
      // Not lower because of geometry rather than colour: on a bowl most of
      // the visible *area* sits at large radius, so most of the surface
      // genuinely is near the top of its range.
      expect(
        tight,
        lessThan(0.7),
        reason: 'a single hue holds $tight of the surface',
      );
    });
  });

  testWidgets('and one that fits behaves the same way', (tester) async {
    await tester.runAsync(() async {
      // The control: nothing is cut here, so this is the case that always
      // worked. If it were flat too, the test above would be measuring
      // something other than the range.
      final double roomy = await concentration(await render(rangeZ: 50));
      expect(roomy, lessThan(0.6), reason: 'a single hue holds $roomy');
    });
  });
}
