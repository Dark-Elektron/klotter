import 'dart:math' as math;
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

/// Drawing a function of a complex variable by colouring its domain.
///
/// Hue is the argument and lightness the modulus, so the assertions are about
/// where particular hues land — which is the only thing that says the picture
/// means anything rather than merely being colourful.
void main() {
  const Size canvas = Size(240, 240);
  const double span = 2; // the window is -2..2 both ways
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  /// `f(z) = z`, written so it is recognised as complex.
  ///
  /// The `0i` is the cost of inferring complexity from the imaginary unit: `z`
  /// on its own has no `i` in it and would be sampled as a real function.
  PlotExpression identity() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'z+0i')]);

  Future<ui.Image> render(PlotExpression expr) async {
    final painter = Plot2DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
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
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(240, 240);
  }

  /// The colour at a point of the complex plane.
  Future<HSVColor> at(ui.Image image, double re, double im) async {
    final data = (await image.toByteData())!;
    final int px = (((re + span) / (2 * span)) * 240).round().clamp(0, 239);
    final int py = ((1 - (im + span) / (2 * span)) * 240).round().clamp(0, 239);
    final int o = (py * 240 + px) * 4;
    return HSVColor.fromColor(
      Color.fromARGB(
        255,
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      ),
    );
  }

  /// Degrees between two hues, the short way round.
  double hueGap(double a, double b) {
    final double d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  test('the expression under test is complex', () {
    // The guard every rendering test in this suite now carries: an expression
    // that failed to compile draws nothing, and two renders of nothing agree
    // about everything.
    final e = identity();
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isComplex, isTrue);
    // And one without an i is not, which is what the branch keys off.
    expect(
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2')]).isComplex,
      isFalse,
    );
  });

  testWidgets('the hue at a point is the argument there', (tester) async {
    await tester.runAsync(() async {
      final ui.Image image = await render(identity());

      // f(z) = z, so the colour at z is decided by arg z. Sampled off the
      // axes, where a pixel either side cannot change the answer much.
      for (final ({double re, double im}) p in <({double re, double im})>[
        (re: 1.0, im: 0.0), // arg 0
        (re: 0.0, im: 1.0), // arg π/2
        (re: -1.0, im: 0.0), // arg π
        (re: 0.0, im: -1.0), // arg -π/2
        (re: 1.0, im: 1.0), // arg π/4
      ]) {
        final double want = math.atan2(p.im, p.re) * 180 / math.pi;
        final HSVColor got = await at(image, p.re, p.im);
        expect(
          hueGap(got.hue, want < 0 ? want + 360 : want),
          lessThan(20),
          reason: 'at ${p.re}+${p.im}i the hue is ${got.hue}, wanted $want',
        );
      }
    });
  });

  testWidgets('every hue appears, so the picture wraps without a seam', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final ui.Image image = await render(identity());
      final Set<int> sectors = <int>{};
      for (int k = 0; k < 24; k++) {
        final double a = k * math.pi / 12;
        final HSVColor c = await at(image, math.cos(a), math.sin(a));
        sectors.add((c.hue / 30).floor() % 12);
      }
      // All twelve thirty-degree sectors of the wheel, which is what says the
      // colouring goes the whole way round rather than running out at π.
      expect(sectors.length, 12, reason: 'only ${sectors.length} sectors');
    });
  });

  testWidgets('a zero is dark and the far field is bright', (tester) async {
    await tester.runAsync(() async {
      final ui.Image image = await render(identity());
      final HSVColor origin = await at(image, 0, 0);
      final HSVColor away = await at(image, 1.8, 1.8);
      expect(origin.value, lessThan(0.35), reason: 'the zero is not dark');
      expect(
        away.value,
        greaterThan(origin.value + 0.3),
        reason: 'the modulus is not readable',
      );
    });
  });

  testWidgets('a pole is bright, and the hues run the other way', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // 1/z: the argument is negated, so the wheel turns backwards, and the
      // origin is white rather than black.
      final image = await render(
        PlotExpression.compile(<MathNode>[LiteralNode(text: '1/(z+0i)')]),
      );
      // Just off it, not on it: 1/0 is undefined and the painter leaves a
      // hole there rather than inventing a colour. What has to be bright is
      // the neighbourhood, which is what makes a pole read as a pole.
      final HSVColor near = await at(image, 0.06, 0.06);
      expect(near.value, greaterThan(0.75), reason: 'the pole is not bright');

      // arg(1/z) = -arg(z), so the colour at i is the one z had at -i.
      final HSVColor up = await at(image, 0, 1);
      expect(hueGap(up.hue, 270), lessThan(25), reason: 'hue ${up.hue}');
    });
  });
}
