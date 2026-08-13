import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../math_engine/math_engine.dart';
import '../math_renderer/renderer.dart';
import '../utils/constants.dart';
import '../utils/texture_generator.dart';

enum NumberFormat {
  automatic, // Scientific only for very large/small numbers
  scientific, // Always scientific notation
  plain, // Commas, never scientific
}

enum ThemeType {
  classic,
  dark,
  softPink,
  pink,
  sunsetEmber,
  desertSand,
  digitalAmber,
  roseChic,
  honeyMustard,
  forestMoss,
}

/// How the plot surface is coloured.
enum PlotColorMode {
  /// Always a light plot surface, whatever the app theme.
  light,

  /// Always a dark plot surface.
  dark,

  /// Follow the app theme.
  themeBased,
}

/// Which side the number pad sits on.
///
/// Mirrors the keypad rather than only relocating the digits: for a
/// right-hander the numbers sit under the right thumb with the function
/// blocks to their left, and the whole arrangement flips for a left-hander.
enum Handedness {
  /// Numbers on the right (default).
  rightHanded,

  /// Numbers on the left.
  leftHanded,
}

/// How the keypad buttons are coloured.
enum KeypadColorMode {
  /// Always light: white buttons with dark text.
  light,

  /// Always dark: dark buttons with light text.
  dark,

  /// Follow the selected theme's keypad colours.
  themeBased,
}

class SettingsProvider extends ChangeNotifier {
  static const double maxButtonRadius = 36.0;
  static const double maxButtonSpacing = 12.0;

  double _precision = PRECISION.toDouble();
  ThemeType _themeType = ThemeType.classic;
  bool _isRadians = false;
  bool _hapticFeedback = true;
  bool _soundEffects = false;
  String _multiplicationSign = '\u00D7'; // Default: ×
  NumberFormat _numberFormat = NumberFormat.automatic;
  bool _useScientificNotationButton = false;
  double _borderRadius = 5.0;
  double _buttonSpacing = 1.0;
  TextureType _textureType = TextureType.smoothNoise;
  String _fontFamily = FONTFAMILY;
  KeypadColorMode _keypadColorMode = KeypadColorMode.themeBased;
  Handedness _handedness = Handedness.rightHanded;
  PlotColorMode _plotColorMode = PlotColorMode.themeBased;

  // Getters
  double get precision => _precision;
  ThemeType get themeType => _themeType;
  bool get isDarkTheme =>
      _themeType != ThemeType.classic &&
      _themeType != ThemeType.softPink &&
      _themeType != ThemeType.desertSand &&
      _themeType != ThemeType.honeyMustard;
  bool get isRadians => _isRadians;
  bool get hapticFeedback => _hapticFeedback;
  bool get soundEffects => _soundEffects;
  String get multiplicationSign => _multiplicationSign;
  NumberFormat get numberFormat => _numberFormat;
  bool get useScientificNotationButton => _useScientificNotationButton;
  double get borderRadius => _borderRadius;
  double get buttonSpacing => _buttonSpacing;
  TextureType get textureType => _textureType;
  String get fontFamily => _fontFamily;
  KeypadColorMode get keypadColorMode => _keypadColorMode;

  /// Applies to both the tablet block order and the phone's number pad.
  Handedness get handedness => _handedness;
  PlotColorMode get plotColorMode => _plotColorMode;

  // Static method to create provider with preloaded settings
  static Future<SettingsProvider> create() async {
    final provider = SettingsProvider._();
    await provider._loadSettings();
    return provider;
  }

  // Private constructor
  SettingsProvider._();

  SettingsProvider._forTesting({
    ThemeType themeType = ThemeType.classic,
    String multiplicationSign = '×',
    NumberFormat numberFormat = NumberFormat.automatic,
    bool useScientificNotationButton = false,
    TextureType textureType = TextureType.smoothNoise,
    String? fontFamily,
  }) : _themeType = themeType,
       _multiplicationSign = multiplicationSign,
       _numberFormat = numberFormat,
       _useScientificNotationButton = useScientificNotationButton,
       _textureType = textureType,
       _fontFamily = fontFamily ?? FONTFAMILY;

  // Factory constructor for tests
  static SettingsProvider forTesting({
    ThemeType themeType = ThemeType.classic,
    String multiplicationSign = '×',
    NumberFormat numberFormat = NumberFormat.automatic,
    bool useScientificNotationButton = false,
    TextureType textureType = TextureType.smoothNoise,
    String? fontFamily,
  }) {
    return SettingsProvider._forTesting(
      themeType: themeType,
      multiplicationSign: multiplicationSign,
      numberFormat: numberFormat,
      useScientificNotationButton: useScientificNotationButton,
      textureType: textureType,
      fontFamily: fontFamily,
    );
  }

  // Load all settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _precision = prefs.getDouble('precision') ?? PRECISION.toDouble();

