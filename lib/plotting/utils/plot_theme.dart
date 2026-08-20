import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../settings/settings_provider.dart';
import '../../utils/app_colors.dart';

class PlotThemeData {
  /// How strongly the plot ground is lit, 0 flat to 1 full.
  ///
  /// This was flat, and on purpose. A vignette competes with the data twice
  /// over: the same curve colour reads at a different contrast depending where
  /// it sits, and in 3D the surface shading already carries form through
  /// lightness, so a ground that also varies in lightness argues with it.
  /// Scientific plotting surfaces are flat for that reason, and the earlier
  /// version swung 20-40% from centre to edge, which is far too much to sit
  /// behind a colour ramp.
  ///
  /// Kept as a knob rather than a decision, because it is a matter of taste
  /// and the depth does make a 3D plot sit in space rather than float on a
  /// panel. Set it to 0 for a flat ground.
  ///
  /// 0.75 gives about a 14% swing. That is deliberately more than the 12% this
  /// started at: the plot panel is opaque on ten of the eleven themes, so the
  /// wallpaper behind it never shows and this gradient is the only thing
  /// carrying depth there. It is worth knowing that 14% is approaching the
  /// 20-40% the original vignette was removed for — the reason that was too
  /// much has not changed, and if a colour ramp ever starts reading
  /// differently at the rim than at the centre, this is the number to lower.
  static const double backgroundDepth = 0.75;

  /// How opaque the plot's own ground is, 0 clear to 1 solid.
  ///
  /// The plot fills the page now and the expression rows float over it, so
  /// this is the only thing standing between the data and the wallpaper.
  static const double groundOpacity = 0.86;

  /// The overlay controls that sit on the plot: 2D/3D, zoom, surface, pan.
  ///
  /// They were a fixed teal-and-white — an accent that matched no theme, and
  /// idle colours of `white24`/`white54` that all but vanished on a light
  /// ground. Both now come from the same place as the axes and labels, so a
  /// control is legible wherever it is drawn and the highlight is the theme's
  /// own accent.
  final Color controlActive;
  final Color controlIdle;
  final Color controlOutline;
  final Color controlFill;

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
    required this.controlActive,
    required this.controlIdle,
    required this.controlOutline,
    required this.controlFill,
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

  /// Built themes, kept so the same one is handed out rather than rebuilt.
  ///
  /// A theme depends only on the app palette, the plot colour mode and the
  /// theme type — none of which change while a frame is being drawn. It was
  /// being rebuilt at every call site that wanted a colour off it, dozens of
  /// times per frame, and it is not a cheap object: palettes, gradients and a
  /// couple of dozen derived colours.
  ///
  /// Cleared when the settings that feed it change; see [clearCache].
  static final Map<String, PlotThemeData> _cache = <String, PlotThemeData>{};

  /// Throw away the built themes.
  ///
  /// Called when a setting they derive from changes — the plot's depth knob,
  /// the colour mode, the app theme — because the key cannot see those.
  static void clearCache() => _cache.clear();

  factory PlotThemeData.fromColors(
    AppColors colors, {
    PlotColorMode mode = PlotColorMode.themeBased,
    ThemeType themeType = ThemeType.classic,
  }) {
    final String key =
        '${themeType.name}|${mode.name}|'
        '${colors.displayBackground.toARGB32()}|${colors.accent.toARGB32()}';
    final PlotThemeData? hit = _cache[key];
    if (hit != null) return hit;
    return _cache[key] = PlotThemeData._build(colors, mode, themeType);
  }

