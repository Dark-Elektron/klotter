import 'dart:math' as math;
import 'package:flutter/painting.dart';

import '../models/point_3d.dart';

// ============================================================
// COLORMAPS
// ============================================================

Color _rampLerp(List<Color> stops, double t) {
  final double x = t.clamp(0.0, 1.0) * (stops.length - 1);
  final int i = x.floor().clamp(0, stops.length - 2);
  return Color.lerp(stops[i], stops[i + 1], x - i)!;
}

/// Which ramp a value is coloured with — chosen in the settings.
enum PlotPalette {
  /// Google's Turbo: a rainbow that runs smoothly in lightness, without jet's
  /// bright cyan and yellow bands, which read as ridges that are not in the
  /// data. The default: it keeps the rainbow's spread of hues, which separate
  /// levels well on a shaded surface.
  turbo,

  /// Perceptually uniform and safe under colour-vision deficiency; lightness
  /// rises steadily from dark purple to yellow.
  viridis,
}

/// Turbo at [t], from the polynomial fit published with it (Mikhailov, 2019).
///
/// A close fit rather than the reference table: through the body of the ramp
/// the two are indistinguishable, and at the very ends the fit is a few
/// per cent off — its darkest violet is a shade greyer. The table is 256 rows
/// for a difference no one could point to on a surface.
Color _turboAt(double t) {
  double channel(
    double c0,
    double c1,
    double c2,
    double c3,
    double c4,
    double c5,
  ) =>
      (c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * c5))))).clamp(0.0, 1.0);
  final double r = channel(
    0.13572138,
    4.61539260,
    -42.66032258,
    132.13108234,
    -152.94239396,
    59.28637943,
  );
  final double g = channel(
    0.09140261,
    2.19418839,
    4.84296658,
    -14.18503333,
    4.27729857,
    2.82956604,
  );
  final double b = channel(
    0.10667330,
    12.64194608,
    -60.58204836,
    110.36276771,
    -89.90310912,
    27.34824973,
  );
  return Color.fromARGB(
    255,
    (r * 255).round(),
    (g * 255).round(),
    (b * 255).round(),
  );
}

/// Turbo sampled into evenly spaced stops, so the colorbar — a gradient over
/// stops — and [plotColormap] are the same ramp. Thirty-three is fine enough
/// that interpolating between them is indistinguishable from the curve.
final List<Color> _turbo = List<Color>.unmodifiable(<Color>[
  for (int i = 0; i <= 32; i++) _turboAt(i / 32),
]);

/// Viridis: perceptually uniform and colour-vision-deficiency safe, monotonic
/// in lightness. One of the two choices of [PlotPalette].
const List<Color> _viridis = <Color>[
  Color(0xFF440154),
  Color(0xFF472D7B),
  Color(0xFF3B528B),
  Color(0xFF2C728E),
  Color(0xFF21918C),
  Color(0xFF27AD81),
  Color(0xFF5EC962),
  Color(0xFFAADC32),
  Color(0xFFFDE725),
];

/// Single-hue teal ramp, light to dark, for the quieter surface mode.
const List<Color> _tealRamp = <Color>[
  Color(0xFFE0F2F1),
  Color(0xFFA7D8D4),
  Color(0xFF6BBFBA),
  Color(0xFF3A9E9C),
  Color(0xFF1E7D7E),
  Color(0xFF135C61),
  Color(0xFF0B3D44),
];

/// Viridis at [t], whichever ramp is in use.
Color viridisColormap(double t) => _rampLerp(_viridis, t);

/// How many discrete levels the banded ramp uses.
///
/// Eight matches the density most FEM post-processors default to: enough to
/// read a gradient, few enough that each band is a legible contour region.
const int plotColorBands = 8;

/// Quantised ramp — the NGSolve/ParaView look.
///
/// A smooth ramp shows *where* a value is; discrete bands show *which contour
/// interval* it falls in, which is what makes a level readable off the plot
/// without a probe. Each band takes the colour of its own midpoint, so the
/// colorbar's swatches are the exact colours drawn on the surface.
Color plotColormapBanded(
  double t,
  PlotPalette palette, {
  int bands = plotColorBands,
}) {
  final double clamped = t.clamp(0.0, 1.0);
  // The top edge belongs to the last band rather than starting a new one.
  final int index = (clamped * bands).floor().clamp(0, bands - 1);
  return plotColormap((index + 0.5) / bands, palette);
}

