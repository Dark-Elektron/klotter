import 'dart:math';
import 'dart:typed_data';

import '../parsers/plot_expression.dart';
import 'level_set.dart';

/// How far a level set reaches, or null when it is nowhere in the probe window.
typedef LevelExtent = ({double x, double y, double z});

/// Where `F = 0` actually is, found by looking for it.
///
/// A level set cannot be framed the way a height surface is. There is no
/// `z = f(x, y)` to measure, and sizing the box by `max|F|` is far worse than
/// useless: for `x²+y²+z²=1` over ±5 the maximum of |F| is 74, which would ask
/// for a box thirty times bigger than the unit sphere it is meant to frame.
///
/// So this looks for the surface instead of measuring the function. It walks a
/// coarse lattice and keeps every cell where F changes sign between neighbours,
/// because a sign change is exactly where the surface passes. The bounding box
/// of those crossings is the reach.
///
/// [probe] is how far out to look. Anything beyond it is not found — an
/// unbounded surface like `x - y = 0` reports the probe window itself, which is
/// the honest answer: it goes at least this far.
LevelExtent? levelSetExtent(
  PlotExpression equation, {
  double probe = 40,
  int steps = 20,
  int passes = 7,
  bool volume = true,
}) {
  if (!equation.isValid || !equation.isLevelSet) return null;

  // A polar curve is traced, so its reach is read off its path instead of
  // searched for, which would miss the parts with negative r. In the box it
  // is a wall the full height, so it reaches the probe in z.
  if (equation.isPolarCurve) {
    final ({double x, double y})? reach = polarCurveReach(equation, probe);
    if (reach == null) return null;
    return (
      x: min(reach.x * 1.05, probe),
      y: min(reach.y * 1.05, probe),
      z: volume ? probe : 0,
    );
  }
  // A swept spherical surface likewise, from its grid of angles.
  if (equation.isSphericalSurface) {
    final ({double x, double y, double z})? reach = sphericalSurfaceReach(
      equation,
      probe,
    );
    if (reach == null) return null;
    return (
      x: min(reach.x * 1.05, probe),
      y: min(reach.y * 1.05, probe),
      z: volume ? min(reach.z * 1.05, probe) : 0,
    );
  }

  // A surface smaller than a cell of the first lattice can fall between its
  // points and never show a change of sign. x⁴+y⁴+z⁴−2(x²+y²+z²)+8xyz+1 is
  // negative only in four lobes along the diagonals, and a lattice four units
  // apart stepped over every one of them, so that surface was never framed at
  // all. So finding nothing is not the answer until the search has been made
  // again at a few smaller probes, each a quarter of the last, around the
  // origin where a plot's shapes are. An equation that really is nowhere pays
  // one coarse pass per probe for that, which is the price of a single pass
  // at the old cost.
  for (double window = probe; window >= probe / 64; window /= 4) {
    final LevelExtent? found = _extentWithin(
      equation,
      window,
      steps,
      passes,
      volume,
    );
    if (found != null) return found;
  }
  return null;
}

/// How far out to frame an unbounded surface that passes near the origin.
///
/// With nothing bounded there is no size to frame by — a paraboloid is the
/// same shape at every scale — so this is a choice, and the classic window a
/// few units across is the one where the part that matters, its tip or its
/// waist, is large enough to read.
const double unboundedFrame = 2.5;

