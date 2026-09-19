import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_text_style.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A light theme, and it is the one you get by default.
///
/// Every other palette is light-on-dark. The renderer had `Colors.white`
/// written into it in thirty-nine places, so an expression on pale paper was
/// invisible — the ink follows the theme now.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a fresh install opens in the light theme', () async {
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    expect(settings.themeType, ThemeType.light);
    expect(settings.isDarkTheme, isFalse, reason: 'light is not a dark theme');
  });

  test('its ink is dark, and dark enough to read on its paper', () {
    final AppColors c = AppColors.fromType(ThemeType.light);

    double luminance(Color x) => x.computeLuminance();
    expect(
      luminance(c.textPrimary),
      lessThan(0.2),
      reason: 'the ink is not dark, so it will not read on pale paper',
    );
    expect(
      luminance(c.displayBackground),
      greaterThan(0.8),
      reason: 'the paper is not light, so this is not a light theme',
    );
    // Comfortably past the 4.5:1 that body text is meant to clear.
    final double contrast =
        (luminance(c.displayBackground) + 0.05) /
        (luminance(c.textPrimary) + 0.05);
    expect(contrast, greaterThan(4.5), reason: 'contrast is only $contrast:1');
  });

  test('choosing the theme sets the ink the expression is drawn in', () {
    AppColors.fromType(ThemeType.dark);
    expect(MathTextStyle.ink, Colors.white, reason: 'dark themes write white');

    AppColors.fromType(ThemeType.light);
    expect(
      MathTextStyle.ink,
      AppColors.light.textPrimary,
      reason: 'the expression would be drawn white on white paper',
    );
  });

  test('an upgrade keeps the theme it was already using', () async {
    // Someone who chose a theme before they were named should not be moved to
    // a different one by an update; only a fresh install gets the new default.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'isDarkTheme': true,
    });
    final dark = await SettingsProvider.create();
    addTearDown(dark.dispose);
    expect(dark.themeType, ThemeType.dark);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'isDarkTheme': false,
    });
    final classic = await SettingsProvider.create();
    addTearDown(classic.dispose);
    expect(
      classic.themeType,
      ThemeType.classic,
      reason: 'an existing install was moved off the theme it was using',
    );
  });
}
