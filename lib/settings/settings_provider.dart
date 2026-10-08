import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../math_renderer/renderer.dart';
import '../plotting/utils/colormap.dart';
import '../utils/constants.dart';
import '../utils/system_font.dart';

enum ThemeType {
  /// Dark ink on pale paper. The default.
  light,
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

  /// The phone's own font, offered beside the two the app carries.
  ///
  /// Not a family the app declares: what it draws in is worked out on the
  /// phone (see [SystemFont] and [textFontFamily]).
  static const String systemFont = 'System';

  /// The font families the user can pick between.
  ///
  /// Every name but [systemFont] has to be a family declared in pubspec.yaml,
  /// or choosing it silently falls back to the default. Kept here rather than
  /// on the screen so a saved choice can be checked against it when settings
  /// load.
  static const List<String> availableFonts = <String>[
    'OpenSans',
    'STIXTwoMath',
    systemFont,
  ];
  static const double maxButtonSpacing = 12.0;

  /// Light is the default: dark ink on pale paper.
  ThemeType _themeType = ThemeType.light;
  bool _hapticFeedback = true;
  bool _confirmClearAll = true;
  String _multiplicationSign = '\u00D7'; // Default: ×
  double _borderRadius = 5.0;
  double _buttonSpacing = 1.0;
  String _fontFamily = FONTFAMILY;
  KeypadColorMode _keypadColorMode = KeypadColorMode.themeBased;
  Handedness _handedness = Handedness.rightHanded;
  PlotColorMode _plotColorMode = PlotColorMode.themeBased;
  PlotPalette _plotPalette = PlotPalette.turbo;

  // Getters
  ThemeType get themeType => _themeType;
  bool get isDarkTheme =>
      _themeType != ThemeType.light &&
      _themeType != ThemeType.classic &&
      _themeType != ThemeType.softPink &&
      _themeType != ThemeType.desertSand &&
      _themeType != ThemeType.honeyMustard;
  bool get hapticFeedback => _hapticFeedback;

  /// Whether ⌧ asks before wiping every cell.
  ///
  /// On by default, because the key sits beside undo and redo and looks like
  /// any other glyph, so the first press is usually an accident. Off is a
  /// reasonable choice once you know the press is undoable — which is what
  /// the dialog exists to say.
  bool get confirmClearAll => _confirmClearAll;
  String get multiplicationSign => _multiplicationSign;
  double get borderRadius => _borderRadius;
  double get buttonSpacing => _buttonSpacing;
  /// The font chosen in Settings, as it is offered there.
  String get fontFamily => _fontFamily;

  /// The family text is drawn in: the one chosen, or for [systemFont] the
  /// phone's font where it had to be loaded, and otherwise null — the
  /// platform's default, which is the system font everywhere else.
  String? get textFontFamily =>
      _fontFamily == systemFont ? SystemFont.family : _fontFamily;
  KeypadColorMode get keypadColorMode => _keypadColorMode;

  /// Applies to both the tablet block order and the phone's number pad.
  Handedness get handedness => _handedness;
  PlotColorMode get plotColorMode => _plotColorMode;

  /// The ramp surfaces and colorbars are coloured with by value.
  PlotPalette get plotPalette => _plotPalette;

  // Static method to create provider with preloaded settings
  static Future<SettingsProvider> create() async {
    final provider = SettingsProvider._();
    await provider._loadSettings();
    return provider;
  }

  // Private constructor
  SettingsProvider._();

  SettingsProvider._forTesting({
    ThemeType themeType = ThemeType.light,
    String multiplicationSign = '×',
    String? fontFamily,
  }) : _themeType = themeType,
       _multiplicationSign = multiplicationSign,
       _fontFamily = fontFamily ?? FONTFAMILY;

  // Factory constructor for tests
  static SettingsProvider forTesting({
    ThemeType themeType = ThemeType.light,
    String multiplicationSign = '×',
    String? fontFamily,
  }) {
    return SettingsProvider._forTesting(
      themeType: themeType,
      multiplicationSign: multiplicationSign,
      fontFamily: fontFamily,
    );
  }

  // Load all settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load theme
    String? themeStr = prefs.getString('themeType');
    if (themeStr != null) {
      _themeType = ThemeType.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => ThemeType.light,
      );
    } else if (prefs.containsKey('isDarkTheme')) {
      // An older install, from before themes were named. Keep the two it knew
      // about: classic was what "not dark" meant then, and someone who chose
      // it should not be moved to a different theme by an update.
      _themeType =
          (prefs.getBool('isDarkTheme') ?? false)
              ? ThemeType.dark
              : ThemeType.classic;
    }
    // Otherwise a fresh install, which keeps the default: light.

    _hapticFeedback = prefs.getBool('hapticFeedback') ?? true;
    _confirmClearAll = prefs.getBool('confirmClearAll') ?? true;
    _multiplicationSign = prefs.getString('multiplicationSign') ?? '\u00D7';
    _borderRadius = (prefs.getDouble('borderRadius') ?? 5.0).clamp(
      0.0,
      maxButtonRadius,
    );
    _buttonSpacing = (prefs.getDouble('buttonSpacing') ?? 1.0).clamp(
      1.0,
      maxButtonSpacing,
    );


    // Load font family
    // Cambria became STIX Two Math: Cambria Math is Microsoft's and cannot be
    // shipped inside the app, so a saved choice of it carries over to its free
    // equivalent. Any other family no longer offered falls back to the
    // default, rather than handing the settings menu a value it cannot show.
    //
    // Rosemary was carried in the app for a phone whose own font it is. It is
    // Samsung's, so it could not stay, and the phone's own font is offered in
    // its place — which on that phone is Rosemary.
    final String savedFont = prefs.getString('fontFamily') ?? FONTFAMILY;
    _fontFamily = switch (savedFont) {
      'Cambria' => 'STIXTwoMath',
      'Rosemary' => systemFont,
      _ => savedFont,
    };
    if (!availableFonts.contains(_fontFamily)) _fontFamily = FONTFAMILY;
    // Before the first frame, so text is not laid out once in the default
    // and again in the phone's font a moment later.
    if (_fontFamily == systemFont) await SystemFont.load();

    // Load keypad color mode
    final String paletteStr = prefs.getString('plotPalette') ?? 'turbo';
    _plotPalette = PlotPalette.values.firstWhere(
      (e) => e.name == paletteStr,
      orElse: () => PlotPalette.turbo,
    );

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

    // Set global multiplication sign on load
    MathTextStyle.setMultiplySign(_multiplicationSign);

    // Set global font family on load
    MathTextStyle.setFontFamily(textFontFamily);

    notifyListeners();
  }

  // Setters with persistence
  Future<void> setThemeType(ThemeType value) async {
    _themeType = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeType', value.name);
    notifyListeners();
  }

  Future<void> toggleDarkTheme(bool value) async {
    await setThemeType(value ? ThemeType.dark : ThemeType.classic);
  }

  Future<void> toggleHapticFeedback(bool value) async {
    _hapticFeedback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticFeedback', value);
    notifyListeners();
  }

  Future<void> toggleConfirmClearAll(bool value) async {
    _confirmClearAll = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirmClearAll', value);
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

  Future<void> setFontFamily(String value) async {
    _fontFamily = value;
    if (value == systemFont) await SystemFont.load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fontFamily', value);

    // Update MathTextStyle
    MathTextStyle.setFontFamily(textFontFamily);
    notifyListeners();
  }

  Future<void> setPlotPalette(PlotPalette value) async {
    _plotPalette = value;
    // The painters read it from the colormap module, which every colouring by
    // value goes through.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plotPalette', value.name);
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
