import 'package:flutter/material.dart';
import '../../settings/settings_provider.dart';
import '../../utils/app_colors.dart';

class PlotThemeData {
  final Gradient background2D;
  final Gradient background3D;
  final Color grid;
  final Color subGrid;
  final Color axis;
  final Color tick;
  final Color label;
  final Color boundary;
  final Color colorbarBorder;
  final Color colorbarText;
  final Color wireframe;
  final Color axisX;
  final Color axisY;
  final Color axisZ;

  /// Colours for successive curves on one plot, assigned in order and never
  /// cycled by rank — curve 1 keeps its colour when curve 2 is deleted.
  final List<Color> seriesColors;

  const PlotThemeData({
    required this.background2D,
    required this.background3D,
    required this.grid,
    required this.subGrid,
    required this.axis,
    required this.tick,
    required this.label,
    required this.boundary,
    required this.colorbarBorder,
    required this.colorbarText,
    required this.wireframe,
    required this.axisX,
    required this.axisY,
    required this.axisZ,
    required this.seriesColors,
  });

  /// Colour of the nth curve on a plot.
  Color seriesColor(int index) => seriesColors[index % seriesColors.length];

  factory PlotThemeData.fromColors(
    AppColors colors, {
    PlotColorMode mode = PlotColorMode.themeBased,
    ThemeType themeType = ThemeType.classic,
  }) {
    // Whether the plot surface is light is a property of the plot, not of the
    // app chrome — a dark app can carry a light plot and vice versa.
    final bool isLight = switch (mode) {
      PlotColorMode.light => true,
      PlotColorMode.dark => false,
      PlotColorMode.themeBased =>
        colors.displayBackground.computeLuminance() > 0.5,
    };

    // A flat surface, not a vignette.
    //
    // The previous radial gradient ran a ~20-40% lightness swing from centre
    // to edge. That competes with the data twice over: the same curve colour
    // reads at different contrast depending where it sits, and in 3D the
    // surface shading already encodes form through lightness, so a background
    // that also varies in lightness fights it. Scientific plotting surfaces
    // are flat for exactly this reason. A 2% wash is kept only so the panel
    // does not read as a dead rectangle.
    final Color surface =
        mode == PlotColorMode.themeBased
            ? colors.displayBackground
            : (isLight ? const Color(0xFFFBFBFD) : const Color(0xFF15171C));

    Color shift(Color c, double amount) {
      if (amount == 0) return c;
      return (amount > 0
              ? Color.lerp(c, Colors.white, amount)
              : Color.lerp(c, Colors.black, -amount)) ??
          c;
    }

    final Color surfaceEdge = shift(surface, isLight ? -0.02 : 0.02);

    final background2D = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [surface, surfaceEdge],
    );
    final background3D = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [surface, surfaceEdge],
    );

    // Ink derives from the plot surface, not the app text colour — otherwise a
    // light plot inside a dark theme draws white axes on a white ground.
    final Color lineBase = isLight ? Colors.black : Colors.white;
    final grid = lineBase.withValues(alpha: isLight ? 0.16 : 0.20);
    final subGrid = lineBase.withValues(alpha: isLight ? 0.08 : 0.10);
    final axis = lineBase.withValues(alpha: isLight ? 0.45 : 0.60);
    final tick = lineBase.withValues(alpha: isLight ? 0.35 : 0.50);
    final label = lineBase.withValues(alpha: isLight ? 0.75 : 0.80);
    final boundary = lineBase.withValues(alpha: isLight ? 0.50 : 0.65);
    final colorbarBorder = lineBase.withValues(alpha: isLight ? 0.45 : 0.60);
    final colorbarText = lineBase.withValues(alpha: isLight ? 0.80 : 0.85);
    final wireframe = lineBase.withValues(alpha: isLight ? 0.12 : 0.18);

    Color axisTone(Color baseColor) =>
        (isLight
            ? Color.lerp(baseColor, Colors.black, 0.25)
            : Color.lerp(baseColor, Colors.white, 0.20)) ??
        baseColor;

    return PlotThemeData(
      background2D: background2D,
      background3D: background3D,
      grid: grid,
      subGrid: subGrid,
      axis: axis,
      tick: tick,
      label: label,
      boundary: boundary,
      colorbarBorder: colorbarBorder,
      colorbarText: colorbarText,
      wireframe: wireframe,
      axisX: axisTone(const Color(0xFFEF5350)),
      axisY: axisTone(const Color(0xFF66BB6A)),
      axisZ: axisTone(const Color(0xFF42A5F5)),
      seriesColors: _seriesFor(themeType, isLight),
    );
  }

  // ============================================================
  // PER-THEME SERIES PALETTES
  //
  // One palette cannot serve every theme: a set tuned for a warm sand ground
  // disappears against forest green, and curves that read on a dark surface
  // are washed out on a light one. Each theme family names its own ordered
  // set, with light and dark variants — the dark variants are lifted and
  // desaturated rather than being the same hues dimmed.
  //
  // Hues are ordered for maximum separation between *adjacent* entries, since
  // the first two are what most plots actually use.
  // ============================================================

  static const List<Color> _neutralLight = <Color>[
    Color(0xFF1F6FEB), // blue
    Color(0xFFD1495B), // red
    Color(0xFF1B998B), // teal
    Color(0xFFE07A1F), // orange
    Color(0xFF7B4EA8), // violet
    Color(0xFF4C7A2F), // green
  ];
  static const List<Color> _neutralDark = <Color>[
    Color(0xFF6BA8FF),
    Color(0xFFFF7D8F),
    Color(0xFF4FD1BE),
    Color(0xFFFFB25E),
    Color(0xFFC08BEB),
    Color(0xFF9BD675),
  ];

  // Warm grounds (ember, sand, amber, mustard): lead with a cool anchor.
  static const List<Color> _warmLight = <Color>[
    Color(0xFF1D5C8F),
    Color(0xFFB3322C),
    Color(0xFF00786E),
    Color(0xFF8A5A00),
    Color(0xFF6D3FA0),
    Color(0xFF3F6B22),
  ];
  static const List<Color> _warmDark = <Color>[
    Color(0xFF7FC0FF),
    Color(0xFFFF8A73),
    Color(0xFF54D6C4),
    Color(0xFFFFC978),
    Color(0xFFC79BF0),
    Color(0xFFA9DD7E),
  ];

  // Pink grounds: teal-blue and green separate best from the surface hue.
  static const List<Color> _pinkLight = <Color>[
    Color(0xFF15607A),
    Color(0xFF9C2D63),
    Color(0xFF3F7A34),
    Color(0xFFC2621B),
    Color(0xFF5B4BB5),
    Color(0xFF8A6A17),
  ];
  static const List<Color> _pinkDark = <Color>[
    Color(0xFF6FD3F0),
    Color(0xFFFF8FC4),
    Color(0xFF8ADD82),
    Color(0xFFFFB070),
    Color(0xFFA6A0FF),
    Color(0xFFE3C766),
  ];

  // Green ground: blue and magenta hold up best.
  static const List<Color> _greenLight = <Color>[
    Color(0xFF1B4F9C),
    Color(0xFFB02E7A),
    Color(0xFF8A5A00),
    Color(0xFF00706B),
    Color(0xFF7A3FA8),
    Color(0xFFB33A2F),
  ];
  static const List<Color> _greenDark = <Color>[
    Color(0xFF79B4FF),
    Color(0xFFFF8ECB),
    Color(0xFFFFC46B),
    Color(0xFF57D5CC),
    Color(0xFFC199F5),
    Color(0xFFFF8E7E),
  ];

  static List<Color> _seriesFor(ThemeType theme, bool isLight) {
    switch (theme) {
      case ThemeType.sunsetEmber:
      case ThemeType.desertSand:
      case ThemeType.digitalAmber:
      case ThemeType.honeyMustard:
        return isLight ? _warmLight : _warmDark;
      case ThemeType.softPink:
      case ThemeType.pink:
      case ThemeType.roseChic:
        return isLight ? _pinkLight : _pinkDark;
      case ThemeType.forestMoss:
        return isLight ? _greenLight : _greenDark;
      case ThemeType.classic:
      case ThemeType.dark:
        return isLight ? _neutralLight : _neutralDark;
    }
  }
}
