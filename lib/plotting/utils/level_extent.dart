import '../parsers/plot_expression.dart';

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

    double at(int i, int j, int k) {
      final double x = -reachX + i * spanX;
      final double y = -reachY + j * spanY;
      final double z = volume ? -reachZ + k * spanZ : 0;
      final double v = equation.evaluate(x, y, z);
      return v.isFinite ? v : double.nan;
    }

    final int depth = volume ? steps : 0;
    for (int i = 0; i <= steps; i++) {
      for (int j = 0; j <= steps; j++) {
        for (int k = 0; k <= depth; k++) {
          final double here = at(i, j, k);
          if (here.isNaN) continue;
          // A change of sign between neighbours is where the surface passes.
          final bool crosses =
              (i < steps && _flips(here, at(i + 1, j, k))) ||
              (j < steps && _flips(here, at(i, j + 1, k))) ||
              (volume && k < depth && _flips(here, at(i, j, k + 1)));
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