/// The band [t] falls in, and the fraction of the range each band spans.
/// Useful for drawing a colorbar whose divisions line up with the surface.
({int index, double lower, double upper}) plotColorBand(
  double t, {
  int bands = plotColorBands,
}) {
  final double clamped = t.clamp(0.0, 1.0);
  final int index = (clamped * bands).floor().clamp(0, bands - 1);
  return (index: index, lower: index / bands, upper: (index + 1) / bands);
}

/// The magnitude ramp for surfaces, contours and colorbars: [palette], the
/// one chosen in the settings.
///
/// The palette is passed in by whatever draws, rather than read from a global
/// the settings wrote into: a painter that is not told the palette changed
/// cannot know to repaint, and kept the old colours until something else
/// moved.
Color plotColormap(double t, PlotPalette palette) =>
    _rampLerp(plotColormapStops(palette), t);

/// The stops behind [plotColormap], in order from low to high.
///
/// A colorbar drawn as a gradient over these is continuous, and identical to
/// what [plotColormap] returns because both space the stops evenly. Sampling
/// the ramp into one row of pixels per bar height instead quantises it to as
/// many steps as the bar is tall, which on a high-density screen shows as
/// bands with hard edges.
List<Color> plotColormapStops(PlotPalette palette) =>
    palette == PlotPalette.viridis ? _viridis : _turbo;

// ============================================================
// PER-SURFACE RAMPS
// ============================================================

/// Ramps for telling several surfaces apart on one set of axes.
///
/// Each stays inside one hue family and runs dark at the bottom to bright at
/// the top, so height still reads within a surface while the hue says which
/// surface it is. [plotColormap] cannot do this job: give two surfaces the
/// same rainbow and every height appears in both, so the blue of one sits
/// right beside the blue of the other and neither can be followed.
const List<List<Color>> _surfaceRamps = <List<Color>>[
  // Blue
  <Color>[
    Color(0xFF0B1D51),
    Color(0xFF14357E),
    Color(0xFF1E63B8),
    Color(0xFF4E9BE0),
    Color(0xFF9FD0F5),
  ],
  // Amber
  <Color>[
    Color(0xFF4A1D03),
    Color(0xFF8A3B06),
    Color(0xFFCC6A10),
    Color(0xFFF0A030),
    Color(0xFFFFD98A),
  ],
  // Green
  <Color>[
    Color(0xFF0A2E17),
    Color(0xFF14572B),
    Color(0xFF2C8C46),
    Color(0xFF5DBE6E),
    Color(0xFFA9E6A0),
  ],
  // Magenta
  <Color>[
    Color(0xFF3B0A38),
    Color(0xFF6E1466),
    Color(0xFFA82A96),
    Color(0xFFD861BE),
    Color(0xFFF4AEE0),
  ],
  // Teal
  <Color>[
    Color(0xFF042E33),
    Color(0xFF0B565E),
    Color(0xFF11868C),
    Color(0xFF3FB8B4),
    Color(0xFF9BE7DF),
  ],
  // Crimson
  <Color>[
    Color(0xFF470A16),
    Color(0xFF80122A),
    Color(0xFFBC2740),
    Color(0xFFE4636F),
    Color(0xFFF7AFAF),
  ],
];

/// How many distinct surface ramps exist before they repeat.
int get surfaceRampCount => _surfaceRamps.length;

/// The ramp for surface [index] of [of] on the same axes.
///
/// A lone surface keeps [plotColormap], the full rainbow, because there is
/// nothing to confuse it with and the extra hue range shows its shape better.
Color Function(double) surfaceColormap(
  int index, {
  required int of,
  required PlotPalette palette,
}) {
  if (of <= 1) return (double t) => plotColormap(t, palette);
  final List<Color> ramp = _surfaceRamps[index % _surfaceRamps.length];
  return (double t) => _rampLerp(ramp, t);
}

/// The stops behind [surfaceColormap], for drawing its scale.
///
/// A colorbar is a gradient across a list of colours rather than a sampled
/// function, so it needs the stops themselves. Matches [surfaceColormap] for
/// the same arguments, including falling back to the rainbow for a lone
/// surface.
List<Color> surfaceRampStops(
  int index, {
  required int of,
  required PlotPalette palette,
}) =>
    of <= 1
        ? plotColormapStops(palette)
        : _surfaceRamps[index % _surfaceRamps.length];

/// Quieter single-hue alternative for the plain "gradient" surface mode.
Color surfaceGradientColor(double t) => _rampLerp(_tealRamp, t);

// ============================================================
// DEPTH SHADING
// ============================================================

/// Direction the key light comes from, in view space: up, slightly left, and
/// toward the viewer. Fixed to the camera rather than the model so rotating
/// the surface sweeps the highlight across it — the motion cue that makes the
/// shape read as solid.
const double _lx = -0.40;
const double _ly = -0.55;
const double _lz = 0.73;

