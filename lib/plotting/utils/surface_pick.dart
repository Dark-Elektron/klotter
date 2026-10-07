import 'dart:math';
import 'dart:ui';

import '../painters/plot_3d_painter.dart';
import '../models/view_fit.dart';
import '../../math_engine/math_engine.dart';
import '../models/complex_view.dart';
import '../models/enums.dart';
import '../parsers/plot_expression.dart';
import '../parsers/vector_field_parser.dart';
import 'level_set.dart';
import 'parametric.dart';

/// A point on a surface, in data coordinates, with the line it came from.
///
/// [u] and [v] are the sweep parameters when the point came off a parametric
/// plot, and null otherwise. On a sweep they are the interesting numbers —
/// x, y and z say where the point is, u and v say which part of the sweep put
/// it there — so the readout shows them when they exist.
///
/// [curveIndex] is [vectorCurveIndex] for a point taken from a vector field
/// rather than from one of the cell's scalar lines.
typedef SurfaceHit =
    ({double x, double y, double z, int curveIndex, double? u, double? v});

/// Marks a hit that came from the vector field rather than a scalar line.
const int vectorCurveIndex = -1;

/// The camera a 3D plot is drawn through.
///
/// Holds exactly what [Plot3DPainter] uses to project, so picking can invert
/// the same transform. The constants come from the painter rather than being
/// repeated here — a second copy would drift and put the marker where the
/// surface is not.
class PlotCamera {
  PlotCamera({
    required this.size,
    required this.rotationX,
    required this.rotationZ,
    required this.panX,
    required this.panY,
    required this.rangeX,
    required this.rangeY,
    required this.rangeZ,
    this.bottomInset = 0,
  }) : _extents = Plot3DPainter.viewExtentsFor(size);

  final Size size;
  final double rotationX, rotationZ;
  final double panX, panY;
  final double rangeX, rangeY, rangeZ;

  /// The same lift the painter applies, so picking inverts the projection that
  /// was actually drawn. Miss it and every marker lands half the covered height
  /// away from the surface.
  final double bottomInset;
  final ViewFit _extents;

  double get scaleX => _extents.planar / rangeX;
  double get scaleY => _extents.planar / rangeY;
  double get scaleZ => _extents.vertical / rangeZ;

  /// Data point to screen, matching `Point3D.rotateZ().rotateX().project()`.
  Offset project(double x, double y, double z) {
    final (double vx, double vy, double vz) = _toView(
      x * scaleX,
      y * scaleY,
      z * scaleZ,
    );
    final double f = Plot3DPainter.focalLengthFor(size);
    final double scale = f / (f + vy);
    return Offset(
      size.width / 2 + vx * scale + panX + _extents.offsetX,
      size.height / 2 - vz * scale + panY + _extents.offsetY - bottomInset / 2,
    );
  }

  /// World to view: azimuth first, then elevation — the turntable order the
  /// painter uses everywhere.
  (double, double, double) _toView(double x, double y, double z) {
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double x1 = x * cz - y * sz;
    final double y1 = x * sz + y * cz;
    return (x1, y1 * cx - z * sx, y1 * sx + z * cx);
  }

  /// View back to world, undoing [_toView] in reverse.
  (double, double, double) _toWorld(double x, double y, double z) {
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double y1 = y * cx + z * sx;
    final double z0 = -y * sx + z * cx;
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    return (x * cz + y1 * sz, -x * sz + y1 * cz, z0);
  }

  /// The data point under [screen] at view-space depth [depth].
  ///
  /// A screen point does not name a point in the scene, only a ray through it;
  /// [depth] chooses how far along that ray to look. This is the projection
  /// solved for the world point instead of the screen one.
  (double, double, double) unproject(Offset screen, double depth) {
    final double f = Plot3DPainter.focalLengthFor(size);
    final double inv = (f + depth) / f;
    final double vx =
        (screen.dx - size.width / 2 - panX - _extents.offsetX) * inv;
    final double vz =
        (size.height / 2 +
            panY +
            _extents.offsetY -
            bottomInset / 2 -
            screen.dy) *
        inv;
    final (double wx, double wy, double wz) = _toWorld(vx, depth, vz);
    return (wx / scaleX, wy / scaleY, wz / scaleZ);
  }

  /// Depth range of the drawn box, so a ray is only marched where there is
  /// something to hit.
  (double, double) get depthSpan {
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final double sx in <double>[-1, 1]) {
      for (final double sy in <double>[-1, 1]) {
        for (final double sz in <double>[-1, 1]) {
          final (_, double vy, _) = _toView(
            sx * rangeX * scaleX,
            sy * rangeY * scaleY,
            sz * rangeZ * scaleZ,
          );
          lo = min(lo, vy);
          hi = max(hi, vy);
        }
      }
    }
    return (lo, hi);
  }
}

