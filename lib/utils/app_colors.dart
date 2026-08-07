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
  final String backgroundImage; // Add this
  final double textureIntensity;
  final double textureScale;
  final double textureSoftness;

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
    required this.backgroundImage, // Add this
    this.textureIntensity = 0.15,
    this.textureScale = 1.65,
    this.textureSoftness = 1.0,
  });

  // classic theme colors
  static const classic = AppColors(
    displayBackground: Colors.white38,
    containerBackground: Colors.blueGrey,
    textPrimary: Colors.white,
    textSecondary: Colors.grey,
    textTertiary: Colors.orangeAccent,
    divider: Colors.grey,
    accent: Colors.yellow,
    keypadBackground: Color(0xFFE0E0E0),
    keypadButton: Colors.white,
    keypadButtonText: Colors.black,
    keyboardPrimary: Color(0xFFE0E0E0), // Default keyboard background
    keyboardSecondary: Colors.white, // Default key color
    backgroundImage: 'assets/imgs/background_classic.svg',
    textureIntensity: 0.15,
    textureScale: 1.65,
    textureSoftness: 1.0,
  );

  // Dark theme colors
  static const dark = AppColors(
    displayBackground: Colors.black,
    containerBackground: Color.fromARGB(255, 57, 57, 57),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF9E9E9E),
    textTertiary: Colors.orangeAccent,
    divider: Color(0xFF616161),
    accent: Colors.yellowAccent,
    keypadBackground: Color(0xFF121212),
    keypadButton: Color(0xFF2C2C2C),
    keypadButtonText: Colors.white,
    keyboardPrimary: Color(0xFF121212), // Dark keyboard background
    keyboardSecondary: Color(0xFF2C2C2C), // Dark key color
    backgroundImage: 'assets/imgs/background_dark.svg',
    textureIntensity: 0.6,
    textureScale: 1,
    textureSoftness: 0.8,
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
    backgroundImage: 'assets/imgs/background_pink.svg',
    textureIntensity: 0.6,
    textureScale: 1,
    textureSoftness: 0.5,
  );

  static const softPink = AppColors(
    displayBackground: Color(0xFFFBE4E4), // Warm light rose
    containerBackground: Color(
      0xFFE29B9B,
    ), // Warm Dusty Rose (Matched to image)
    textPrimary: Color(0xFF5E2A2A), // Deep warm rose
    textSecondary: Color(0xFF8E5C5C), // Muted warm rose
    textTertiary: Color(0xFFFF7096), // Vibrant Pink (kept for contrast)
    divider: Color(0xFFF2C4C4), // Warm light border
    accent: Color(0xFFD87070), // Warm coral-red accent
    keypadBackground: Color(0xFFFCF0F0), // Softest warm pink
    keypadButton: Color(0xFFF2C4C4), // Warm rose buttons
    keypadButtonText: Color(0xFF5E2A2A), // Dark warm text
    keyboardPrimary: Color(0xFFFCF0F0),
    keyboardSecondary: Color(0xFFF2C4C4),
    backgroundImage: 'assets/imgs/background_soft_pink.svg',
    textureIntensity: 0.1,
    textureSoftness: 0.2,
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
    backgroundImage: 'assets/imgs/background_sunset_ember.svg',
    textureIntensity: 0.4,
    textureSoftness: 0.9,
  );

  static const desertSand = AppColors(
    displayBackground: Color(0xFFF4EBD2), // Soft Beige
    containerBackground: Color(0xFFC18A63), // Clay
    textPrimary: Color(0xFF4A3F36), // Deep Coffee
    textSecondary: Color(0xFF7E9C76),
    textTertiary: Color(0xFFA35418), // Burnt Sienna
    divider: Color(0xFFD9C9A2),
    accent: Color(0xFFE86F1B), // Orange Citrus
    keypadBackground: Color(0xFFFDF5E6),
    keypadButton: Color(0xFFEEDBC3),
    keypadButtonText: Color(0xFF4A3325),
    keyboardPrimary: Color(0xFFFDF5E6),
    keyboardSecondary: Color(0xFFEEDBC3),
    backgroundImage: 'assets/imgs/background_desert_sand.svg',
    textureIntensity: 0.16,
    textureScale: 1.8,
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
    backgroundImage: 'assets/imgs/background_digital_amber.svg',
    textureIntensity: 0.8,
    textureScale: 1.4,
  );

  static const roseChic = AppColors(
    displayBackground: Color(0xFF2C2C2C),
    containerBackground: Color(0xFF3D3D3D),
    textPrimary: Color(0xFFF7E5E1), // Soft Rose White
    textSecondary: Color(0xFFB2545B),
    textTertiary: Color(0xFFEAA292), // Peach Blossom
    divider: Color(0xFF60202A),
    accent: Color(0xFF8F2F42), // Rosewood
    keypadBackground: Color(0xFF1A1A1A),
    keypadButton: Color(0xFF4A3F3F),
    keypadButtonText: Color(0xFFF9C6B0),
    keyboardPrimary: Color(0xFF1A1A1A),
    keyboardSecondary: Color(0xFF4A3F3F),
    backgroundImage: 'assets/imgs/background_rose_chic.svg',
    textureIntensity: 0.13,
  );

  static const honeyMustard = AppColors(
    displayBackground: Color(0xFFFFF5C5),
    containerBackground: Color(0xFFFFCF36), // Mustard
    textPrimary: Color(0xFF1E615A), // Dark Teal Contrast
    textSecondary: Color(0xFF8A694D),
    textTertiary: Color(0xFF138A7D),
    divider: Color(0xFFC5A57E),
    accent: Color(0xFFEB5B00), // Bright Orange
    keypadBackground: Color(0xFFF5E8D8),
    keypadButton: Color(0xFFD69A3C),
    keypadButtonText: Colors.white,
    keyboardPrimary: Color(0xFFF5E8D8),
    keyboardSecondary: Color(0xFFD69A3C),
    backgroundImage: 'assets/imgs/background_honey_mustard.svg',
    textureIntensity: 0.18,
    textureScale: 1.0,
  );

  static const forestMoss = AppColors(
    displayBackground: Color(0xFFE8F0E5), // Pale sage/mist
    containerBackground: Color(
      0xFF4A6741,
    ), // Deep Forest Green (Main display area)
    textPrimary: Color(0xFF1B2E1D), // Deep Evergreen
    textSecondary: Color(0xFF6B8E23), // Olive Drab
    textTertiary: Color(0xFFD4A373), // Raw Sienna (Woody accent)
    divider: Color(0xFFBDC7BC), // Muted leaf grey
    accent: Color(0xFF2D5A27), // Strong Jungle Green
    keypadBackground: Color(0xFFF1F4F0), // Soft off-white green
    keypadButton: Color(0xFFBDCBB7), // Muted eucalyptus
    keypadButtonText: Color(0xFF2A3B24), // Dark moss text
    keyboardPrimary: Color(0xFFF1F4F0),
    keyboardSecondary: Color(0xFFBDCBB7),
    backgroundImage: 'assets/imgs/background_forest_moss.svg',
    textureIntensity: 0.2,
    textureSoftness: 2,
  );

  // Helper to get colors based on context
  static AppColors of(BuildContext context, {bool listen = true}) {
    final settings = Provider.of<SettingsProvider>(context, listen: listen);
    return fromType(settings.themeType);
  }

  static AppColors fromType(ThemeType type) {
    switch (type) {
      case ThemeType.classic:
        return classic;
      case ThemeType.dark:
        return dark;
      case ThemeType.softPink:
        return softPink;
      case ThemeType.pink:
        return pink;
      case ThemeType.sunsetEmber:
        return sunsetEmber;
      case ThemeType.desertSand:
        return desertSand;
      case ThemeType.digitalAmber:
        return digitalAmber;
      case ThemeType.roseChic:
        return roseChic;
      case ThemeType.honeyMustard:
        return honeyMustard;
      case ThemeType.forestMoss:
        return forestMoss;
    }
  }
}