/// How much light a face receives with no direct illumination. Without an
/// ambient floor, faces turned away from the light go black and the surface
/// reads as holes rather than shadow.
const double _ambient = 0.42;

/// Lambertian diffuse factor in `[_ambient, 1.0]` for a quad, from its
/// view-space corners. Uses the absolute dot product so the underside of a
/// surface is shaded rather than unlit.
///
/// Takes corners rather than a `Quad` because the 3D painter declares its own
/// `Quad` that shadows the one in `models/point_3d.dart`.
double quadShadeFactor(Point3D p1, Point3D p2, Point3D p4) {
  // Two edge vectors from p1.
  final double ux = p2.x - p1.x;
  final double uy = p2.y - p1.y;
  final double uz = p2.z - p1.z;
  final double vx = p4.x - p1.x;
  final double vy = p4.y - p1.y;
  final double vz = p4.z - p1.z;

  // Surface normal = u x v.
  final double nx = uy * vz - uz * vy;
  final double ny = uz * vx - ux * vz;
  final double nz = ux * vy - uy * vx;

  final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (len < 1e-9 || !len.isFinite) return 1.0;

  final double ndotl = ((nx * _lx + ny * _ly + nz * _lz) / len).abs();
  return _ambient + (1.0 - _ambient) * ndotl.clamp(0.0, 1.0);
}

/// Apply a shade factor to a base colour.
///
/// Shadows lerp toward a deep desaturated blue rather than black. Real shadows
/// pick up ambient skylight, so a cool shadow reads as depth while a black one
/// reads as dirt.
Color applyShading(Color base, double factor) {
  const Color shadowTint = Color(0xFF10141C);
  return Color.lerp(shadowTint, base, factor.clamp(0.0, 1.0))!;
}

// ============================================================
// SURFACE LIGHT
//
// One light for every kind of surface. Level surfaces were lit by a fixed key
// light; height, complex and parametric surfaces by how squarely they faced the
// camera — so a sphere and a paraboloid on the same axes were lit as if in two
// different rooms, and the camera-facing kind lost its shape exactly where it
// faced you.
// ============================================================

/// Which way the key light comes from, in the box's own space before the
/// camera turns it: from over the viewer's left shoulder at the default view.
///
/// Fixed to the box rather than to the camera, so a surface keeps its lighting
/// as it is turned — which is how a held object behaves — and the lit colour
/// can be worked out once with the geometry instead of on every frame.
final ({double x, double y, double z}) keyLight = () {
  const double x = -0.35, y = -0.62, z = 0.70;
  final double len = math.sqrt(x * x + y * y + z * z);
  return (x: x / len, y: y / len, z: z / len);
}();

/// How square a surface with normal (nx, ny, nz) stands to [keyLight], from
/// 0 edge-on to 1 square on.
///
/// Two-sided: marching gives a normal pointing the way f increases, and which
/// side that is depends on whether the equation was written `f = 0` or
/// `-f = 0` — the same sphere either way.
double keyLightOn(double nx, double ny, double nz) {
  final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (len == 0 || !len.isFinite) return 1;
  return ((nx * keyLight.x + ny * keyLight.y + nz * keyLight.z) / len).abs();
}

/// How much of a surface's colour survives in its deepest shade.
const double _shadowKeep = 0.40;

/// The blue a shade picks up instead of falling to black, per channel.
///
/// Real shade is lit by the sky, so it turns cool; shade that only darkens
/// greys every hue towards the same mud, which is what made a lit surface read
/// as flat. Small enough that a dark surface does not visibly brighten.
const double _shadowTintR = 0.04;
const double _shadowTintG = 0.06;
const double _shadowTintB = 0.13;

/// [base] under the key light, with [lambert] from [keyLightOn].
///
/// Square to the light it is exactly [base] — the colour the colorbar and the
/// row's swatch show — and it only ever darkens from there, never brightens,
/// so no colour appears on a surface that is not in its legend. Turned away it
/// falls toward a darker, cooler version of itself rather than towards black.
///
/// [strength] is how far into the shade it may go: 1 for a solid surface,
/// whose colour carries nothing but form, and less for one coloured by value,
/// whose colour has to stay close enough to the colorbar to be read off it.
int litSurfaceArgb(int base, double lambert, {double strength = 1}) {
  final double r = ((base >> 16) & 0xFF) / 255;
  final double g = ((base >> 8) & 0xFF) / 255;
  final double b = (base & 0xFF) / 255;
  final double shade = (1 - lambert.clamp(0.0, 1.0)) * strength;
  int channel(double c, double tint) {
    // Held at or below the colour itself: on a channel that is already near
    // black the tint would otherwise lift it, and the shade would come out
    // brighter than the lit side.
    final double dark = math.min(c, c * _shadowKeep + tint);
    return ((c + (dark - c) * shade).clamp(0.0, 1.0) * 255).round();
  }

  return (base & 0xFF000000) |
      (channel(r, _shadowTintR) << 16) |
      (channel(g, _shadowTintG) << 8) |
      channel(b, _shadowTintB);
}

