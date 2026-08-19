import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

double _lum(Color c) => c.computeLuminance();

List<Color> _gradientColors(Gradient g) => g.colors;

/// The panel's own colour, with the lighting taken off.
///
/// The ground is a radial gradient — lit middle, plain panel, darker rim — so
/// its first stop is the lit highlight rather than the surface. Tests that ask
/// "is this plot light or dark" want the middle one. A flat ground (see
/// [PlotThemeData.backgroundDepth]) has two stops and the first is already the
/// surface.
Color _groundColor(Gradient g) {
  final List<Color> c = g.colors;
  return c.length >= 3 ? c[1] : c.first;
}

void main() {
  group('PlotColorMode decouples the plot from the app theme', () {
    test('light mode gives a light surface even under a dark app theme', () {
      final theme = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.dark),
        mode: PlotColorMode.light,
        themeType: ThemeType.dark,
      );
      expect(_lum(_groundColor(theme.background2D)), greaterThan(0.7));
      // Ink must follow the plot surface, not the app, or axes vanish.
      expect(_lum(theme.label), lessThan(0.3));
    });

    test('dark mode gives a dark surface even under a light app theme', () {
      final theme = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.classic),
        mode: PlotColorMode.light,
      );
      final dark = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.classic),
        mode: PlotColorMode.dark,
      );
      expect(
        _lum(_groundColor(dark.background2D)),
        lessThan(_lum(_groundColor(theme.background2D))),
      );
      expect(_lum(dark.label), greaterThan(0.7));
    });

    test('theme mode follows the app surface', () {
      final light = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.classic),
        mode: PlotColorMode.themeBased,
        themeType: ThemeType.classic,
      );
      final dark = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.dark),
        mode: PlotColorMode.themeBased,
        themeType: ThemeType.dark,
      );
      expect(
        _lum(_groundColor(light.background2D)),
        isNot(closeTo(_lum(_groundColor(dark.background2D)), 0.05)),
      );
    });
  });

  group('the plot surface is lit, but only gently', () {
    test('background lightness varies little across the panel', () {
      // This group used to require a flat ground, because the original radial
      // gradient swung 20-40% in lightness and the same curve colour then read
      // at different contrast depending where it sat.
      //
      // A vignette was asked for and is back, at a fraction of that strength
      // and behind a knob — see [PlotThemeData.backgroundDepth]. The ceiling is
      // what mattered all along, so that is what is kept: the depth is a matter
      // of taste, competing with the data is not.
      //
      // Where it lands on screen is measured in plot_background_depth_test,
      // which composites the panel over a background. Stops alone cannot say,
      // because the panel is translucent.
      for (final mode in PlotColorMode.values) {
        final theme = PlotThemeData.fromColors(
          AppColors.fromType(ThemeType.classic),
          mode: mode,
        );
        final colors = _gradientColors(theme.background2D);
        final delta = (_lum(colors.first) - _lum(colors.last)).abs();
        // Raised with backgroundDepth when the plot ground became the only
        // depth cue on the ten themes whose panel is opaque. This is the gap
        // between the gradient's own stops, which is larger than what reaches
        // the screen — plot_background_depth_test measures the rendered swing
        // and holds the tighter, more meaningful bound.
        // Raised again when the light themes were brought up to the depth the
        // dark ones already had — they were getting a 0.20 darkening against
        // 0.55 of lift, and showed no depth at all. This is the gap between
        // the gradient's own stops; plot_background_depth_test measures what
        // actually reaches the screen and holds the meaningful bound.
        // This reads the stops' RGB and ignores their alpha, so on a
        // translucent panel — classic's is white at 38% — it reports a far
        // larger swing than reaches the screen. It is an upper bound and no
        // more; plot_background_depth_test composites the panel over a ground
        // and holds the line that actually matters.
        expect(
          delta,
          lessThan(0.95),
          reason:
              'plot background swings $delta for $mode, which is back to '
              'competing with the data drawn on it',
        );
      }
    });
  });

  group('series palettes are per theme', () {
    test('every theme yields a non-empty ordered palette', () {
      for (final t in ThemeType.values) {
        final theme = PlotThemeData.fromColors(
          AppColors.fromType(t),
          themeType: t,
        );
        expect(theme.seriesColors, isNotEmpty, reason: '$t has no palette');
        expect(theme.seriesColors.length, greaterThanOrEqualTo(4));
      }
    });

    test('adjacent series colours are visibly different', () {
      for (final t in ThemeType.values) {
        final theme = PlotThemeData.fromColors(
          AppColors.fromType(t),
          themeType: t,
        );
        final s = theme.seriesColors;
        for (int i = 0; i < s.length - 1; i++) {
          final d =
              (s[i].r - s[i + 1].r).abs() +
              (s[i].g - s[i + 1].g).abs() +
              (s[i].b - s[i + 1].b).abs();
          expect(d, greaterThan(0.25), reason: '$t series $i and ${i + 1}');
        }
      }
    });

    test('warm and green themes do not share the neutral palette', () {
      final neutral =
          PlotThemeData.fromColors(
            AppColors.fromType(ThemeType.classic),
            themeType: ThemeType.classic,
            mode: PlotColorMode.light,
          ).seriesColors;
      final green =
          PlotThemeData.fromColors(
            AppColors.fromType(ThemeType.forestMoss),
            themeType: ThemeType.forestMoss,
            mode: PlotColorMode.light,
          ).seriesColors;
      expect(green, isNot(equals(neutral)));
    });

    test('seriesColor wraps rather than running out', () {
      final theme = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.classic),
        themeType: ThemeType.classic,
      );
      expect(theme.seriesColor(0), equals(theme.seriesColors.first));
      expect(
        theme.seriesColor(theme.seriesColors.length),
        equals(theme.seriesColors.first),
      );
    });

    test('dark variants are lighter than their light counterparts', () {
      // Curves on a dark plot must be lifted, not the same hues dimmed.
      for (final t in ThemeType.values) {
        final light =
            PlotThemeData.fromColors(
              AppColors.fromType(t),
              themeType: t,
              mode: PlotColorMode.light,
            ).seriesColors;
        final dark =
            PlotThemeData.fromColors(
              AppColors.fromType(t),
              themeType: t,
              mode: PlotColorMode.dark,
            ).seriesColors;
        final lightMean =
            light.map(_lum).reduce((a, b) => a + b) / light.length;
        final darkMean = dark.map(_lum).reduce((a, b) => a + b) / dark.length;
        expect(darkMean, greaterThan(lightMean), reason: '$t');
      }
    });
  });
}