/// One surface a touch can land on.
///
/// An equation to solve for zero, a height to compare the ray's own z
/// against, or a traced line whose drawn triangles the ray is tested against
/// — exactly one of them.
class _Pickable {
  _Pickable({required this.index, this.levelSet, this.height, this.traced});

  /// Which of the cell's lines this came from, or [vectorCurveIndex].
  final int index;
  final PlotExpression? levelSet;
  final double Function(double x, double y)? height;

  /// A line traced by sweeping θ (see [PlotExpression.sweepsTheta]), or a
  /// sampled polar equation drawn one address at a time (see
  /// [PlotExpression.equationSheets]).
  ///
  /// Not solved for zero along the ray: its equation, sampled, only knows the
  /// points with a radius of zero or more and θ in one turn, so a tap on a
  /// petal drawn by a negative r found nothing there. What is drawn is a set
  /// of triangles, so that is what the ray is tested against.
  final PlotExpression? traced;
}

/// How far along the ray from [from] to [to] it first passes through one of
/// [triangles], as a fraction of the way, or null when it misses them all.
///
/// Möller–Trumbore, in data coordinates: the box is stretched differently on
/// each axis on screen, but that stretch is affine and leaves where a line
/// meets a plane where it was.
double? _firstTriangleHit(
  List<LevelTriangle> triangles,
  (double, double, double) from,
  (double, double, double) to,
) {
  final (double ox, double oy, double oz) = from;
  final double dx = to.$1 - ox, dy = to.$2 - oy, dz = to.$3 - oz;
  double? first;
  for (final LevelTriangle t in triangles) {
    final double e1x = t.b.x - t.a.x, e1y = t.b.y - t.a.y, e1z = t.b.z - t.a.z;
    final double e2x = t.c.x - t.a.x, e2y = t.c.y - t.a.y, e2z = t.c.z - t.a.z;
    final double px = dy * e2z - dz * e2y;
    final double py = dz * e2x - dx * e2z;
    final double pz = dx * e2y - dy * e2x;
    final double det = e1x * px + e1y * py + e1z * pz;
    if (det == 0 || !det.isFinite) continue;
    final double inv = 1 / det;
    final double sx = ox - t.a.x, sy = oy - t.a.y, sz = oz - t.a.z;
    final double u = (sx * px + sy * py + sz * pz) * inv;
    if (u < 0 || u > 1) continue;
    final double qx = sy * e1z - sz * e1y;
    final double qy = sz * e1x - sx * e1z;
    final double qz = sx * e1y - sy * e1x;
    final double v = (dx * qx + dy * qy + dz * qz) * inv;
    if (v < 0 || u + v > 1) continue;
    final double along = (e2x * qx + e2y * qy + e2z * qz) * inv;
    if (along < 0 || along > 1) continue;
    if (first == null || along < first) first = along;
  }
  return first;
}

/// The complex components on show, in the order they are drawn.
List<ComplexPart> complexPartsOf(ComplexView view) => <ComplexPart>[
  if (view.real) ComplexPart.real,
  if (view.imaginary) ComplexPart.imaginary,
  if (view.modulus) ComplexPart.modulus,
];

