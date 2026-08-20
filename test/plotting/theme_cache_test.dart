import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The plot theme is built once and handed out.
///
/// It was rebuilt at every call site that wanted a colour off it — twenty-eight
/// times per panel build — and it is not a cheap object: palettes, gradients
/// and a couple of dozen derived colours, on a widget that repaints every drag
/// frame.
void main() {
  setUp(PlotThemeData.clearCache);

  test('the same settings give back the same object', () {
    final AppColors c = AppColors.fromType(ThemeType.classic);
    final PlotThemeData a = PlotThemeData.fromColors(c);
    final PlotThemeData b = PlotThemeData.fromColors(c);
    expect(identical(a, b), isTrue, reason: 'the theme was built twice');
  });

  test('different themes are different objects', () {
    // The cache must not hand a dark theme to a light plot.
    final PlotThemeData light = PlotThemeData.fromColors(
      AppColors.fromType(ThemeType.classic),
      themeType: ThemeType.classic,
    );
    final PlotThemeData dark = PlotThemeData.fromColors(
      AppColors.fromType(ThemeType.dark),
      themeType: ThemeType.dark,
    );
    expect(identical(light, dark), isFalse);
    expect(light.label, isNot(dark.label));
  });

  test('the colour mode is part of the identity', () {
    final AppColors c = AppColors.fromType(ThemeType.classic);
    final PlotThemeData a = PlotThemeData.fromColors(
      c,
      mode: PlotColorMode.light,
    );
    final PlotThemeData b = PlotThemeData.fromColors(
      c,
      mode: PlotColorMode.dark,
    );
    expect(identical(a, b), isFalse, reason: 'both modes shared one theme');
  });

  test('clearing forces a rebuild', () {
    final AppColors c = AppColors.fromType(ThemeType.classic);
    final PlotThemeData before = PlotThemeData.fromColors(c);
    PlotThemeData.clearCache();
    expect(identical(before, PlotThemeData.fromColors(c)), isFalse);
  });

  test('the plot ground lets the wallpaper through', () {
    // The plot fills the page now, so its own ground is the only thing between
    // the data and the wallpaper. Fully opaque hid it on every theme whose
    // panel colour is opaque.
    for (final ThemeType t in ThemeType.values) {
      final PlotThemeData theme = PlotThemeData.fromColors(
        AppColors.fromType(t),
        themeType: t,
      );
      for (final c in theme.background3D.colors) {
        expect(c.a, lessThan(1.0), reason: '$t paints an opaque ground');
      }
    }
  });
}
