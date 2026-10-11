import 'dart:math' as math;

import '../math_renderer/math_text_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/settings_provider.dart';

class AppColors {
  final Color displayBackground;
  final Color containerBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color accent;
  final Color keypadBackground;
  final Color keypadButton;
  final Color keypadButtonText;
  final Color keyboardPrimary; // NEW
  final Color keyboardSecondary; // NEW

  const AppColors({
    required this.displayBackground,
    required this.containerBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.accent,
    required this.keypadBackground,
    required this.keypadButton,
    required this.keypadButtonText,
    required this.keyboardPrimary, // NEW
    required this.keyboardSecondary, // NEW
  });

  // classic theme colors
  /// Dark ink on pale paper.
  ///
  /// The one theme where the expression is written in dark ink: every other
  /// palette here is light-on-dark, which is why the renderer's colour had to
  /// stop being a constant before this could exist.
  static const light = AppColors(
    displayBackground: Color(0xFFF7F7FA),
    containerBackground: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFF0B6BCB),
    divider: Color(0xFFD6D6DB),
    accent: Color(0xFF0B6BCB),
    keypadBackground: Color(0xFFEFEFF3),
    keypadButton: Color(0xFFFFFFFF),
    keypadButtonText: Color(0xFF1C1C1E),
    keyboardPrimary: Color(0xFFEFEFF3),
    keyboardSecondary: Color(0xFFFFFFFF),
  );

  static const classic = AppColors(
    displayBackground: Colors.white38,
    containerBackground: Color(0xFF546E7A), // Blue grey 600
    textPrimary: Colors.white,
    textSecondary: Color(0xFFECEFF1), // Blue grey 50
    textTertiary: Color(0xFFFFE8C8), // Pale apricot
    divider: Colors.grey,
    accent: Colors.yellow,
    keypadBackground: Color(0xFFE0E0E0),
    keypadButton: Colors.white,
    keypadButtonText: Colors.black,
    keyboardPrimary: Color(0xFFE0E0E0), // Default keyboard background
    keyboardSecondary: Colors.white, // Default key color
  );

  // Dark theme colors
  static const dark = AppColors(
    displayBackground: Colors.black,
    containerBackground: Color.fromARGB(255, 57, 57, 57),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFA2A2A2),
    textTertiary: Colors.orangeAccent,
    divider: Color(0xFF616161),
    accent: Colors.yellowAccent,
    keypadBackground: Color(0xFF121212),
    keypadButton: Color(0xFF2C2C2C),
    keypadButtonText: Colors.white,
    keyboardPrimary: Color(0xFF121212), // Dark keyboard background
    keyboardSecondary: Color(0xFF2C2C2C), // Dark key color
  );

  static const pink = AppColors(
    displayBackground: Color(0xFF2D2426), // Dark Chocolate-Plum
    containerBackground: Color(0xFF3D3134), // Warm Dark Mauve
    textPrimary: Color(0xFFFFF0F3), // Off-white with a hint of rose
    textSecondary: Color(0xFFC2A3A8), // Muted dusty rose
    textTertiary: Color(0xFFFF8FA3), // Vibrant Pink accent
    divider: Color(0xFF5E4B4E), // Deep muted wine
    accent: Color(0xFFFF4D6D), // Bright Cherry-Pink for operators
    keypadBackground: Color(0xFF1F1819), // Deepest charcoal pink
    keypadButton: Color(0xFF594548), // Muted plum-pink buttons
    keypadButtonText: Color(0xFFFFB3C1), // Soft pastel pink text
    keyboardPrimary: Color(0xFF1F1819),
    keyboardSecondary: Color(0xFF594548),
  );

  static const softPink = AppColors(
    displayBackground: Color(0xFFFBE4E4), // Warm light rose
    containerBackground: Color(
      0xFFE29B9B,
    ), // Warm Dusty Rose (Matched to image)
    textPrimary: Color(0xFF5E2A2A), // Deep warm rose
    textSecondary: Color(0xFF583939), // Muted warm rose
    textTertiary: Color(0xFF870024), // Vibrant Pink (kept for contrast)
    divider: Color(0xFFF2C4C4), // Warm light border
    accent: Color(0xFFD87070), // Warm coral-red accent
    keypadBackground: Color(0xFFFCF0F0), // Softest warm pink
    keypadButton: Color(0xFFF2C4C4), // Warm rose buttons
    keypadButtonText: Color(0xFF5E2A2A), // Dark warm text
    keyboardPrimary: Color(0xFFFCF0F0),
    keyboardSecondary: Color(0xFFF2C4C4),
  );

  // Dark theme colors
  static const sunsetEmber = AppColors(
    displayBackground: Color(0xFF2D1B1B),
    containerBackground: Color(0xFF3D2B2B),
    textPrimary: Color(0xFFFDF5E6),
    textSecondary: Color(0xFFA89F91),
    textTertiary: Color(0xFFFF8C42), // Burnt Orange
    divider: Color(0xFF5D4037),
    accent: Color(0xFFE2725B), // Terracotta
    keypadBackground: Color(0xFF231515),
    keypadButton: Color(0xFF4E342E),
    keypadButtonText: Color(0xFFFFCC80),
    keyboardPrimary: Color(0xFF231515),
    keyboardSecondary: Color(0xFF4E342E),
  );

  static const desertSand = AppColors(
    displayBackground: Color(0xFFF4EBD2), // Soft Beige
    containerBackground: Color(0xFFC18A63), // Clay
    textPrimary: Color(0xFF352D27), // Deep Coffee
    textSecondary: Color(0xFF273224),
    textTertiary: Color(0xFF4A260B), // Burnt Sienna
    divider: Color(0xFFD9C9A2),
    accent: Color(0xFFE86F1B), // Orange Citrus
    keypadBackground: Color(0xFFFDF5E6),
    keypadButton: Color(0xFFEEDBC3),
    keypadButtonText: Color(0xFF4A3325),
    keyboardPrimary: Color(0xFFFDF5E6),
    keyboardSecondary: Color(0xFFEEDBC3),
  );

  static const digitalAmber = AppColors(
    displayBackground: Colors.black,
    containerBackground: Color(0xFF1A120B),
    textPrimary: Color(0xFFFFBF00), // Amber
    textSecondary: Color(0xFFD69A3C),
    textTertiary: Color(0xFFFFDA9A),
    divider: Color(0xFF3E2723),
    accent: Color(0xFFFF8F00),
    keypadBackground: Color(0xFF0C0C0C),
    keypadButton: Color(0xFF232323),
    keypadButtonText: Color(0xFFFFBF00),
    keyboardPrimary: Color(0xFF0C0C0C),
    keyboardSecondary: Color(0xFF232323),
  );

  // Salmon (#F8B69E): a light theme with dark text, one of
  // four pastels picked together (salmon, yellow, sage, sky blue).
  static const roseChic = AppColors(
    displayBackground: Color(0xFFFDE8E0), // behind the cells
    containerBackground: Color(0xFFF8B69E), // the cells
    textPrimary: Color(0xFF322420),
    textSecondary: Color(0xFF684C42),
    textTertiary: Color(0xFF8C3515), // cell index and angle unit
    divider: Color(0xFFD59D88),
    accent: Color(0xFFD15E34), // switches, sliders, help icons
    keypadBackground: Color(0xFFFDEFEA),
    keypadButton: Color(0xFFFBD5C7),
    keypadButtonText: Color(0xFF322420),
    keyboardPrimary: Color(0xFFFDEFEA),
    keyboardSecondary: Color(0xFFFBD5C7),
  );

  // Pale yellow (#FFF3AB): a light theme with dark text, one of
  // four pastels picked together (salmon, yellow, sage, sky blue).
  static const honeyMustard = AppColors(
    displayBackground: Color(0xFFFFFBE4), // behind the cells
    containerBackground: Color(0xFFFFF3AB), // the cells
    textPrimary: Color(0xFF333122),
    textSecondary: Color(0xFF736D4D),
    textTertiary: Color(0xFF7D6E13), // cell index and angle unit
    divider: Color(0xFFDBD193),
    accent: Color(0xFFA39229), // switches, sliders, help icons
    keypadBackground: Color(0xFFFFFCED),
    keypadButton: Color(0xFFFFF8CE),
    keypadButtonText: Color(0xFF333122),
    keyboardPrimary: Color(0xFFFFFCED),
    keyboardSecondary: Color(0xFFFFF8CE),
  );

  // Sage green (#CBDCB0): a light theme with dark text, one of
  // four pastels picked together (salmon, yellow, sage, sky blue).
  static const forestMoss = AppColors(
    displayBackground: Color(0xFFEEF4E6), // behind the cells
    containerBackground: Color(0xFFCBDCB0), // the cells
    textPrimary: Color(0xFF292C23),
    textSecondary: Color(0xFF58604D),
    textTertiary: Color(0xFF45660F), // cell index and angle unit
    divider: Color(0xFFAFBD97),
    accent: Color(0xFF6D9926), // switches, sliders, help icons
    keypadBackground: Color(0xFFF4F7EE),
    keypadButton: Color(0xFFE1EBD1),
    keypadButtonText: Color(0xFF292C23),
    keyboardPrimary: Color(0xFFF4F7EE),
    keyboardSecondary: Color(0xFFE1EBD1),
  );

  // Sky blue (#97CDE7): a light theme with dark text, one of
  // four pastels picked together (salmon, yellow, sage, sky blue).
  static const skyBlue = AppColors(
    displayBackground: Color(0xFFDEEFF7), // behind the cells
    containerBackground: Color(0xFF97CDE7), // the cells
    textPrimary: Color(0xFF1E292E),
    textSecondary: Color(0xFF3F5560),
    textTertiary: Color(0xFF125778), // cell index and angle unit
    divider: Color(0xFF82B0C7),
    accent: Color(0xFF3091BF), // switches, sliders, help icons
    keypadBackground: Color(0xFFE8F4FA),
    keypadButton: Color(0xFFC3E2F1),
    keypadButtonText: Color(0xFF1E292E),
    keyboardPrimary: Color(0xFFE8F4FA),
    keyboardSecondary: Color(0xFFC3E2F1),
  );

  /// How opaque the rows panel is over the plot: enough to read an
  /// expression against a busy plot, little enough to see the curves
  /// through it.
  static const double rowOpacity = 0.82;

  /// What the expression rows are drawn on, at its lightest and darkest.
  ///
  /// The panel is translucent, and what shows through it is the plot rather
  /// than the page: the plot shades its ground darker toward the rim, where
  /// the rows sit, and Settings can put a dark plot under any theme. Measured
  /// under the rows, a pastel theme's ground came out 15% darker than the
  /// panel over its page, and over a dark plot close to the panel over black.
  /// Text on the rows is held to read on both.
  ({Color lightest, Color darkest}) get rowBackdrops {
    final Color panel = containerBackground.withValues(alpha: rowOpacity);
    return (
      // A phone shows black behind a translucent page (classic's).
      lightest: Color.alphaBlend(
        panel,
        Color.alphaBlend(displayBackground, Colors.black),
      ),
      darkest: Color.alphaBlend(panel, Colors.black),
    );
  }

  /// The WCAG contrast ratio of two colours, from 1 to 21.
  static double contrastRatio(Color a, Color b) {
    final double la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// The lower of [colour]'s contrasts on the two [rowBackdrops].
  double _worstOnRows(Color colour) {
    final ({Color lightest, Color darkest}) rows = rowBackdrops;
    return math.min(
      contrastRatio(colour, rows.lightest),
      contrastRatio(colour, rows.darkest),
    );
  }

  /// Whether the rows are written in white rather than the palette's own
  /// text colour: whichever reads better on the [rowBackdrops].
  bool get _whiteRows =>
      _worstOnRows(Colors.white) >= _worstOnRows(textPrimary);

  /// [colour], made to read at [minContrast] on the expression rows: kept
  /// where it already does on both [rowBackdrops], and otherwise moved, its
  /// hue kept, the way the ink lies (lighter on rows written in white,
  /// darker on the rest) until it does.
  Color onRows(Color colour, {double minContrast = 3}) {
    if (_worstOnRows(colour) >= minContrast) return colour;
    final bool lighter = _whiteRows;
    final HSLColor hsl = HSLColor.fromColor(colour);
    double lightness = hsl.lightness;
    while (lightness > 0 && lightness < 1) {
      lightness = (lightness + (lighter ? 0.01 : -0.01)).clamp(0.0, 1.0);
      final Color c = hsl.withLightness(lightness).toColor();
      if (_worstOnRows(c) >= minContrast) return c;
    }
    return lighter ? Colors.white : Colors.black;
  }

  // Helper to get colors based on context
  /// The colours an expression is written in on [palette]'s rows: the ink,
  /// and the orange of `ans`.
  ///
  /// The ink is the palette's own text colour or white, whichever reads
  /// better on the [rowBackdrops], deepened where it must be to read at
  /// 4.5:1 on both. Read from the palette itself rather than listed
  /// separately, so a new theme cannot forget it. Every dark palette keeps
  /// the white it was always written in. The light ones (light, the four
  /// pastels, soft pink and desert sand) get their dark text: white on a
  /// pastel row read at 1.4:1, and only light had been given its own ink
  /// before.
  ///
  /// `ans` keeps its orange where that reads at 3:1 (it is large text), and
  /// is otherwise moved toward the ink's side until it does. On the pastel
  /// rows the plain orange read at 1.1:1.
  static ({Color ink, Color ans}) _rowInks(AppColors palette) => (
    ink: palette.onRows(
      palette._whiteRows ? Colors.white : palette.textPrimary,
      minContrast: 4.5,
    ),
    ans: palette.onRows(Colors.orangeAccent),
  );

  /// [_rowInks] for each theme, worked out once: every read of a palette
  /// sets them.
  static final Map<ThemeType, ({Color ink, Color ans})> _rowInkCache =
      <ThemeType, ({Color ink, Color ans})>{};

  static AppColors of(BuildContext context, {bool listen = true}) {
    final settings = Provider.of<SettingsProvider>(context, listen: listen);
    return fromType(settings.themeType);
  }

  static AppColors fromType(ThemeType type) {
    final AppColors palette = switch (type) {
      ThemeType.light => light,
      ThemeType.classic => classic,
      ThemeType.dark => dark,
      ThemeType.softPink => softPink,
      ThemeType.pink => pink,
      ThemeType.sunsetEmber => sunsetEmber,
      ThemeType.desertSand => desertSand,
      ThemeType.digitalAmber => digitalAmber,
      ThemeType.roseChic => roseChic,
      ThemeType.honeyMustard => honeyMustard,
      ThemeType.forestMoss => forestMoss,
      ThemeType.skyBlue => skyBlue,
    };
    // Every read of the palette passes through here, so this is where the
    // expression ink is kept in step with the theme. The renderer cannot ask
    // for it: its glyph colour used to be the constant `Colors.white` in
    // thirty-nine places, which is why a light theme was impossible before.
    final ({Color ink, Color ans}) inks =
        _rowInkCache[type] ??= _rowInks(palette);
    MathTextStyle.ink = inks.ink;
    MathTextStyle.ansInk = inks.ans;
    return palette;
  }
}
