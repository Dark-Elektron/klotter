import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The controls sitting on the plot — 2D/3D, zoom, surface, pan, reset.
///
/// They were a fixed teal-and-white: an accent belonging to no theme, and idle
/// colours of `white24`/`white54` that all but disappeared on a light ground.
/// They now come from the same place as the axes and labels, so the test is
/// that they stay legible against the panel they are drawn on, in every theme.
void main() {
  double contrast(Color a, Color b) =>
      (a.computeLuminance() - b.computeLuminance()).abs();

  for (final ThemeType type in ThemeType.values) {
    final AppColors colors = AppColors.fromType(type);
    final PlotThemeData theme = PlotThemeData.fromColors(colors);

    test('$type: an idle control is visible against the plot', () {
      // Against the axis ink, which is known to read on this panel: an idle
      // control must be in the same territory, not an alpha away from nothing.
      expect(
        theme.controlIdle.a,
        greaterThan(0.4),
        reason: 'too transparent to see on a light ground',
      );
      expect(
        contrast(theme.controlIdle, theme.label),
        lessThan(0.35),
        reason:
            'the idle control is nowhere near the ink that is known to read '
            'on this panel',
      );
    });

    test('$type: the highlight is the theme accent, not a fixed teal', () {
      expect(theme.controlActive, colors.accent);
    });

    test('$type: active and idle are told apart', () {
      // A highlight that matches the idle state says nothing about which
      // control is on.
      expect(
        contrast(theme.controlActive, theme.controlIdle),
        greaterThan(0.02),
        reason: 'the selected control looks the same as an unselected one',
      );
    });
  }

  test('the fill behind a selected control is not opaque', () {
    // It sits over the data. Opaque would hide the plot under the button.
    for (final ThemeType type in ThemeType.values) {
      final PlotThemeData theme = PlotThemeData.fromColors(
        AppColors.fromType(type),
      );
      expect(theme.controlFill.a, lessThan(0.5), reason: '$type');
      expect(theme.controlFill.a, greaterThan(0.1), reason: '$type');
    }
  });
}