/// Where a touch first meets a surface.
///
/// A touch in 3D picks out a ray, not a point, so this marches the ray from
/// near to far and returns the first crossing — the point that was visually
/// touched, not one hidden behind it. Null when the ray misses everything,
/// which is a real answer: there is nothing under that part of the plot.
///
/// The root function differs by what the line means. A height `z = f(x, y)` is
/// hit where the ray's own z meets the surface's; an equation `F = 0` is hit
/// where F vanishes. Both are found the same way — walk for a sign change,
/// then bisect — as [levelSetYAt] does for the 2D trace.
///
/// Single-variable lines (`sin(x)`, `sin(z)`) are curves, not surfaces, and a
/// ray does not meaningfully meet one; they are skipped.
SurfaceHit? pickSurface(
  PlotCamera camera,
  List<PlotExpression> curves,
  Offset screen, {
  int samples = 320,
  VectorFieldParser? field,
  SurfaceMode surfaceMode = SurfaceMode.none,
  ComplexView complexView = ComplexView.initial,
}) {
  final (double near, double far) = camera.depthSpan;
  if (!near.isFinite || !far.isFinite || far <= near) return null;

  SurfaceHit? best;
  double bestDepth = double.infinity;

  // Everything the touch could land on, gathered before any marching.
  //
  // A list rather than a widening special case inside the loop: one line can
  // put up to three surfaces on the axes — a complex function shows its real
  // part, its imaginary part and its modulus together — and a vector field
  // contributes one that belongs to no line at all. Deciding what is pickable
  // separately from how it is picked keeps the march to a single shape.
  final List<_Pickable> targets = <_Pickable>[];

  for (int i = 0; i < curves.length; i++) {
    final PlotExpression curve = curves[i];
    if (!curve.isValid) continue;

    if (curve.isComplex) {
      // Only the components on show. A part that is switched off is not drawn,
      // so touching where it would have been must find nothing.
      for (final ComplexPart part in complexPartsOf(complexView)) {
        targets.add(
          _Pickable(
            index: i,
            height: (double x, double y) {
              final Complex w = curve.evaluateComplex(x, y);
              return switch (part) {
                ComplexPart.real => w.real,
                ComplexPart.imaginary => w.imag,
                ComplexPart.modulus => w.magnitude,
              };
            },
          ),
        );
      }
      continue;
    }

    // A traced line, or a sampled polar equation drawn one address at a time:
    // either way what is on screen is a set of triangles, and that is what a
    // tap is tested against. Solving the equation along the ray instead would
    // look for one value standing for every address, which leaps where
    // branches meet.
    if (curve.isLevelSet &&
        (curve.sweepsTheta || curve.equationSheets.isNotEmpty)) {
      targets.add(_Pickable(index: i, traced: curve));
    } else if (curve.isLevelSet) {
      targets.add(_Pickable(index: i, levelSet: curve));
    } else if (curve.isSurface) {
      targets.add(
        _Pickable(
          index: i,
          height: (double x, double y) => curve.evaluate(x, y),
        ),
      );
    }
  }

  // A vector field's magnitude or component surface is a height like any
  // other — z = |F(x, y)| — so it joins the same march. Only when one is
  // actually being drawn: with no mode chosen there is nothing on screen.
  if (field != null &&
      !field.isParametric &&
      !field.is3D &&
      surfaceMode != SurfaceMode.none) {
    targets.add(
      _Pickable(
        index: vectorCurveIndex,
        height: (double x, double y) => field.componentValue(surfaceMode, x, y),
      ),
    );
  }

  for (final _Pickable target in targets) {
    final PlotExpression? traced = target.traced;
    if (traced != null) {
      // The same triangles the painter drew, from the same cache when they
      // are already made.
      final List<LevelTriangle> drawn =
          marchedSurface(
            traced,
            -camera.rangeX,
            camera.rangeX,
            -camera.rangeY,
            camera.rangeY,
            -camera.rangeZ,
            camera.rangeZ,
            resolution: Plot3DPainter.levelResolution,
          ).triangles;
      final double? along = _firstTriangleHit(
        drawn,
        camera.unproject(screen, near),
        camera.unproject(screen, far),
      );
      if (along == null) continue;
      final double hit = near + (far - near) * along;
      if (hit < bestDepth) {
        final (double x, double y, double z) = camera.unproject(screen, hit);
        bestDepth = hit;
        best = (x: x, y: y, z: z, curveIndex: target.index, u: null, v: null);
      }
      continue;
    }

    // Signed distance to the surface along the ray, or NaN where there is
    // nothing to compare against.
    double at(double depth) {
      final (double x, double y, double z) = camera.unproject(screen, depth);
      if (x.abs() > camera.rangeX || y.abs() > camera.rangeY) return double.nan;
      final PlotExpression? levelSet = target.levelSet;
      if (levelSet != null) {
        if (z.abs() > camera.rangeZ) return double.nan;
        return levelSet.evaluate(x, y, z);
      }
      final double surface = target.height!(x, y);
      // Outside the z window the surface is not drawn, so it is not pickable.
      if (!surface.isFinite || surface.abs() > camera.rangeZ) return double.nan;
      return z - surface;
    }

    double previousDepth = near;
    double previous = at(near);

    for (int s = 1; s <= samples; s++) {
      final double depth = near + (far - near) * s / samples;
      final double value = at(depth);

      final bool crossed =
          previous.isFinite &&
          value.isFinite &&
          previous != 0 &&
          previous.isNegative != value.isNegative;

      // A change of sign the value leaps across rather than passes through —
      // a pole, a step, θ coming round, or a sampled polar line switching
      // from one address to another — has no surface in it, and the walk
      // goes on past it (see [crossesZero]).
      if (crossed &&
          !crossesZero(
            (double t) => at(previousDepth + (depth - previousDepth) * t),
            previous,
            value,
          )) {
        previousDepth = depth;
        previous = value;
        continue;
      }

      if (value == 0 || crossed) {
        double hit = depth;
        if (crossed) {
          double lo = previousDepth, hi = depth, atLo = previous;
          for (int step = 0; step < 50; step++) {
            final double mid = (lo + hi) / 2;
            final double atMid = at(mid);
            if (!atMid.isFinite) break;
            if (atMid.isNegative == atLo.isNegative) {
              lo = mid;
              atLo = atMid;
            } else {
              hi = mid;
            }
          }
          hit = (lo + hi) / 2;
        }
        if (hit < bestDepth) {
          final (double x, double y, double z) = camera.unproject(screen, hit);
          bestDepth = hit;
          best = (x: x, y: y, z: z, curveIndex: target.index, u: null, v: null);
        }
        // Nearest crossing on this curve is enough; anything behind it is
        // hidden by the surface just found.
        break;
      }

      previousDepth = depth;
      previous = value;
    }
  }

  return best;
}