/// How dark a mesh line is against the surface it lies on, at full weight.
const double meshInkDepth = 0.58;

/// The colour of a mesh line drawn over [surface], which is the surface's own
/// colour where the line lies — already lit.
///
/// A darker shade of the surface rather than black. A black line keeps its
/// value whatever the light does around it, so the grid reads as a wire cage
/// hung in front of the shape; a line that is the surface's own colour, only
/// deeper, takes the same light and the same hue as the surface and reads as
/// drawn on it.
///
/// [weight] fades the line: 1 is full ink, 0 is no line at all.
int meshInkArgb(int surface, double weight) {
  final double k = 1 - meshInkDepth * weight.clamp(0.0, 1.0);
  int channel(int shift) =>
      ((((surface >> shift) & 0xFF) * k).round()).clamp(0, 255);
  return (surface & 0xFF000000) |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}

/// How far the farthest part of a 3D surface is washed towards the ground
/// behind it, the nearest part not at all.
///
/// Distance is what air does to colour, and it is the cue a rotating surface
/// most lacks: without it the far side of a shape is as vivid as the near
/// one, and the eye has nothing but the perspective to sort them by. A third
/// of the way is enough to set the back behind the front without washing out
/// the colours a colorbar has to be read against.
const double depthFog = 0.32;

/// [argb] washed [amount] of the way towards [fog], keeping its alpha.
int fogArgb(int argb, double amount, int fog) {
  if (!(amount > 0)) return argb;
  return fogBlend(argb, amount >= 1 ? 256 : (amount * 256).toInt(), fog);
}

/// [argb] washed [k] / 256 of the way towards [fog], keeping its alpha.
///
/// Integers only, with the weight worked out by the caller: this runs for
/// every vertex of every frame of a rotation, a hundred thousand times or more.
int fogBlend(int argb, int k, int fog) {
  if (k <= 0) return argb;
  final int keep = 256 - k;
  final int r = (((argb >> 16) & 0xFF) * keep + ((fog >> 16) & 0xFF) * k) >> 8;
  final int g = (((argb >> 8) & 0xFF) * keep + ((fog >> 8) & 0xFF) * k) >> 8;
  final int b = ((argb & 0xFF) * keep + (fog & 0xFF) * k) >> 8;
  return (argb & 0xFF000000) | (r << 16) | (g << 8) | b;
}

/// The colour standing for a complex value in a domain-coloured plot.
///
/// Hue carries the argument and lightness carries the modulus, which is the
/// usual reading: a zero is a black point every hue runs into, a pole is a
/// white one, and the order of the colours going round says which way the
/// function turns.
///
/// The hue wheel is used rather than [plotColormap] because phase wraps. A
/// ramp with different colours at its ends would draw a seam along every ray
/// where the argument passes π — a line in the picture that is not in the
/// function.
///
/// The modulus is compressed before it is used. Untouched, a function that
/// reaches a few hundred somewhere is flat white nearly everywhere else; the
/// compression is what lets a pole and a zero show in the same picture.
/// [scale] is the modulus that comes out mid-grey.
Color domainColor(double argument, double modulus, {double scale = 1.0}) {
  if (!argument.isFinite || !modulus.isFinite) {
    return const Color(0x00000000);
  }

  // atan2 gives (-π, π]; the wheel wants [0, 360).
  double hue = argument * 180 / math.pi;
  if (hue < 0) hue += 360;

  // 0 at a zero, 1 at a pole, 0.5 at `scale`. Both ends are approached
  // smoothly, so neither is a hard disc of colour.
  final double turns = math.log(1 + modulus / scale) / math.log(2);
  final double lightness = (turns / (1 + turns)).clamp(0.0, 1.0);

  // Full colour in the middle, giving way to the black and the white that
  // mark the zero and the pole.
  final double vividness = 1 - (2 * lightness - 1).abs();
  return HSLColor.fromAHSL(
    1,
    hue,
    (0.3 + 0.7 * vividness).clamp(0.0, 1.0),
    lightness,
  ).toColor();
}