/// The half-widths to frame [equation] in: its reach along each axis where it
/// is bounded, and something that can be looked at where it is not.
///
/// [levelSetExtent] reports an unbounded surface as reaching the edge of its
/// probe, which is honest — it goes at least that far — but framing that
/// asks for a box sixty units across around two paraboloids touching at the
/// origin, where all there is to see is a speck. So an axis is first tested
/// for being bounded: the reach is measured again in a window four times as
/// wide, and an axis whose reach grows with the window has no end of its own.
///
/// - Bounded everywhere: the reach, as before.
/// - Unbounded along some axes: those take three times the bounded reach — a
///   unit cylinder is framed as a stretch of tube, not as a speck in a
///   column eighty units tall.
/// - Unbounded along every axis — a plane, a cone, a paraboloid, a
///   hyperboloid: framed by where it comes nearest the origin, at twice that
///   distance, so a plane far off is still in the box and a waist is shown
///   whole; and at [unboundedFrame] when it passes through the origin.
LevelExtent? levelSetFraming(PlotExpression equation, {bool volume = true}) {
  const double probe = 40;
  final LevelExtent? near = levelSetExtent(
    equation,
    probe: probe,
    volume: volume,
  );
  if (near == null) return null;
  // Clear of the probe's edge on every axis: whatever is there ends inside
  // it, and there is nothing more to find out. Only a surface that reaches
  // the edge pays for the wider look.
  const double edge = probe * 0.9;
  if (near.x < edge && near.y < edge && (!volume || near.z < edge)) {
    return near;
  }
  final LevelExtent? far = levelSetExtent(equation, probe: 160, volume: volume);
  // A bounded reach comes out the same in the wider window, give or take the
  // last pass's step. One that grows with the window grows by at least the
  // square root of four, as a paraboloid's radius does.
  bool bounded(double here, double? wider) =>
      wider == null || wider <= here * 1.25;
  final bool bx = bounded(near.x, far?.x);
  final bool by = bounded(near.y, far?.y);
  // Not looked for in a plane, so it cannot run off anywhere.
  final bool bz = !volume || bounded(near.z, far?.z);
  if (bx && by && bz) return near;

  if (!bx && !by && !bz) {
    final double? nearest = levelSetNearest(equation, volume: volume);
    final double frame =
        nearest == null ? unboundedFrame : max(unboundedFrame, 2 * nearest);
    return (x: frame, y: frame, z: volume ? frame : near.z);
  }

  final double boundedReach = <double>[
    if (bx) near.x,
    if (by) near.y,
    if (bz) near.z,
  ].reduce(max);
  final double open = max(3 * boundedReach, unboundedFrame);
  return (x: bx ? near.x : open, y: by ? near.y : open, z: bz ? near.z : open);
}

/// How close [equation]'s surface comes to the origin, or null when it is
/// not found at all.
///
/// Measured on a lattice in a window, then again in windows a quarter the
/// size down to half a unit, keeping the nearest crossing any of them finds.
/// A coarse lattice alone is not enough: two paraboloids touching at the
/// origin are thinner than its cells there, so the nearest crossing it sees is
/// far up the cups, and they were framed hundreds of units across. A smaller
/// window can only find crossings nearer in, so the closest of them all is as
/// near as the surface comes, to about a cell of the finest lattice.
double? levelSetNearest(
  PlotExpression equation, {
  double probe = 160,
  int steps = 20,
  bool volume = true,
}) {
  if (!equation.isValid || !equation.isLevelSet) return null;
  double? best;
  for (double window = probe; window >= 0.5; window /= 4) {
    final double? found = _nearestWithin(equation, window, steps, volume);
    if (found != null && (best == null || found < best)) best = found;
  }
  return best;
}

/// The distance from the origin of the nearest lattice edge [equation] crosses
/// within ±[probe], or null when it crosses none.
double? _nearestWithin(
  PlotExpression equation,
  double probe,
  int steps,
  bool volume,
) {
  final double span = probe * 2 / steps;
  final int depth = volume ? steps : 0;
  final int side = steps + 1;
  final int layers = depth + 1;
  final Float64List samples = Float64List(side * side * layers);
  int cell(int i, int j, int k) => (i * side + j) * layers + k;
  double at(int n) => -probe + n * span;
  for (int i = 0; i <= steps; i++) {
    for (int j = 0; j <= steps; j++) {
      for (int k = 0; k <= depth; k++) {
        final double v = equation.evaluate(at(i), at(j), volume ? at(k) : 0);
        samples[cell(i, j, k)] = v.isFinite ? v : double.nan;
      }
    }
  }

  double nearest = double.infinity;
  void edge(double here, double there, double x, double y, double z) {
    if (!_flips(here, there)) return;
    final double d = sqrt(x * x + y * y + z * z);
    if (d < nearest) nearest = d;
  }

  for (int i = 0; i <= steps; i++) {
    for (int j = 0; j <= steps; j++) {
      for (int k = 0; k <= depth; k++) {
        final double here = samples[cell(i, j, k)];
        if (here.isNaN) continue;
        final double x = at(i), y = at(j), z = volume ? at(k) : 0;
        // Each edge measured at its middle.
        if (i < steps) {
          edge(here, samples[cell(i + 1, j, k)], x + span / 2, y, z);
        }
        if (j < steps) {
          edge(here, samples[cell(i, j + 1, k)], x, y + span / 2, z);
        }
        if (volume && k < depth) {
          edge(here, samples[cell(i, j, k + 1)], x, y, z + span / 2);
        }
      }
    }
  }
  return nearest.isFinite ? nearest : null;
}