/// The point on a parametric plot nearest to [screen].
///
/// A sweep is not a height, so it cannot be found by marching a ray until the
/// value changes sign — there is no `z = f(x, y)` to compare against. What
/// there is, already computed and cached for drawing, is the sampled sweep
/// itself. So the pick projects those samples and takes the nearest, which is
/// both simpler and exactly consistent with what is on screen: the marker can
/// only land somewhere the curve was actually drawn.
///
/// [tolerance] is in pixels — a touch further than this from every sample is a
/// touch on empty space, and returns null rather than snapping to something
/// far away.
SurfaceHit? pickParametric(
  PlotCamera camera,
  VectorFieldParser field,
  Offset screen, {
  required ParameterRange uRange,
  required ParameterRange vRange,
  double tolerance = 44,
}) {
  if (!field.isParametric) return null;

  SurfaceHit? best;
  double bestDistance = tolerance;

  void consider(ParametricPoint? p, double u, double v, bool hasV) {
    if (p == null) return;
    if (!p.x.isFinite || !p.y.isFinite || !p.z.isFinite) return;
    // Off the box is off the plot: those parts are clipped away when drawn.
    if (p.x.abs() > camera.rangeX ||
        p.y.abs() > camera.rangeY ||
        p.z.abs() > camera.rangeZ) {
      return;
    }
    final Offset at = camera.project(p.x, p.y, p.z);
    if (!at.dx.isFinite || !at.dy.isFinite) return;
    final double d = (at - screen).distance;
    if (d >= bestDistance) return;
    bestDistance = d;
    best = (
      x: p.x,
      y: p.y,
      z: p.z,
      curveIndex: vectorCurveIndex,
      u: u,
      v: hasV ? v : null,
    );
  }

  if (field.isParametricSurface) {
    final List<List<ParametricPoint?>> grid = cachedParametricSurface(
      field,
      u: uRange,
      v: vRange,
    );
    for (int i = 0; i < grid.length; i++) {
      final List<ParametricPoint?> row = grid[i];
      final double u =
          uRange.min +
          (uRange.max - uRange.min) *
              (grid.length == 1 ? 0 : i / (grid.length - 1));
      for (int j = 0; j < row.length; j++) {
        final double v =
            vRange.min +
            (vRange.max - vRange.min) *
                (row.length == 1 ? 0 : j / (row.length - 1));
        consider(row[j], u, v, true);
      }
    }
    return best;
  }

  // A curve is refined onto the segment between samples rather than snapped to
  // the nearest one. Snapping put the marker up to half a step away from the
  // finger and made it jump from sample to sample as the finger moved, which
  // reads as the marker not staying on the curve — it was on it, just not
  // where the touch was.
  final List<ParametricPoint?> curve = cachedParametricCurve(field, u: uRange);
  final double span = uRange.max - uRange.min;
  double uAt(int i) =>
      uRange.min + span * (curve.length == 1 ? 0 : i / (curve.length - 1));

  for (int i = 0; i + 1 < curve.length; i++) {
    final ParametricPoint? a = curve[i];
    final ParametricPoint? b = curve[i + 1];
    if (a == null || b == null) continue;
    if (!a.x.isFinite || !b.x.isFinite) continue;

    final Offset pa = camera.project(a.x, a.y, a.z);
    final Offset pb = camera.project(b.x, b.y, b.z);
    if (!pa.dx.isFinite || !pb.dx.isFinite) continue;

    // Where the touch falls along this segment, measured on screen because
    // that is where the finger is.
    final Offset seg = pb - pa;
    final double len2 = seg.dx * seg.dx + seg.dy * seg.dy;
    final double t =
        len2 <= 0
            ? 0.0
            : (((screen - pa).dx * seg.dx + (screen - pa).dy * seg.dy) / len2)
                .clamp(0.0, 1.0);

    final ParametricPoint at = (
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      z: a.z + (b.z - a.z) * t,
    );
    consider(at, uAt(i) + (uAt(i + 1) - uAt(i)) * t, 0, false);
  }
  // A single sample is a curve with no segments, and still worth reporting.
  if (curve.length == 1) consider(curve.first, uAt(0), 0, false);
  return best;
}
