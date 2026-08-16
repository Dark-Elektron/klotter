import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/plotting/widgets/plot_2d_screen.dart';

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
      // Away from the axes, which are drawn over the colouring and would
      // otherwise be what got sampled.
      final HSVColor near = await at(image, 0.3, 0.3);
      expect(near.value, greaterThan(0.75), reason: 'the pole is not bright');

      // arg(1/z) = -arg(z), so the colour at i is the one z had at -i.
      final HSVColor up = await at(image, 0, 1);
      expect(hueGap(up.hue, 270), lessThan(25), reason: 'hue ${up.hue}');
    });
  });

  testWidgets('the axes survive the colouring', (tester) async {
    await tester.runAsync(() async {
      // Domain colouring fills the window edge to edge, and the grid and axes
      // are drawn before it — so it painted straight over them and the plot
      // came out with no axes at all, only the tick labels drawn later.
      final data = (await (await render(identity())).toByteData())!;
      Color px(int x, int y) {
        final int o = (y * 240 + x) * 4;
        return Color.fromARGB(
          255,
          data.getUint8(o),
          data.getUint8(o + 1),
          data.getUint8(o + 2),
        );
      }

      // An axis is a sharp local deviation; the colouring is smooth. So each
      // point on the axis row is compared against the average of the rows
      // three pixels either side of it, which cancels the gradient of the
      // function and leaves only what was drawn on top.
      //
      // An earlier version compared the axis row against one ten pixels below
      // and passed with the redraw removed: for f(z) = z the colour changes
      // with y, so it was measuring the function rather than the axis.
      int spikes = 0;
      for (int x = 20; x < 220; x += 5) {
        final Color on = px(x, 120);
        final Color above = px(x, 117);
        final Color below = px(x, 123);
        final double gap =
            (on.r - (above.r + below.r) / 2).abs() +
            (on.g - (above.g + below.g) / 2).abs() +
            (on.b - (above.b + below.b) / 2).abs();
        if (gap > 0.12) spikes++;
      }
      expect(
        spikes,
        greaterThan(20),
        reason: 'the axis shows at only $spikes of 40 points',
      );
    });
  });

  group('the window', () {
    testWidgets('stays centred on the origin', (tester) async {
      // A complex function has no curve to frame: its domain is the plane,
      // and the Argand diagram is the picture rather than a graph of
      // something against x.
      SharedPreferences.setMockInitialValues({
        'walkthrough_completed_v2': true,
      });
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);

      final key = GlobalKey<Plot2DScreenState>();
      // z̲ + 3, which is the spelling that exposes this. The real evaluator
      // returns NaN for anything containing i, so the fit already found
      // nothing to fit for (x + yi)² and left the window alone. z̲ compiles
      // to a plain z with no imaginary part, so the fit does read numbers
      // from it — 3 everywhere — and framed the window around y = 3.
      final expr = PlotExpression.compile(<MathNode>[
        ComplexVariableNode(),
        LiteralNode(text: '+3'),
      ]);
      expect(expr.isComplex, isTrue, reason: expr.error);
      expect(expr.evaluate(2, 0, 0), 3, reason: 'the fit would read this');

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                width: 360,
                child: Plot2DScreen(
                  key: key,
                  plotTheme: PlotThemeData.fromColors(colors),
                  function: expr,
                  functions: <PlotExpression>[expr],
                  is3DFunction: false,
                  plotMode: PlotMode.function,
                  fieldType: FieldType.scalar,
                  showContour: false,
                  surfaceMode: SurfaceMode.none,
                  colors: colors,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final (xMin, xMax, yMin, yMax) = key.currentState!.ranges;
      expect(
        (yMin + yMax).abs(),
        lessThan(0.01),
        reason: 'the window runs $yMin to $yMax',
      );
      expect((xMin + xMax).abs(), lessThan(0.01));
    });

    testWidgets('while an ordinary function is still framed to fit', (
      tester,
    ) async {
      // The control: auto-scaling has to keep working for everything else.
      SharedPreferences.setMockInitialValues({
        'walkthrough_completed_v2': true,
      });
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);

      final key = GlobalKey<Plot2DScreenState>();
      final expr = PlotExpression.compile(<MathNode>[
        LiteralNode(text: 'x^2+20'),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                width: 360,
                child: Plot2DScreen(
                  key: key,
                  plotTheme: PlotThemeData.fromColors(colors),
                  function: expr,
                  functions: <PlotExpression>[expr],
                  is3DFunction: false,
                  plotMode: PlotMode.function,
                  fieldType: FieldType.scalar,
                  showContour: false,
                  surfaceMode: SurfaceMode.none,
                  colors: colors,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final (_, _, yMin, yMax) = key.currentState!.ranges;
      // x² + 20 never comes near zero, so a framed window must not be
      // centred on it.
      expect(yMin, greaterThan(5), reason: 'the window runs $yMin to $yMax');
    });
  });
}