/// [levelSetExtent] at one probe width.
LevelExtent? _extentWithin(
  PlotExpression equation,
  double probe,
  int steps,
  int passes,
  bool volume,
) {
  // Found by refinement rather than in one sweep. A single lattice fine enough
  // to place a unit circle inside a ±40 probe would be tens of thousands of
  // samples in 2D and millions in 3D; a coarse pass locates the surface, and
  // each pass after it re-searches the box the last one found. Four passes
  // take a 3.3-unit cell down to about 0.05.
  // Per axis, because a surface can be bounded on one and not another: a
  // cylinder `x²+y²=1` runs the whole z window, and refining by the widest
  // axis would let its z reach hold x and y open at the probe width forever.
  double reachX = probe, reachY = probe, reachZ = probe;
  LevelExtent? best;

  for (int pass = 0; pass < passes; pass++) {
    final double spanX = reachX * 2 / steps;
    final double spanY = reachY * 2 / steps;
    final double spanZ = reachZ * 2 / steps;
    double maxX = 0, maxY = 0, maxZ = 0;
    bool found = false;

    // Every lattice point is evaluated once, up front. Each one is compared
    // with up to three neighbours, and evaluating it afresh for every
    // comparison did the same work up to four times over — on the probe that
    // a resize or an edit of a level set waits for.
    final int depth = volume ? steps : 0;
    final int side = steps + 1;
    final int layers = depth + 1;
    final Float64List samples = Float64List(side * side * layers);
    int cell(int i, int j, int k) => (i * side + j) * layers + k;
    for (int i = 0; i <= steps; i++) {
      final double x = -reachX + i * spanX;
      for (int j = 0; j <= steps; j++) {
        final double y = -reachY + j * spanY;
        for (int k = 0; k <= depth; k++) {
          final double z = volume ? -reachZ + k * spanZ : 0;
          final double v = equation.evaluate(x, y, z);
          samples[cell(i, j, k)] = v.isFinite ? v : double.nan;
        }
      }
    }

    for (int i = 0; i <= steps; i++) {
      for (int j = 0; j <= steps; j++) {
        for (int k = 0; k <= depth; k++) {
          final double here = samples[cell(i, j, k)];
          if (here.isNaN) continue;
          // A change of sign between neighbours is where the surface passes.
          final bool crosses =
              (i < steps && _flips(here, samples[cell(i + 1, j, k)])) ||
              (j < steps && _flips(here, samples[cell(i, j + 1, k)])) ||
              (volume && k < depth && _flips(here, samples[cell(i, j, k + 1)]));
          if (!crosses) continue;
          found = true;
          final double x = (-reachX + i * spanX).abs();
          final double y = (-reachY + j * spanY).abs();
          final double z = volume ? (-reachZ + k * spanZ).abs() : 0;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
          if (z > maxZ) maxZ = z;
        }
      }
    }

    if (!found) return best;
    // Padded by each axis's own step, not the widest one. A cylinder is
    // unbounded in z, so its z window never shrinks and its z step stays at
    // the probe's coarsest; adding that to x reported the unit cylinder as
    // reaching 5 in x, which is wider than the box it replaced.
    best = (x: maxX + spanX, y: maxY + spanY, z: maxZ + spanZ);

    // Search again inside what was found, with a little room so a surface
    // sitting just outside the last box is not cropped away by it.
    final double nextX = (maxX + spanX) * 1.3;
    final double nextY = (maxY + spanY) * 1.3;
    final double nextZ = (maxZ + spanZ) * 1.3;
    final bool tighter =
        nextX < reachX || nextY < reachY || (volume && nextZ < reachZ);
    if (!tighter) break; // as tight as this probe allows
    if (nextX < reachX) reachX = nextX;
    if (nextY < reachY) reachY = nextY;
    if (volume && nextZ < reachZ) reachZ = nextZ;
  }
  return best;
}

bool _flips(double a, double b) =>
    b.isFinite && a != 0 && a.isNegative != b.isNegative;
