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

/// Jet: the classic rainbow ramp, dark blue through cyan, yellow and red.
///
/// Chosen deliberately. Note the trade-off it carries: jet is not perceptually
/// uniform — its lightness rises and falls across the range, so bright bands at
/// cyan and yellow can read as ridges that are not in the data, and it loses
/// separation under the common forms of colour-vision deficiency. On a shaded
/// 3D surface it also competes with the lighting, which encodes form through
/// lightness. [viridisColormap] remains available if that ever matters.
const List<Color> _jet = <Color>[
  Color(0xFF000080),
  Color(0xFF0000FF),
  Color(0xFF00FFFF),
  Color(0xFFFFFF00),
  Color(0xFFFF0000),
  Color(0xFF800000),
];

/// Viridis: perceptually uniform and colour-vision-deficiency safe, monotonic
/// in lightness. Kept as an alternative to [plotColormap].
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

/// The perceptually uniform alternative, should it be wanted again.
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
Color plotColormapBanded(double t, {int bands = plotColorBands}) {
  final double clamped = t.clamp(0.0, 1.0);
  // The top edge belongs to the last band rather than starting a new one.
  final int index = (clamped * bands).floor().clamp(0, bands - 1);
  return plotColormap((index + 0.5) / bands);
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

/// Default magnitude ramp for surfaces, contours and colorbars.
Color plotColormap(double t) => _rampLerp(_jet, t);

/// The stops behind [plotColormap], in order from low to high.
///
/// A colorbar drawn as a gradient over these is continuous, and identical to
/// what [plotColormap] returns because both space the stops evenly. Sampling
/// the ramp into one row of pixels per bar height instead quantises it to as
/// many steps as the bar is tall, which on a high-density screen shows as
/// bands with hard edges.
const List<Color> plotColormapStops = _jet;

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
Color Function(double) surfaceColormap(int index, {required int of}) {
  if (of <= 1) return plotColormap;
  final List<Color> ramp = _surfaceRamps[index % _surfaceRamps.length];
  return (double t) => _rampLerp(ramp, t);
}

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

/// Atmospheric depth cue: wash distant geometry toward the background so far
/// parts of the surface recede. [depth01] is 0 at the nearest quad and 1 at
/// the farthest.
Color applyDepthCue(Color color, double depth01, Color background) {
  const double maxWash = 0.28;
  return Color.lerp(color, background, depth01.clamp(0.0, 1.0) * maxWash)!;
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