  factory PlotThemeData._build(
    AppColors colors,
    PlotColorMode mode,
    ThemeType themeType,
  ) {
    // Whether the plot surface is light is a property of the plot, not of the
    // app chrome — a dark app can carry a light plot and vice versa.
    final bool isLight = switch (mode) {
      PlotColorMode.light => true,
      PlotColorMode.dark => false,
      PlotColorMode.themeBased =>
        colors.displayBackground.computeLuminance() > 0.5,
    };

    // How much the ground lifts from its edges towards the light. See
    // [backgroundDepth].
    final Color surface =
        mode == PlotColorMode.themeBased
            ? colors.displayBackground
            : (isLight ? const Color(0xFFFBFBFD) : const Color(0xFF15171C));

    /// Lighten or darken [c], keeping its transparency.
    ///
    /// The plot panel is translucent in most themes — classic's is white at
    /// 38% — and lerping towards opaque white or black drags the alpha along
    /// with the colour. The edge of the ground then became *more* opaque than
    /// its middle, so on a light app background the vignette came out
    /// inverted: the corners read brighter than the lit centre.
    Color shift(Color c, double amount) {
      if (amount == 0) return c;
      final Color mixed =
          (amount > 0
              ? Color.lerp(c, Colors.white, amount)
              : Color.lerp(c, Colors.black, -amount)) ??
          c;
      return mixed.withValues(alpha: c.a);
    }

    // The lit centre and the fall-off at the corners. Both are measured from
    // the panel colour so every theme keeps its own ground and only the
    // shading is shared.
    //
    // A light panel is lit by darkening its edges and a dark one by lifting
    // its middle: adding white to something already near white does nothing
    // visible, and neither does adding black to near-black.
    final double lift = backgroundDepth;
    // A light panel is lit by darkening its rim and a dark one by lifting its
    // middle: adding white to something already near white does nothing
    // visible, and neither does adding black to near-black.
    //
    // The two sides need very different amounts, which is why light themes
    // showed no depth at all while dark ones read perfectly. A dark ground was
    // getting a 0.55 lift and a light one only a 0.20 darkening — and on top of
    // that the eye reads lightness relatively, so the smaller change on the
    // brighter ground was doubly invisible. 0.50 brings them to the same order.
    // A translucent panel dilutes its own gradient: classic's is white at 38%,
    // so only 38% of any shading it carries reaches the screen and it read
    // flatter than the opaque light themes beside it. Compensating by the
    // panel's own alpha puts them on the same footing. Bounded, so a nearly
    // invisible panel cannot ask for an impossible shift.
    // Capped well short of full compensation. A 38% panel cannot carry full
    // contrast however hard the stops are pushed — asking for it drove the rim
    // to almost pure black and saturated. 1.8 is the most that still buys
    // depth without the rim going flat.
    final double sheer = (1 / math.max(surface.a, 0.30)).clamp(1.0, 1.8);
    final Color surfaceCentre =
        isLight
            ? shift(surface, 0.06 * lift * sheer)
            : shift(surface, 0.55 * lift);
    final Color surfaceEdge =
        isLight
            ? shift(surface, -0.50 * lift * sheer - 0.02)
            : shift(surface, -0.22 * lift + 0.02);

    // Radial rather than top-to-bottom, and off-centre: a light that sits
    // above and slightly left of the plot reads as a light in a room, while
    // one dead centre reads as a spotlight and draws the eye to the middle of
    // the data.
    /// The panel's own translucency, so the wallpaper is still visible.
    ///
    /// The plot used to occupy the upper part of the page and the expression
    /// band below it showed the app background. The plot fills the page now,
    /// so on every theme whose panel colour is opaque the wallpaper was hidden
    /// completely. Classic was the exception only because its panel happens to
    /// be white at 38%.
    ///
    /// Lower this to see more of the wallpaper, raise it towards 1 for a flat
    /// ground with more contrast under the data.
    Color sheerer(Color c) =>
        c.withValues(alpha: c.a * PlotThemeData.groundOpacity);

    Gradient ground() {
      if (backgroundDepth <= 0) {
        // Flat. The 2% wash is kept only so the panel does not read as a dead
        // rectangle.
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[sheerer(surface), sheerer(surfaceEdge)],
        );
      }
      return RadialGradient(
        center: const Alignment(-0.25, -0.45),
        radius: 1.15,
        colors: <Color>[
          sheerer(surfaceCentre),
          sheerer(surface),
          sheerer(surfaceEdge),
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      );
    }

    final background2D = ground();
    final background3D = ground();

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

    final Color accent = colors.accent;
    return PlotThemeData(
      controlActive: accent,
      controlIdle: lineBase.withValues(alpha: isLight ? 0.55 : 0.60),
      controlOutline: lineBase.withValues(alpha: isLight ? 0.28 : 0.24),
      controlFill: accent.withValues(alpha: isLight ? 0.22 : 0.30),
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