    // Load theme
    String? themeStr = prefs.getString('themeType');
    if (themeStr != null) {
      _themeType = ThemeType.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => ThemeType.classic,
      );
    } else {
      // Migrate from old isDarkTheme bool if it exists
      bool oldIsDark = prefs.getBool('isDarkTheme') ?? false;
      _themeType = oldIsDark ? ThemeType.dark : ThemeType.classic;
    }

    _isRadians = prefs.getBool('isRadians') ?? false;
    _hapticFeedback = prefs.getBool('hapticFeedback') ?? true;
    _soundEffects = prefs.getBool('soundEffects') ?? false;
    _multiplicationSign = prefs.getString('multiplicationSign') ?? '\u00D7';
    _useScientificNotationButton =
        prefs.getBool('useScientificNotationButton') ?? false;
    _borderRadius = (prefs.getDouble('borderRadius') ?? 5.0).clamp(
      0.0,
      maxButtonRadius,
    );
    _buttonSpacing = (prefs.getDouble('buttonSpacing') ?? 1.0).clamp(
      1.0,
      maxButtonSpacing,
    );

    // Load number format
    String formatStr = prefs.getString('numberFormat') ?? 'automatic';
    _numberFormat = NumberFormat.values.firstWhere(
      (e) => e.name == formatStr,
      orElse: () => NumberFormat.automatic,
    );

    // Load texture type
    String textureStr = prefs.getString('textureType') ?? 'smoothNoise';
    _textureType = TextureType.values.firstWhere(
      (e) => e.name == textureStr,
      orElse: () => TextureType.smoothNoise,
    );

    // Load font family
    _fontFamily = prefs.getString('fontFamily') ?? FONTFAMILY;

    // Load keypad color mode
    String plotColorStr = prefs.getString('plotColorMode') ?? 'themeBased';
    _plotColorMode = PlotColorMode.values.firstWhere(
      (e) => e.name == plotColorStr,
      orElse: () => PlotColorMode.themeBased,
    );

    String keypadColorStr = prefs.getString('keypadColorMode') ?? 'themeBased';
    final String handStr = prefs.getString('handedness') ?? 'rightHanded';
    _handedness = Handedness.values.firstWhere(
      (e) => e.name == handStr,
      orElse: () => Handedness.rightHanded,
    );

    _keypadColorMode = KeypadColorMode.values.firstWhere(
      (e) => e.name == keypadColorStr,
      orElse: () => KeypadColorMode.themeBased,
    );

    // Set global precision on load
    MathSolverNew.setPrecision(_precision.toInt());

    // Set global number format on load
    MathSolverNew.setNumberFormat(_numberFormat);

    // Set global multiplication sign on load
    MathTextStyle.setMultiplySign(_multiplicationSign);

    // Set global font family on load
    MathTextStyle.setFontFamily(_fontFamily);

    notifyListeners();
  }

  // Setters with persistence
  Future<void> setPrecision(double value) async {
    _precision = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('precision', value);

    // Update the global precision in MathSolverNew
    MathSolverNew.setPrecision(value.toInt());

    notifyListeners();
  }

  Future<void> setThemeType(ThemeType value) async {
    _themeType = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeType', value.name);
    notifyListeners();
  }

  Future<void> toggleDarkTheme(bool value) async {
    await setThemeType(value ? ThemeType.dark : ThemeType.classic);
  }

  Future<void> toggleRadians(bool value) async {
    _isRadians = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isRadians', value);
    notifyListeners();
  }

  Future<void> toggleHapticFeedback(bool value) async {
    _hapticFeedback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticFeedback', value);
    notifyListeners();
  }

  Future<void> toggleSoundEffects(bool value) async {
    _soundEffects = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundEffects', value);
    notifyListeners();
  }

  Future<void> setMultiplicationSign(String value) async {
    _multiplicationSign = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('multiplicationSign', value);

    // Update MathTextStyle
    MathTextStyle.setMultiplySign(value);
    notifyListeners();
  }

  Future<void> setNumberFormat(NumberFormat value) async {
    _numberFormat = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('numberFormat', value.name);

    // Update MathSolverNew
    MathSolverNew.setNumberFormat(value);
    notifyListeners();
  }

  Future<void> setUseScientificNotationButton(bool value) async {
    _useScientificNotationButton = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useScientificNotationButton', value);
    notifyListeners();
  }

  Future<void> setBorderRadius(double value) async {
    _borderRadius = value.clamp(0.0, maxButtonRadius);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('borderRadius', _borderRadius);
    notifyListeners();
  }

  Future<void> setButtonSpacing(double value) async {
    _buttonSpacing = value.clamp(1.0, maxButtonSpacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('buttonSpacing', _buttonSpacing);
    notifyListeners();
  }

  Future<void> setTextureType(TextureType value) async {
    _textureType = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('textureType', value.name);
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    _fontFamily = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fontFamily', value);

    // Update MathTextStyle
    MathTextStyle.setFontFamily(value);
    notifyListeners();
  }

  Future<void> setPlotColorMode(PlotColorMode value) async {
    _plotColorMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plotColorMode', value.name);
  }

  Future<void> setKeypadColorMode(KeypadColorMode value) async {
    _keypadColorMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('keypadColorMode', value.name);
    notifyListeners();
  }

  Future<void> setHandedness(Handedness value) async {
    _handedness = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('handedness', value.name);
    notifyListeners();
  }
}
