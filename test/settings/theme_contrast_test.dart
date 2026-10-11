import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_text_style.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

double contrast(Color a, Color b) => AppColors.contrastRatio(a, b);

/// Text in every theme reads against what it is drawn on. Several did not:
/// desert sand's text was 3.4:1 and its labels 1.0:1, soft pink's labels
/// 1.2:1, and white ink on the pastel rows would have been 1.4:1.
void main() {
  test('every theme keeps its text readable', () {
    for (final ThemeType theme in ThemeType.values) {
      final AppColors c = AppColors.fromType(theme);
      for (final (String what, Color text) in [
        ('text', c.textPrimary),
        ('secondary text', c.textSecondary),
        ('tertiary text', c.textTertiary),
      ]) {
        expect(
          contrast(text, c.containerBackground),
          greaterThanOrEqualTo(4.5),
          reason: '$theme: $what',
        );
      }
      expect(
        contrast(c.keypadButtonText, c.keypadButton),
        greaterThanOrEqualTo(4.5),
        reason: '$theme: key labels',
      );
    }
  });

  test('the expression ink reads on every theme\'s rows', () {
    for (final ThemeType theme in ThemeType.values) {
      final AppColors c = AppColors.fromType(theme);
      // The rows are translucent: what is under them lies between the panel
      // over the page and the panel over black (a dark plot).
      for (final (String where, Color ground) in [
        ('over the page', c.rowBackdrops.lightest),
        ('over black', c.rowBackdrops.darkest),
      ]) {
        expect(
          contrast(MathTextStyle.ink, ground),
          greaterThanOrEqualTo(4.5),
          reason: '$theme: ink ${MathTextStyle.ink} $where',
        );
        // ans is large text.
        expect(
          contrast(MathTextStyle.ansInk, ground),
          greaterThanOrEqualTo(3),
          reason: '$theme: ans $where',
        );
      }
    }
  });

  test('a row that cannot be drawn shows its mark on every theme', () {
    for (final ThemeType theme in ThemeType.values) {
      final AppColors c = AppColors.fromType(theme);
      final Color mark =
          PlotThemeData.fromColors(c, themeType: theme).errorMark;
      for (final Color ground in [
        c.rowBackdrops.lightest,
        c.rowBackdrops.darkest,
      ]) {
        // An icon: 3:1, as for any graphic that carries meaning.
        expect(
          contrast(mark, ground),
          greaterThanOrEqualTo(3),
          reason: '$theme: $mark',
        );
      }
    }
  });

  test('ans leans the way the ink does', () {
    // On classic's blue grey, black has more headroom than white, and a dark
    // orange beside white ink read as a smudge rather than a highlight.
    final double orange = Colors.orangeAccent.computeLuminance();
    for (final ThemeType theme in ThemeType.values) {
      AppColors.fromType(theme);
      if (MathTextStyle.ansInk == Colors.orangeAccent) continue;
      expect(
        MathTextStyle.ansInk.computeLuminance() > orange,
        MathTextStyle.ink.computeLuminance() > 0.5,
        reason: '$theme: ans ${MathTextStyle.ansInk}',
      );
    }
  });

  test('dark themes keep their white ink; light ones write dark', () {
    for (final ThemeType theme in ThemeType.values) {
      AppColors.fromType(theme);
      final bool lightInk = MathTextStyle.ink.computeLuminance() > 0.5;
      if (SettingsProvider.lightThemes.contains(theme) &&
          theme != ThemeType.classic) {
        expect(lightInk, isFalse, reason: '$theme');
      } else {
        expect(lightInk, isTrue, reason: '$theme');
      }
    }
  });

  test(
    'a theme counted light has a light background, and dark the opposite',
    () {
      for (final ThemeType theme in ThemeType.values) {
        final double background =
            AppColors.fromType(theme).displayBackground.computeLuminance();
        if (SettingsProvider.lightThemes.contains(theme)) {
          expect(background, greaterThan(0.5), reason: '$theme');
        } else {
          expect(background, lessThan(0.1), reason: '$theme');
        }
      }
    },
  );

  test('the pastel rows are the four picked colours', () {
    expect(AppColors.roseChic.containerBackground, const Color(0xFFF8B69E));
    expect(AppColors.honeyMustard.containerBackground, const Color(0xFFFFF3AB));
    expect(AppColors.forestMoss.containerBackground, const Color(0xFFCBDCB0));
    expect(AppColors.skyBlue.containerBackground, const Color(0xFF97CDE7));
  });
}
