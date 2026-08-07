import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/app_colors.dart';
import '../utils/texture_generator.dart';
import 'settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onShowTutorial;

  const SettingsScreen({super.key, this.onShowTutorial});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const double _sliderControlWidth = 160;
  static const double _toggleControlWidth = 120;
  static const double _maxButtonRadius = SettingsProvider.maxButtonRadius;
  static const double _maxButtonSpacing = SettingsProvider.maxButtonSpacing;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final colors = AppColors.of(context);

    final activeColor = colors.accent;
    final activeTrackColor = colors.accent.withValues(alpha: 0.5);
    final sliderActiveColor = colors.accent;

    return Scaffold(
      backgroundColor: colors.displayBackground,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.displayBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSectionCard(
                  colors: colors,
                  title: 'CALCULATION',
                  children: [
                    _buildPrecisionControl(
                      settings: settings,
                      colors: colors,
                      sliderActiveColor: sliderActiveColor,
                    ),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildNumberFormatControl(
                      settings: settings,
                      colors: colors,
                    ),
                  ],
                ),
                _buildSectionCard(
                  colors: colors,
                  title: 'BUTTON PREFERENCES',
                  children: [
                    _buildInlineSegmentedControl<String>(
                      colors: colors,
                      label: 'Multiplication Sign',
                      value: settings.multiplicationSign,
                      options: const [
                        _SegmentOption<String>(
                          value: '\u00D7',
                          label: '\u00D7',
                          fontSize: 18,
                        ),
                        _SegmentOption<String>(
                          value: '\u00B7',
                          label: '\u00B7',
                          fontSize: 18,
                        ),
                      ],
                      onChanged:
                          (value) => settings.setMultiplicationSign(value),
                    ),
                  ],
                ),
                _buildSectionCard(
                  colors: colors,
                  title: 'APPEARANCE',
                  children: [
                    _buildThemeControl(settings: settings, colors: colors),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildTextureTypeControl(
                      settings: settings,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildKeypadColorControl(
                      settings: settings,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildHandednessControl(
                      settings: settings,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildPlotColorControl(
                      settings: settings,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildFontFamilyControl(settings: settings, colors: colors),
                    const SizedBox(height: 10),
                    Divider(color: colors.divider.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    _buildButtonRadiusControl(
                      settings: settings,
                      colors: colors,
                      sliderActiveColor: sliderActiveColor,
                    ),
                    const SizedBox(height: 16),
                    _buildButtonSpacingControl(
                      settings: settings,
                      colors: colors,
                      sliderActiveColor: sliderActiveColor,
                    ),
                  ],
                ),
                _buildSectionCard(
                  colors: colors,
                  title: 'INTERACTION',
                  children: [
                    _buildHapticControl(
                      settings: settings,
                      colors: colors,
                      activeColor: activeColor,
                      activeTrackColor: activeTrackColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: ListTile(
                leading: Icon(Icons.school_outlined, color: colors.textPrimary),
                title: Text(
                  'Show Tutorial',
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  'Learn how to use the calculator',
                  style: TextStyle(color: colors.textSecondary),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: colors.textPrimary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: colors.containerBackground,
                onTap: () {
                  if (widget.onShowTutorial != null) {
                    widget.onShowTutorial!();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Computes an appropriate opaque card color for the settings tiles
  Color _getCardColor(AppColors colors) {
    final bg = colors.displayBackground;

    // Check if displayBackground is semi-transparent or fully black
    final needsAdjustment = bg.a < 1.0 || (bg.r == 0 && bg.g == 0 && bg.b == 0);

    if (needsAdjustment) {
      // Determine if we're in a dark or light themed context
      final isDark =
          ThemeData.estimateBrightnessForColor(colors.containerBackground) ==
          Brightness.dark;

      if (isDark) {
        // For dark themes, create a raised surface color
        // Blend displayBackground with a lighter base
        if (bg.a < 1.0) {
          return Color.alphaBlend(bg, const Color(0xFF2D2D2D));
        }
        // For pure black, lighten slightly
        return HSLColor.fromColor(colors.containerBackground)
            .withLightness(
              (HSLColor.fromColor(colors.containerBackground).lightness + 0.05)
                  .clamp(0.0, 1.0),
            )
            .toColor();
      } else {
        // For light themes with transparency, blend with off-white
        return Color.alphaBlend(bg, const Color(0xFFF5F5F5));
      }
    }

    return bg;
  }

  Widget _buildSectionCard({
    required AppColors colors,
    required String title,
    required List<Widget> children,
  }) {
    final isDark =
        ThemeData.estimateBrightnessForColor(colors.displayBackground) ==
        Brightness.dark;

    final cardColor = _getCardColor(colors);

    final shadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
        blurRadius: 16,
        offset: const Offset(0, 6),
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
        blurRadius: 24,
        offset: const Offset(0, 12),
        spreadRadius: -4,
      ),
    ];

    return RepaintBoundary(
      child: Container(
        key: ValueKey('card_${cardColor.toARGB32()}_$title'),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: shadows,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrecisionControl({
    required SettingsProvider settings,
    required AppColors colors,
    required Color sliderActiveColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Precision',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        SizedBox(
          width: _sliderControlWidth,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 2,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: sliderActiveColor,
                    inactiveTrackColor: colors.divider.withValues(alpha: 0.4),
                    thumbColor: sliderActiveColor,
                  ),
                  child: Slider(
                    value: settings.precision,
                    min: 0,
                    max: 16,
                    divisions: 16,
                    onChanged: (value) => settings.setPrecision(value),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  settings.precision.toInt().toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _foregroundFor(colors.accent),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumberFormatControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Number Format',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<NumberFormat>(
          colors: colors,
          value: settings.numberFormat,
          items: NumberFormat.values,
          labelBuilder: _getNumberFormatLabel,
          onChanged: (value) => settings.setNumberFormat(value),
        ),
      ],
    );
  }

  Widget _buildThemeControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Theme',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<ThemeType>(
          colors: colors,
          value: settings.themeType,
          items: ThemeType.values,
          labelBuilder: _getThemeLabel,
          onChanged: (value) => settings.setThemeType(value),
        ),
      ],
    );
  }

  Widget _buildTextureTypeControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Background Texture',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<TextureType>(
          colors: colors,
          value: settings.textureType,
          items: TextureType.values,
          labelBuilder: _getTextureTypeLabel,
          onChanged: (value) => settings.setTextureType(value),
        ),
      ],
    );
  }

  Widget _buildKeypadColorControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Keypad Color',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<KeypadColorMode>(
          colors: colors,
          value: settings.keypadColorMode,
          items: KeypadColorMode.values,
          labelBuilder: _getKeypadColorModeLabel,
          onChanged: (value) => settings.setKeypadColorMode(value),
        ),
      ],
    );
  }

  /// Applies on every device: the tablet mirrors its three blocks, and the
  /// phone mirrors its fixed number pad.
  Widget _buildHandednessControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Handedness',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<Handedness>(
          colors: colors,
          value: settings.handedness,
          items: Handedness.values,
          labelBuilder: _getHandednessLabel,
          onChanged: (value) => settings.setHandedness(value),
        ),
      ],
    );
  }

  String _getHandednessLabel(Handedness value) {
    switch (value) {
      case Handedness.rightHanded:
        return 'Right';
      case Handedness.leftHanded:
        return 'Left';
    }
  }

  Widget _buildPlotColorControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Plot Color',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<PlotColorMode>(
          colors: colors,
          value: settings.plotColorMode,
          items: PlotColorMode.values,
          labelBuilder: _getPlotColorModeLabel,
          onChanged: (value) => settings.setPlotColorMode(value),
        ),
      ],
    );
  }

  Widget _buildButtonRadiusControl({
    required SettingsProvider settings,
    required AppColors colors,
    required Color sliderActiveColor,
  }) {
    final value = settings.borderRadius.clamp(0.0, _maxButtonRadius);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Button Radius',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        SizedBox(
          width: _sliderControlWidth,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 2,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: sliderActiveColor,
                    inactiveTrackColor: colors.divider.withValues(alpha: 0.4),
                    thumbColor: sliderActiveColor,
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: _maxButtonRadius,
                    divisions: _maxButtonRadius.toInt(),
                    onChanged: (next) => settings.setBorderRadius(next),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.round().toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _foregroundFor(colors.accent),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtonSpacingControl({
    required SettingsProvider settings,
    required AppColors colors,
    required Color sliderActiveColor,
  }) {
    final value = settings.buttonSpacing.clamp(0.0, _maxButtonSpacing);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Button Spacing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        SizedBox(
          width: _sliderControlWidth,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 2,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: sliderActiveColor,
                    inactiveTrackColor: colors.divider.withValues(alpha: 0.4),
                    thumbColor: sliderActiveColor,
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: _maxButtonSpacing,
                    divisions: _maxButtonSpacing.toInt(),
                    onChanged: (next) => settings.setButtonSpacing(next),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.round().toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _foregroundFor(colors.accent),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernDropdown<T>({
    required AppColors colors,
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    final isDark =
        ThemeData.estimateBrightnessForColor(colors.displayBackground) ==
        Brightness.dark;

    final cardColor = _getCardColor(colors);

    // Compute dropdown button background - slightly different from card
    final dropdownBg =
        isDark
            ? Color.lerp(cardColor, Colors.white, 0.05)!
            : Color.lerp(cardColor, Colors.black, 0.03)!;

    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      elevation: 8,
      itemBuilder:
          (context) =>
              items.map((item) {
                final isSelected = item == value;
                return PopupMenuItem<T>(
                  value: item,
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labelBuilder(item),
                        style: TextStyle(
                          color:
                              isSelected ? colors.accent : colors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 15,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_rounded,
                          color: colors.accent,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: dropdownBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.divider.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelBuilder(value),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colors.textPrimary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHapticControl({
    required SettingsProvider settings,
    required AppColors colors,
    required Color activeColor,
    required Color activeTrackColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Haptic Feedback',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        Switch(
          activeThumbColor: activeColor,
          activeTrackColor: activeTrackColor,
          inactiveThumbColor: colors.textSecondary.withValues(alpha: 0.5),
          inactiveTrackColor: colors.divider.withValues(alpha: 0.3),
          value: settings.hapticFeedback,
          onChanged: settings.toggleHapticFeedback,
        ),
      ],
    );
  }

  Widget _buildInlineSegmentedControl<T>({
    required AppColors colors,
    required String label,
    required T value,
    required List<_SegmentOption<T>> options,
    required ValueChanged<T> onChanged,
  }) {
    final selectedTextColor = _foregroundFor(colors.accent);
    final isDarkTheme =
        ThemeData.estimateBrightnessForColor(colors.displayBackground) ==
        Brightness.dark;

    final trackColor =
        isDarkTheme
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        RepaintBoundary(
          child: Container(
            key: ValueKey('toggle_${colors.accent.toARGB32()}_$label'),
            width: _toggleControlWidth,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value == options[0].value
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                  child: Container(
                    width: (_toggleControlWidth - 6) / options.length,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colors.accent.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children:
                      options.map((option) {
                        final isSelected = value == option.value;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => onChanged(option.value),
                            behavior: HitTestBehavior.opaque,
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  color:
                                      isSelected
                                          ? selectedTextColor
                                          : colors.textPrimary.withValues(
                                            alpha: 0.7,
                                          ),
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                  fontSize: option.fontSize,
                                ),
                                child: Text(option.label),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _foregroundFor(Color background) {
    final brightness = ThemeData.estimateBrightnessForColor(background);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }

  String _getNumberFormatLabel(NumberFormat format) {
    switch (format) {
      case NumberFormat.automatic:
        return 'Automatic';
      case NumberFormat.scientific:
        return 'Scientific';
      case NumberFormat.plain:
        return 'Plain (commas)';
    }
  }

  String _getPlotColorModeLabel(PlotColorMode mode) {
    switch (mode) {
      case PlotColorMode.light:
        return 'Light';
      case PlotColorMode.dark:
        return 'Dark';
      case PlotColorMode.themeBased:
        return 'Theme';
    }
  }

  String _getKeypadColorModeLabel(KeypadColorMode mode) {
    switch (mode) {
      case KeypadColorMode.light:
        return 'Light';
      case KeypadColorMode.dark:
        return 'Dark';
      case KeypadColorMode.themeBased:
        return 'Theme';
    }
  }

  String _getThemeLabel(ThemeType theme) {
    switch (theme) {
      case ThemeType.classic:
        return 'Classic';
      case ThemeType.dark:
        return 'Dark';
      case ThemeType.softPink:
        return 'Petal Soft Pink';
      case ThemeType.pink:
        return 'Midnight Peony';
      case ThemeType.sunsetEmber:
        return 'Sunset Ember';
      case ThemeType.desertSand:
        return 'Desert Sand';
      case ThemeType.digitalAmber:
        return 'Digital Amber';
      case ThemeType.roseChic:
        return 'Rose Chic';
      case ThemeType.honeyMustard:
        return 'Honey Mustard';
      case ThemeType.forestMoss:
        return 'Forest Moss';
    }
  }

  String _getTextureTypeLabel(TextureType type) {
    switch (type) {
      case TextureType.smoothNoise:
        return 'Smooth Noise';
      case TextureType.paperFiber:
        return 'Paper Grain';
      case TextureType.none:
        return 'None (Solid)';
    }
  }

  static const List<String> _availableFonts = [
    'OpenSans',
    'Cambria',
    'Rosemary',
  ];

  Widget _buildFontFamilyControl({
    required SettingsProvider settings,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Font',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        _buildModernDropdown<String>(
          colors: colors,
          value: settings.fontFamily,
          items: _availableFonts,
          labelBuilder: _getFontFamilyLabel,
          onChanged: (value) => settings.setFontFamily(value),
        ),
      ],
    );
  }

  String _getFontFamilyLabel(String family) {
    switch (family) {
      case 'OpenSans':
        return 'Open Sans';
      case 'Cambria':
        return 'Cambria';
      case 'Rosemary':
        return 'Rosemary';
      default:
        return family;
    }
  }
}

class _SegmentOption<T> {
  final T value;
  final String label;
  final double fontSize;

  const _SegmentOption({
    required this.value,
    required this.label,
    this.fontSize = 14,
  });
}
