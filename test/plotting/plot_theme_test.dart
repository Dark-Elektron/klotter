import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

double _lum(Color c) => c.computeLuminance();

List<Color> _gradientColors(Gradient g) => (g as LinearGradient).colors;

void main() {
  group('PlotColorMode decouples the plot from the app theme', () {
    test('light mode gives a light surface even under a dark app theme', () {
      final theme = PlotThemeData.fromColors(
        AppColors.fromType(ThemeType.dark),
        mode: PlotColorMode.light,
        themeType: ThemeType.dark,
      );
      expect(_lum(_gradientColors(theme.background2D).first), greaterThan(0.7));
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
        _lum(_gradientColors(dark.background2D).first),
        lessThan(_lum(_gradientColors(theme.background2D).first)),
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
        _lum(_gradientColors(light.background2D).first),
        isNot(closeTo(_lum(_gradientColors(dark.background2D).first), 0.05)),
      );
    });
  });

  group('the plot surface is flat, not a vignette', () {
    test('background lightness barely varies across the panel', () {
      // The old radial gradient swung 20-40% in lightness, so the same curve
      // colour read at different contrast depending where it sat.
      for (final mode in PlotColorMode.values) {
        final theme = PlotThemeData.fromColors(
          AppColors.fromType(ThemeType.classic),
          mode: mode,
        );
        final colors = _gradientColors(theme.background2D);
        final delta = (_lum(colors.first) - _lum(colors.last)).abs();
        expect(
          delta,
          lessThan(0.06),
          reason: 'plot background should be effectively flat for $mode',
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
