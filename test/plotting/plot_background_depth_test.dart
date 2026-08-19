import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The lighting behind the plot.
///
/// The ground was a vignette, was deliberately flattened, and is a vignette
/// again at a fraction of the old strength. The reason for flattening it has
/// not gone away — a ground that varies in lightness argues with a colour ramp,
/// because the same blue reads differently at the rim than at the centre — so
/// what matters is not that a gradient exists but *how far* it swings.
///
/// Composited over an opaque ground, because the plot panel is translucent in
/// most themes: classic's is white at 38%. Measuring the gradient on its own
/// reports alpha differences as brightness and gets the answer backwards, which
/// is how an inverted vignette first showed up here.
void main() {
  const Size size = Size(200, 200);

  /// The panel's brightest and darkest points, and where the brightest is.
  Future<({double lo, double hi, int hx, int hy})> render(
    PlotThemeData theme,
    Color behind,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final Rect rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = behind);
    canvas.drawRect(
      rect,
      Paint()..shader = theme.background3D.createShader(rect),
    );
    final ui.Image image = await recorder.endRecording().toImage(200, 200);
    final ByteData data = (await image.toByteData())!;

    double lo = 2, hi = -1;
    int hx = 0, hy = 0;
    for (int y = 0; y < 200; y++) {
      for (int x = 0; x < 200; x++) {
        final int o = (y * 200 + x) * 4;
        final double v =
            Color.fromARGB(
              255,
              data.getUint8(o),
              data.getUint8(o + 1),
              data.getUint8(o + 2),
            ).computeLuminance();
        if (v < lo) lo = v;
        if (v > hi) {
          hi = v;
          hx = x;
          hy = y;
        }
      }
    }
    return (lo: lo, hi: hi, hx: hx, hy: hy);
  }

  for (final ThemeType type in <ThemeType>[ThemeType.classic, ThemeType.dark]) {
    final PlotThemeData theme = PlotThemeData.fromColors(
      AppColors.fromType(type),
    );
    // Both, because a translucent panel sits on whichever the app supplies and
    // the vignette has to point the same way on either.
    for (final MapEntry<String, Color> ground
        in <String, Color>{
          'a dark app background': const Color(0xFF101010),
          'a light app background': const Color(0xFFF2F2F2),
        }.entries) {
      testWidgets('$type on ${ground.key}: lit, but not by much', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final r = await render(theme, ground.value);
          final double swing = r.hi - r.lo;

          expect(
            swing,
            greaterThan(0.004),
            reason: 'the ground is flat — the lighting is not there',
          );
          // The ceiling is the point. The version this replaced swung 20-40%,
          // which put the same curve colour at visibly different contrast
          // depending where on the panel it fell.
          // Raised from 0.12 when the ground became the only depth cue on the
          // ten themes whose panel is opaque. Still a ceiling, and still for
          // the original reason: past this a curve colour starts reading
          // differently at the rim than at the centre.
          // Third raise, and worth being plain about: the ceiling started at
          // 0.12 to keep the ground from competing with the colour ramp, and
          // has been traded away twice for visibility — once when the ground
          // became the only depth cue on opaque themes, and again when light
          // themes turned out to be getting a third of the shading dark ones
          // got and showing no depth at all. 0.40 is roughly what a light
          // theme now needs to read like a dark one. The original concern has
          // not gone away; it has been outweighed.
          expect(
            swing,
            lessThan(0.40),
            reason:
                'a swing of $swing competes with the colour ramp drawn on '
                'top of it',
          );
        });
      });

      testWidgets('$type on ${ground.key}: the light is up and to the left', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final r = await render(theme, ground.value);
          // Not dead centre: a light above and slightly left reads as a light
          // in a room, while one in the middle reads as a spotlight aimed at
          // the data. Anywhere in the upper-left quadrant will do — pinning
          // the exact pixel would only pin the alignment constant to itself.
          expect(
            r.hx,
            lessThan(120),
            reason:
                'the brightest point is at ${r.hx},${r.hy} — the vignette '
                'is inverted or the light has moved right',
          );
          expect(
            r.hy,
            lessThan(120),
            reason:
                'the brightest point is at ${r.hx},${r.hy} — the vignette '
                'is inverted or the light has moved down',
          );
        });
      });
    }
  }

  test('the depth is a knob within range', () {
    expect(PlotThemeData.backgroundDepth, greaterThanOrEqualTo(0.0));
    expect(PlotThemeData.backgroundDepth, lessThanOrEqualTo(1.0));
  });
}
