import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/plane_slice.dart';
import '../models/point_3d.dart';
import '../parsers/plot_expression.dart';
import 'plot_cache.dart';

/// A straight piece of an implicit curve, in data coordinates.
typedef LevelSegment = ({double x1, double y1, double x2, double y2});

/// A triangle of an implicit surface, in data coordinates.
typedef LevelTriangle = ({Point3D a, Point3D b, Point3D c});

/// A marched surface: its triangles, and the unit surface normal at each of
/// their corners — nine floats a triangle, `(x, y, z)` per vertex, in the same
/// data coordinates as the triangles.
///
/// Packed floats rather than three more [Point3D] on [LevelTriangle]. The
/// marched result is cached, and a hyperboloid marches to 33,000 triangles, so
/// carrying normals as objects would have put another 100,000 of them in the
/// cache per entry; as floats it is 1.2 MB and no allocations at all.
typedef LevelSurface = ({List<LevelTriangle> triangles, Float32List normals});

/// The last few marched results.
///
/// Marching depends only on the expression, the box and the resolution — not
/// on the camera. Rotating or panning a 3D plot repaints continuously without
/// changing any of those, so without a cache every frame re-sampled a 29³
/// lattice and re-tested 130,000 tetrahedra. A handful of entries is enough:
/// a plot has one surface, and the previous box is worth keeping across a
/// zoom step.
///
/// [PlotCache]s, so [releasePlotGeometry] empties them with the rest when the
/// app is backgrounded. They were a cache class of their own once, which the
/// release did not know about — so the marched surfaces, the largest geometry
/// the app holds, were the one thing it kept.
final PlotCache<List<LevelSegment>> _squaresCache =
    PlotCache<List<LevelSegment>>(4);

///
/// Four, so a cell with two equations keeps both a plain and a refined march
/// of each while the refined ones are on their way (see
/// [marchSurfaceInBackground]).
final PlotCache<LevelSurface> _tetsCache = PlotCache<LevelSurface>(4);

/// Where a linear interpolation between two samples crosses zero.
///
/// Placing the crossing by interpolation rather than at the cell edge is what
/// makes a coarse lattice still produce a smooth circle: the grid sets how
/// many segments there are, not how accurate each one is.
double _crossing(double fa, double fb) {
  final double d = fa - fb;
  if (d == 0 || !d.isFinite) return 0.5;
  return (fa / d).clamp(0.0, 1.0);
}

/// How many times a crossing is corrected before it is kept.
///
/// Linear interpolation places a crossing by pretending f runs straight
/// between the two samples, and on anything steep it does not. The error is
/// small measured against the lattice — a twentieth of a cell — which is how
/// it went unnoticed, but a cell is about 22 screen pixels at phone width, so
/// on `x⁴+y⁴+z⁴−x²−y²−z²+0.4` the surface and the grid drawn on it wandered
/// 1.95 px at the median and 6.18 px at the worst, either side of a line 1.8 px
/// wide. That is the jaggedness.
///
/// Two steps of a guarded secant, which keeps the bracket the sign change
/// gives, take that surface to 0.02 px at the median and 0.45 px at its worst
/// — under a pixel everywhere. A third step reaches 0.003 px, which no screen
/// can show.
///
/// It costs two evaluations of the expression per crossing edge. On the march
/// that is +63% for the surface above and +130% for the densest one measured,
/// in the test VM; compiled it is nearer +6% and +40%, since what is added is
/// expression evaluation and what is already there is mostly array work. None
/// of it is paid per frame either way: the march is cached against the window,
/// so it runs when the box changes and not while the plot is being turned.
const int _crossingRefinements = 2;

/// Where f actually crosses zero on the segment from a to b.
///
/// [fa] is negative and [fb] is not, so the root is bracketed to begin with and
/// every step keeps it bracketed: a secant step is taken only when it lands
/// inside the bracket, and bisection is used when it does not. That is what
/// stops a steep or badly behaved f from throwing the crossing off the edge
/// entirely, which plain secant iteration will do.
///
/// Also says whether the steps [settled] on a value next to zero. A jump over
/// zero never does — its values stay the size of the jump — so a settled
/// crossing is a root without asking [crossesZero], which saves the march
/// that check on nearly every edge of a smooth surface.
({double t, bool settled}) _solveCrossing(
  double Function(double x, double y, double z) f,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double fa,
  double fb,
) {
  if (fa == 0) return (t: 0, settled: true);
  if (fb == 0) return (t: 1, settled: true);

  double t = _crossing(fa, fb);
  double lo = 0;
  double hi = 1;
  double atLo = fa;
  double atHi = fb;
  final double near = _settledResidual * max(fa.abs(), fb.abs());
  bool settled = false;

  for (int step = 0; step < _crossingRefinements; step++) {
    final double v = f(
      ax + (bx - ax) * t,
      ay + (by - ay) * t,
      az + (bz - az) * t,
    );
    // Undefined partway along, or already exact: keep the best t so far rather
    // than stepping somewhere arbitrary.
    if (!v.isFinite) return (t: t, settled: false);
    if (v == 0) return (t: t, settled: true);
    settled = v.abs() <= near;

    if (v.isNegative == atLo.isNegative) {
      lo = t;
      atLo = v;
    } else {
      hi = t;
      atHi = v;
    }

    final double spread = atLo - atHi;
    t = spread == 0 ? (lo + hi) / 2 : lo + (hi - lo) * (atLo / spread);
    if (!(t > lo) || !(t < hi)) t = (lo + hi) / 2;
  }
  return (t: t, settled: settled);
}

/// How close to zero, against the larger end of its edge, a refined crossing
/// has to land to count as settled (see [_solveCrossing]).
const double _settledResidual = 1e-3;

/// How many times a change of sign is halved to decide whether it is a root.
const int _rootDepth = 12;

/// How far the halved change of sign has to have shrunk, against the one it
/// started from, to count as a root. Just over a half, so a straight run
/// through zero is accepted at the first halving.
const double _rootShrink = 0.6;

/// Whether the change of sign from [fa] at t = 0 to [fb] at t = 1 is a root of
/// [at], rather than a jump over zero.
///
/// Two samples of opposite sign either straddle a place where f passes
/// through zero, or one where it leaps over it: a pole, a step, or θ coming
/// round from 2π to 0. Marching took every one for a root, so `θ = π/4` drew
/// a second, spurious ray along the positive x axis where θ starts its turn
/// again, `z = θ` stood a wall there, and `r = 1/cos θ` drew the y axis
/// through its pole.
///
/// Told apart the way the curve tracer tells a steep line from an asymptote:
/// the half holding the change of sign is followed, and its rise watched.
/// Through a root the rise shrinks with the interval — halved at the first
/// step if f is straight there — and it is accepted as soon as it has. Across
/// a jump it never drops below the size of the jump, and at a pole it grows,
/// or the halfway value is undefined; after [_rootDepth] halvings without
/// shrinking it is turned down.
///
/// It knows nothing about coordinates: a jump is a jump, whichever system
/// made it. Only edges that already change sign pay for it, mostly one
/// evaluation each.
bool crossesZero(double Function(double t) at, double fa, double fb) {
  if (fa == 0 || fb == 0) return true;
  final double rise = (fb - fa).abs();
  double lo = 0, hi = 1, atLo = fa, atHi = fb;
  for (int level = 0; level < _rootDepth; level++) {
    final double t = (lo + hi) / 2;
    final double v = at(t);
    if (!v.isFinite) return false;
    if (v == 0) return true;
    if (v.isNegative == atLo.isNegative) {
      lo = t;
      atLo = v;
    } else {
      hi = t;
      atHi = v;
    }
    if ((atHi - atLo).abs() <= _rootShrink * rise) return true;
  }
  return false;
}

/// Trace `F(x, y) = 0` across the window with marching squares.
///
/// Returns the segments making up the curve. An equation is a level set, so
/// there is nothing to sample as a height — the curve is where F changes sign,
/// and it may be several disjoint loops, which is why this returns loose
/// segments rather than a path.
/// How finely an implicit curve is sampled while a gesture is in progress.
///
/// Coarse on purpose: a pan changes the window every frame, and the cache is
/// keyed on the window, so every frame pays the full sampling cost. Smooth
/// motion matters more than a smooth curve while the plot is moving, and the
/// fine version arrives the moment the finger lifts.
const int marchingSquaresDraggingResolution = 150;

/// How finely an implicit curve is sampled at rest.
///
/// Chosen against the screen: ~2.7 px per cell on a phone-width plot, finer
/// than the 3 px line drawn through it. It was 220, which is 48,000 samples a
/// frame — and the cache is keyed on the window, so a pan pays that on every
/// frame. Dropping to 150 took an implicit curve from 19.3 ms to 7.6 ms.
const int marchingSquaresDefaultResolution = 260;

/// [slice] says which plane of a 3D plot is being looked at, and [iso] which
/// level of f is being traced — 0 for an equation, and the held value for the
/// contour of a height surface, whose 2D reading at a fixed z is `f(x, y) = z`.
///
/// Both join the cache key. They change what is sampled, so a cached trace of
/// one plane would otherwise be handed back for another and sliding the plane
/// would appear to do nothing.
List<LevelSegment> marchingSquares(
  PlotExpression f,
  double hMin,
  double hMax,
  double vMin,
  double vMax, {
  int resolution = marchingSquaresDefaultResolution,
  PlaneSlice slice = const PlaneSlice(),
  double iso = 0,
}) {
  return _squaresCache.resolve(
    plotCacheKey(f, <double>[
      hMin,
      hMax,
      vMin,
      vMax,
      slice.offset,
      slice.axis.index.toDouble(),
      iso,
    ], resolution),
    () => _marchingSquares(f, hMin, hMax, vMin, vMax, resolution, slice, iso),
  );
}

List<LevelSegment> _marchingSquares(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  int resolution,
  PlaneSlice slice,
  double iso,
) {
  if (!f.isValid || xMax <= xMin || yMax <= yMin) {
    return const <LevelSegment>[];
  }
  // r = f(θ) is traced, not marched: marching finds only the points it can
  // reach with r ≥ 0 and one turn of θ (see [PlotExpression.isPolarCurve]).
  if (f.isPolarCurve && iso == 0) {
    return _polarSegments(f, xMin, xMax, yMin, yMax, resolution, slice);
  }
  // And ρ = f(θ, φ) is cut from its swept surface, for the same reason.
  if (f.isSphericalSurface && iso == 0) {
    return _clipSegments(_sphericalCut(f, slice), xMin, xMax, yMin, yMax);
  }

  // A sampled polar equation is read at several addresses of each point, and
  // each is traced on its own (see [PlotExpression.equationSheets]).
  final List<({int sign, int turn})> sheets =
      iso == 0 ? f.equationSheets : const <({int sign, int turn})>[];
  if (sheets.isNotEmpty) {
    int side(double h, double v) {
      final (double x, double y, _) = _pointOn(slice, h, v);
      return _sideOfCut(x, y);
    }

    return <LevelSegment>[
      for (final ({int sign, int turn}) sheet in sheets)
        ..._marchLattice(
          (double h, double v) {
            final (double x, double y, double z) = _pointOn(slice, h, v);
            return f.evaluateOnSheet(sheet, x, y, z);
          },
          xMin,
          xMax,
          yMin,
          yMax,
          resolution,
          across: (double h, double v) {
            final (double x, double y, double z) = _pointOn(slice, h, v);
            return f.evaluateOnSheet(sheet, x, y, z, continued: true);
          },
          side: side,
        ),
    ];
  }
  return _marchLattice(
    (double h, double v) => slice.sample(f, h, v) - iso,
    xMin,
    xMax,
    yMin,
    yMax,
    resolution,
  );
}

/// The point of space at (h, v) on the plane [slice] holds.
(double, double, double) _pointOn(PlaneSlice slice, double h, double v) =>
    switch (slice.axis) {
      SliceAxis.x => (slice.offset, h, v),
      SliceAxis.y => (h, slice.offset, v),
      SliceAxis.z => (h, v, slice.offset),
    };

/// Which side of the cut a point is on: the half-plane y = 0, x > 0, where θ
/// comes round from 2π to 0. 1 where θ starts its turn (y ≥ 0), −1 where it
/// finishes it (y < 0), and 0 away from it (x ≤ 0), where θ runs on smoothly.
int _sideOfCut(double x, double y) => x > 0 ? (y >= 0 ? 1 : -1) : 0;

/// Marching squares over the window, on the values [at] gives.
///
/// [across] and [side] are for a line read one address at a time (see
/// [PlotExpression.evaluateOnSheet]): a cell with corners on both sides of the
/// cut reads the ones on the side where θ starts its turn with [across], so
/// the address runs on through it instead of leaping.
List<LevelSegment> _marchLattice(
  double Function(double h, double v) at,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  int resolution, {
  double Function(double h, double v)? across,
  int Function(double h, double v)? side,
}) {
  final double dx = (xMax - xMin) / resolution;
  final double dy = (yMax - yMin) / resolution;

  // Sample the corner lattice once; every cell reuses its neighbours' corners.
  final List<List<double>> lattice = <List<double>>[
    for (int i = 0; i <= resolution; i++)
      <double>[
        for (int j = 0; j <= resolution; j++) at(xMin + i * dx, yMin + j * dy),
      ],
  ];

  final List<LevelSegment> out = <LevelSegment>[];

  for (int i = 0; i < resolution; i++) {
    for (int j = 0; j < resolution; j++) {
      double f00 = lattice[i][j];
      double f10 = lattice[i + 1][j];
      double f11 = lattice[i + 1][j + 1];
      double f01 = lattice[i][j + 1];

      final double x0 = xMin + i * dx;
      final double x1 = xMin + (i + 1) * dx;
      final double y0 = yMin + j * dy;
      final double y1 = yMin + (j + 1) * dy;

      double Function(double h, double v) cellAt = at;
      if (across != null && side != null) {
        final int s00 = side(x0, y0);
        final int s10 = side(x1, y0);
        final int s11 = side(x1, y1);
        final int s01 = side(x0, y1);
        final bool straddles =
            (s00 == -1 || s10 == -1 || s11 == -1 || s01 == -1) &&
            (s00 == 1 || s10 == 1 || s11 == 1 || s01 == 1);
        if (straddles) {
          if (s00 == 1) f00 = across(x0, y0);
          if (s10 == 1) f10 = across(x1, y0);
          if (s11 == 1) f11 = across(x1, y1);
          if (s01 == 1) f01 = across(x0, y1);
          cellAt =
              (double h, double v) => side(h, v) == 1 ? across(h, v) : at(h, v);
        }
      }
      if (!f00.isFinite || !f10.isFinite || !f11.isFinite || !f01.isFinite) {
        continue;
      }

      // Crossings on each edge, walked in order so consecutive hits pair up.
      final List<({double x, double y})> hits = <({double x, double y})>[];
      void edge(
        double fa,
        double fb,
        double ax,
        double ay,
        double bx,
        double by,
      ) {
        if ((fa < 0) == (fb < 0)) return;
        final bool root = crossesZero(
          (double t) => cellAt(ax + (bx - ax) * t, ay + (by - ay) * t),
          fa,
          fb,
        );
        if (!root) return;
        final double t = _crossing(fa, fb);
        hits.add((x: ax + (bx - ax) * t, y: ay + (by - ay) * t));
      }

      edge(f00, f10, x0, y0, x1, y0); // bottom
      edge(f10, f11, x1, y0, x1, y1); // right
      edge(f11, f01, x1, y1, x0, y1); // top
      edge(f01, f00, x0, y1, x0, y0); // left

      // Two crossings is one segment. Four is a saddle, where the cell is
      // genuinely ambiguous — either pairing is a valid curve, so pair them
      // in walk order rather than pretending one reading is correct. An odd
      // count means an edge was a jump, not a root: where a curve ends on
      // one, as the edge of r < θ does where θ's turn runs out, the last cell
      // is left open rather than joined across the jump.
      for (int k = 0; k + 1 < hits.length; k += 2) {
        out.add((
          x1: hits[k].x,
          y1: hits[k].y,
          x2: hits[k + 1].x,
          y2: hits[k + 1].y,
        ));
      }
    }
  }

  return out;
}

/// Trace `F(x, y, z) = 0` through the box with marching tetrahedra.
///
/// Tetrahedra rather than marching cubes: a cube has 256 sign cases needing a
/// lookup table, while a tetrahedron has only three distinct outcomes — no
/// crossing, one corner cut off, or a corner pair split — which can be handled
/// by partitioning its vertices. Fewer cases means no table to get wrong, at
/// the cost of more triangles for the same lattice.
List<LevelTriangle> marchingTetrahedra(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax, {
  int resolution = 40,
  bool refine = true,
}) =>
    marchedSurface(
      f,
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
      resolution: resolution,
      refine: refine,
    ).triangles;

/// The same march, with the surface normal at every vertex.
///
/// Separate from [marchingTetrahedra] only so that callers with no use for
/// normals keep reading as they did; both go through one cache, so asking for
/// the normals never marches anything twice.
///
/// [refine] looks into the cells the lattice cannot see through — see
/// [_refineLevels]. It is the surface as drawn at rest; without it is the
/// cheaper march a pinch can afford on every frame.
///
/// [exact] places each crossing by solving for it (see
/// [_crossingRefinements]) rather than by straight interpolation. Off only
/// for a stand-in drawn for a moment, where it is more than half the cost.
LevelSurface marchedSurface(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax, {
  int resolution = 40,
  bool refine = true,
  bool exact = true,
}) {
  return _tetsCache.resolve(
    _marchKey(
      f,
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
      resolution,
      refine,
      exact: exact,
    ),
    () => _marchingTetrahedra(
      f,
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
      resolution,
      refine: refine,
      exact: exact,
    ),
  );
}

Object _marchKey(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
  bool refine, {
  bool exact = true,
}) => plotCacheKey(f, <double>[
  xMin,
  xMax,
  yMin,
  yMax,
  zMin,
  zMax,
], resolution * 4 + (refine ? 1 : 0) + (exact ? 0 : 2));

/// Whether [marchedSurface] would hand this march back without making it.
bool hasMarchedSurface(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax, {
  int resolution = 40,
  bool refine = true,
}) => _tetsCache.contains(
  _marchKey(f, xMin, xMax, yMin, yMax, zMin, zMax, resolution, refine),
);

/// Where refined marches are made off the UI thread, and the signal that one
/// has landed.
///
/// They are where the time goes. On a Galaxy A54 arriving at the touching
/// paraboloids froze the screen for over a second while the cells round the
/// tips were refined, and a swipe that stalls like that reads as the app
/// hanging. Made in the background, a coarse stand-in is drawn at once and
/// the refined surface replaces it a moment later.
///
/// An object handed to whatever draws (the 3D painter's `marches`) rather
/// than a flag and a notifier at the top level, which tests had to switch on
/// and remember to switch off again; a test makes its own instead.
class BackgroundMarches {
  BackgroundMarches({bool? enabled})
    : _enabled = enabled ?? !Platform.environment.containsKey('FLUTTER_TEST');

  /// The app's. Off under `flutter test`, where every paint is checked as soon
  /// as it is made.
  static final BackgroundMarches shared = BackgroundMarches();

  bool _enabled;

  /// Whether refined marches are made in the background. Off for good once an
  /// isolate cannot be started, after which they are made in place.
  bool get enabled => _enabled;

  /// Ticks each time a march lands, so whatever draws level surfaces can draw
  /// again with it.
  final ValueNotifier<int> landed = ValueNotifier<int>(0);

  /// Marches on their way, so each is asked for only once.
  final Set<Object> _marching = <Object>{};

  /// Make [marchedSurface]'s march in a background isolate and keep it, unless
  /// it is already kept or on its way. [landed] ticks when it arrives.
  void march(
    PlotExpression f,
    double xMin,
    double xMax,
    double yMin,
    double yMax,
    double zMin,
    double zMax, {
    int resolution = 40,
    bool refine = true,
  }) {
    final Object key = _marchKey(
      f,
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
      resolution,
      refine,
    );
    if (_tetsCache.contains(key) || !_marching.add(key)) return;
    _marchInIsolate(
      f,
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
      resolution,
      refine,
    ).then(
      (LevelSurface surface) {
        _marching.remove(key);
        _tetsCache.put(key, surface);
        landed.value++;
      },
      onError: (Object error) {
        // Nothing to be done from here but stop trying: the next paint marches
        // it the ordinary way.
        _marching.remove(key);
        _enabled = false;
        landed.value++;
      },
    );
  }
}

/// The march itself, in an isolate of its own.
///
/// Top-level so the closure sent to the isolate holds only what it is given.
/// Made inside [BackgroundMarches.march] it could capture the instance, and
/// with it everything listening to [BackgroundMarches.landed], which is not
/// for sending.
Future<LevelSurface> _marchInIsolate(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
  bool refine,
) => Isolate.run(
  () => _marchingTetrahedra(
    f,
    xMin,
    xMax,
    yMin,
    yMax,
    zMin,
    zMax,
    resolution,
    refine: refine,
  ),
);

/// One component of the gradient, from a sample and its neighbours on that
/// axis.
///
/// Central where there is a sample either side, one-sided at the faces of the
/// lattice and wherever a neighbour came back undefined — which happens all
/// round a singularity, exactly where a surface most needs a normal it can
/// still use. Flat is the last resort.
double _slope(double before, double here, double after, double step) {
  final bool haveBefore = before.isFinite;
  final bool haveAfter = after.isFinite;
  if (haveBefore && haveAfter) return (after - before) / (2 * step);
  if (!here.isFinite) return 0;
  if (haveAfter) return (after - here) / step;
  if (haveBefore) return (here - before) / step;
  return 0;
}

/// How many times a cell the lattice cannot see into is cut finer.
///
/// A lattice finds a surface only where F changes sign between two of its
/// points. Where two sheets of a surface come closer together than a cell —
/// (x²+z²−y)(x²+z²−2y) = 0 is two paraboloids touching at their tips, a
/// distance r²/2 apart at radius r — both ends of a lattice edge are on the
/// same side and the sign change between them is never seen. Neither sheet is
/// drawn there, which is the ragged hole at the tips with the background
/// showing through, and the slivers around its rim are the march giving out.
///
/// A finer lattice everywhere barely helps: the hole's radius goes as the
/// square root of the cell, so halving it costs eight times the march for a
/// hole only a third smaller. Instead the cells where a sign change has been
/// missed are found and marched again on a finer lattice of their own, and
/// the cells within those again, which costs in proportion to how much of the
/// box is that thin rather than to the box.
///
/// Not only the cells that see nothing. Just outside those, the lens between
/// the two sheets still runs through cells whose corners do change sign, and
/// the plain march joins the two sheets there into one wandering surface — the
/// ragged spikes round the rim of the hole. So any cell a hidden crossing
/// passes through is refined. On the paraboloids that costs a third more than
/// refining the blind cells alone; on a shape with nothing thin, nothing.
const int _refineLevels = 2;

/// How many pieces a refined cell is cut into along each axis, at each level.
const int _refineSplit = 4;

/// The most cells refined at the first level.
///
/// An expression thin almost everywhere — a dense oscillation, say — would
/// otherwise refine most of the box and cost many times the march it was
/// meant to improve. Past this, nothing is refined and the surface is the
/// plain march, which is what it was before refinement existed.
const int _refineCellLimit = 1500;

/// One level of the sampling lattice: the march's own, or a finer one laid
/// over it where a cell had to be looked into.
///
/// A finer level samples lazily and only where asked, and reads whatever
/// coincides with a point of the level above from that level, so no point of
/// space is evaluated twice.
class _Lattice {
  _Lattice.coarsest(
    this.f,
    this.x0,
    this.y0,
    this.z0,
    this.hx,
    this.hy,
    this.hz,
    this.n,
    Float64List samples,
  ) : _above = null,
      _ratio = 1,
      _samples = samples,
      _memo = null;

  _Lattice.finer(_Lattice coarse, int split)
    : f = coarse.f,
      x0 = coarse.x0,
      y0 = coarse.y0,
      z0 = coarse.z0,
      hx = coarse.hx / split,
      hy = coarse.hy / split,
      hz = coarse.hz / split,
      n = (coarse.n - 1) * split + 1,
      _above = coarse,
      _ratio = split,
      _samples = null,
      _memo = <int, double>{};

  /// The value being marched, at a point of the box.
  final double Function(double x, double y, double z) f;
  final double x0, y0, z0;
  final double hx, hy, hz;

  /// Points along each axis.
  final int n;

  final _Lattice? _above;
  final int _ratio;
  final Float64List? _samples;
  final Map<int, double>? _memo;

  /// A finer lattice under this one, made the first time it is wanted.
  _Lattice? _below;
  _Lattice get finer => _below ??= _Lattice.finer(this, _refineSplit);

  double value(int i, int j, int k) {
    if (i < 0 || j < 0 || k < 0 || i >= n || j >= n || k >= n) {
      return double.nan;
    }
    final Float64List? samples = _samples;
    if (samples != null) return samples[(i * n + j) * n + k];
    if (i % _ratio == 0 && j % _ratio == 0 && k % _ratio == 0) {
      return _above!.value(i ~/ _ratio, j ~/ _ratio, k ~/ _ratio);
    }
    return _memo![(i * n + j) * n + k] ??= f(
      x0 + i * hx,
      y0 + j * hy,
      z0 + k * hz,
    );
  }

  Point3D point(int i, int j, int k) =>
      Point3D(x0 + i * hx, y0 + j * hy, z0 + k * hz);

  /// The slope of f along [axis] at a point, from its neighbours.
  double slope(int i, int j, int k, int axis) {
    final double here = value(i, j, k);
    switch (axis) {
      case 0:
        return _slope(value(i - 1, j, k), here, value(i + 1, j, k), hx);
      case 1:
        return _slope(value(i, j - 1, k), here, value(i, j + 1, k), hy);
      default:
        return _slope(value(i, j, k - 1), here, value(i, j, k + 1), hz);
    }
  }

  // The surface normal is the gradient of f, and the lattice hands it over
  // for nothing — a difference of neighbouring samples, no further calls into
  // the expression.
  //
  // Worth the trouble over the obvious alternative of one normal per triangle,
  // taken from its own corners. Marching tetrahedra makes slivers — around a
  // tenth of the triangles come out under a hundredth of a cell in area — and
  // a sliver's cross product is mostly rounding error. Measured against the
  // true normal, a face normal is 4 to 8 degrees out at the median but 30 to
  // 90 degrees out at the 99th percentile, which on a 38,000 triangle surface
  // is a few hundred triangles lit at random: precisely the speckle that
  // shading is meant to clear up. From the lattice the error has no tail at
  // all — 0 to 3 degrees median, and never worse than 11.
  void gradient(int i, int j, int k, Float64List into) {
    into[0] = slope(i, j, k, 0);
    into[1] = slope(i, j, k, 1);
    into[2] = slope(i, j, k, 2);
  }

  /// Whether F crosses zero twice along the edge from (i, j, k) one step
  /// along [axis] — in and straight back out, unseen by the two ends.
  ///
  /// The ends agree in sign, so the lattice sees nothing; but if the slope
  /// leaves one end heading towards zero and arrives at the other coming back
  /// from it, the cubic through both values and both slopes says how deep the
  /// dip between them goes. Below zero is a thin sheet, or two sheets, that
  /// the edge stepped across. On the paraboloids above, F is a quadratic along
  /// y and the cubic is exact.
  bool dipsThrough(int i, int j, int k, int axis) {
    final int bi = axis == 0 ? i + 1 : i;
    final int bj = axis == 1 ? j + 1 : j;
    final int bk = axis == 2 ? k + 1 : k;
    double a = value(i, j, k);
    double b = value(bi, bj, bk);
    if (!a.isFinite || !b.isFinite || a == 0 || b == 0) return false;
    if ((a < 0) != (b < 0)) return false; // a crossing the lattice sees
    final double step = axis == 0 ? hx : (axis == 1 ? hy : hz);
    double da = slope(i, j, k, axis) * step;
    double db = slope(bi, bj, bk, axis) * step;
    if (!da.isFinite || !db.isFinite) return false;
    if (a < 0) {
      a = -a;
      b = -b;
      da = -da;
      db = -db;
    }
    // Falling away from one end and rising into the other, or no dip at all.
    if (da >= 0 || db <= 0) return false;

    // The cubic Hermite through (0, a, da) and (1, b, db), and where its slope
    // is zero: H'(t) = p t² + q t + r.
    double at(double t) {
      final double t2 = t * t, t3 = t2 * t;
      return (2 * t3 - 3 * t2 + 1) * a +
          (t3 - 2 * t2 + t) * da +
          (-2 * t3 + 3 * t2) * b +
          (t3 - t2) * db;
    }

    final double p = 6 * a + 3 * da - 6 * b + 3 * db;
    final double q = -6 * a - 4 * da + 6 * b - 2 * db;
    final double r = da;
    double deepest = double.infinity;
    double deepestAt = -1;
    void consider(double t) {
      if (t <= 0 || t >= 1) return;
      final double h = at(t);
      if (h < deepest) {
        deepest = h;
        deepestAt = t;
      }
    }

    if (p.abs() <= 1e-12 * (q.abs() + r.abs())) {
      if (q != 0) consider(-r / q);
    } else {
      final double disc = q * q - 4 * p * r;
      if (disc < 0) return false;
      final double s = sqrt(disc);
      consider((-q - s) / (2 * p));
      consider((-q + s) / (2 * p));
    }
    if (!(deepest < 0)) return false;

    // Confirmed with the expression itself, at the bottom of the dip. The
    // cubic is a guess wherever F is not a low polynomial along the edge, and
    // near a saddle that only comes close to zero it overshoots: four legs
    // that stop just short of a body (F peaks at +0.019 between them) read as
    // thin there and had half the box refined for nothing, at two and a half
    // times the march. One evaluation per suspect edge settles it.
    final Point3D from = point(i, j, k);
    final double probe = f(
      from.x + (axis == 0 ? hx * deepestAt : 0),
      from.y + (axis == 1 ? hy * deepestAt : 0),
      from.z + (axis == 2 ? hz * deepestAt : 0),
    );
    return probe.isFinite && (probe < 0) != (value(i, j, k) < 0);
  }

  /// Whether any of the twelve edges of the cube at (i, j, k) dips through.
  bool thinCube(int i, int j, int k) {
    for (int a = 0; a <= 1; a++) {
      for (int b = 0; b <= 1; b++) {
        if (dipsThrough(i, j + a, k + b, 0) ||
            dipsThrough(i + a, j, k + b, 1) ||
            dipsThrough(i + a, j + b, k, 2)) {
          return true;
        }
      }
    }
    return false;
  }
}

LevelSurface _marchingTetrahedra(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution, {
  bool refine = true,
  bool exact = true,
}) {
  if (!f.isValid ||
      xMax <= xMin ||
      yMax <= yMin ||
      zMax <= zMin ||
      resolution < 1) {
    return (triangles: const <LevelTriangle>[], normals: Float32List(0));
  }
  // A curve in the plane is, in the box, the wall standing on it, as
  // x² + y² = 1 is a cylinder. A polar curve's wall is built from its traced
  // path for the same reason its curve is (see [_marchingSquares]).
  if (f.isPolarCurve) {
    return _polarWall(f, xMin, xMax, yMin, yMax, zMin, zMax, resolution);
  }
  if (f.isSphericalSurface) {
    return _sphericalSurface(f, xMin, xMax, yMin, yMax, zMin, zMax, resolution);
  }

  // A sampled polar equation is read at several addresses of each point (see
  // [PlotExpression.equationSheets]). Marched as one value — whichever
  // address is nearest zero — it switches from one branch to another in a
  // leap wherever two meet, and the march turns the leaps down:
  // r² = sin(3θ)/(3θ) stood with a slit everywhere its branches meet, a third
  // of its wall missing. One address at a time, as the flat view is traced,
  // each branch is whole.
  final List<({int sign, int turn})> sheets = f.equationSheets;
  if (sheets.isNotEmpty) {
    // No z in it: the wall on its curve, from the curve the flat view traces.
    if (!f.isImplicitSurface) {
      return _wallOnCurve(f, xMin, xMax, yMin, yMax, zMin, zMax, resolution);
    }
    final List<LevelTriangle> triangles = <LevelTriangle>[];
    final List<double> normals = <double>[];
    for (final ({int sign, int turn}) sheet in sheets) {
      final LevelSurface part = _marchField(
        (double x, double y, double z) => f.evaluateOnSheet(sheet, x, y, z),
        xMin,
        xMax,
        yMin,
        yMax,
        zMin,
        zMax,
        resolution,
        refine: refine,
        exact: exact,
        across:
            (double x, double y, double z) =>
                f.evaluateOnSheet(sheet, x, y, z, continued: true),
      );
      triangles.addAll(part.triangles);
      normals.addAll(part.normals);
    }
    return (triangles: triangles, normals: Float32List.fromList(normals));
  }

  return _marchField(
    f.evaluate,
    xMin,
    xMax,
    yMin,
    yMax,
    zMin,
    zMax,
    resolution,
    refine: refine,
    exact: exact,
    relation: f.relation,
  );
}

/// Marching tetrahedra through the box, on the values [f] gives.
///
/// [relation] says whether this is a solid to be closed where the box cuts it
/// (see [_addWallCaps]). [across] is for a line read one address at a time
/// (see [PlotExpression.evaluateOnSheet]): a cube with corners on both sides
/// of the cut — the half-plane y = 0, x > 0, where θ comes round from 2π to
/// 0 — reads the corners on the side where θ starts its turn with [across],
/// so the address runs on through it instead of leaping.
LevelSurface _marchField(
  double Function(double x, double y, double z) f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution, {
  required bool refine,
  required bool exact,
  PlotRelation relation = PlotRelation.equal,
  double Function(double x, double y, double z)? across,
}) {
  final double dx = (xMax - xMin) / resolution;
  final double dy = (yMax - yMin) / resolution;
  final double dz = (zMax - zMin) / resolution;

  // One sample per lattice point, shared by the eight cubes that touch it.
  final int n = resolution + 1;
  final Float64List samples = Float64List(n * n * n);
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      for (int k = 0; k < n; k++) {
        samples[(i * n + j) * n + k] = f(
          xMin + i * dx,
          yMin + j * dy,
          zMin + k * dz,
        );
      }
    }
  }
  final _Lattice lattice = _Lattice.coarsest(
    f,
    xMin,
    yMin,
    zMin,
    dx,
    dy,
    dz,
    n,
    samples,
  );

  final List<LevelTriangle> out = <LevelTriangle>[];
  final List<double> normals = <double>[];

  final Float64List gradA = Float64List(3);
  final Float64List gradB = Float64List(3);

  // Cube split into six tetrahedra sharing the 0-6 body diagonal. Sharing one
  // diagonal across every cube keeps neighbouring cells consistent, so the
  // surface comes out watertight instead of cracked along cell boundaries.
  const List<List<int>> tets = <List<int>>[
    <int>[0, 5, 1, 6],
    <int>[0, 1, 2, 6],
    <int>[0, 2, 3, 6],
    <int>[0, 3, 7, 6],
    <int>[0, 7, 4, 6],
    <int>[0, 4, 5, 6],
  ];
  const List<List<int>> cubeOffsets = <List<int>>[
    <int>[0, 0, 0],
    <int>[1, 0, 0],
    <int>[1, 1, 0],
    <int>[0, 1, 0],
    <int>[0, 0, 1],
    <int>[1, 0, 1],
    <int>[1, 1, 1],
    <int>[0, 1, 1],
  ];

  // The cube being marched: its lattice, where it sits on it, and its corners.
  // Corners are named by their index into [cubeOffsets] so that the lattice
  // position — and so the gradient — can be recovered from them; carrying
  // `Point3D`s alone lost that.
  late _Lattice on;
  late int cubeI, cubeJ, cubeK;

  // Whether the cube being marched lies across the cut, so its far corners
  // were read with [across]; and whether it is near enough the cut that the
  // lattice's own differences, taken across it, cannot be trusted for a
  // normal.
  bool straddling = false;
  bool nearCut = false;

  // The value inside a cube across the cut, continued on the far side.
  double acrossCut(double x, double y, double z) =>
      _sideOfCut(x, y) > 0 ? across!(x, y, z) : f(x, y, z);
  final List<Point3D?> p = List<Point3D?>.filled(8, null);
  final Float64List fv = Float64List(8);

  // The crossings already found in the cube being marched, by the pair of
  // corners they lie between. Its six tetrahedra share edges — nineteen
  // edges serve thirty-six uses — and each crossing costs evaluations of f,
  // so each is found once per cube rather than once per tetrahedron.
  final List<({Point3D at, double nx, double ny, double nz, bool root})?>
  found =
      List<({Point3D at, double nx, double ny, double nz, bool root})?>.filled(
        64,
        null,
      );

  // A crossing: where the surface cuts the edge between two cube corners, and
  // the normal there.
  ({Point3D at, double nx, double ny, double nz, bool root}) solveEdge(
    int c1,
    int c2,
  ) {
    final double fa = fv[c1];
    final double fb = fv[c2];
    final Point3D a = p[c1]!;
    final Point3D b = p[c2]!;
    final double Function(double x, double y, double z) value =
        straddling ? acrossCut : f;
    final ({double t, bool settled}) solved =
        exact
            ? _solveCrossing(value, a.x, a.y, a.z, b.x, b.y, b.z, fa, fb)
            : (t: _crossing(fa, fb), settled: false);
    final double t = solved.t;
    // A change of sign that is a jump rather than a root (see [crossesZero]).
    final bool root =
        solved.settled ||
        crossesZero(
          (double s) => value(
            a.x + (b.x - a.x) * s,
            a.y + (b.y - a.y) * s,
            a.z + (b.z - a.z) * s,
          ),
          fa,
          fb,
        );

    if (nearCut) {
      // The lattice differences here reach across the cut, where one address
      // leaps; a zero normal hands the triangle its own plane instead (see
      // [emit]).
      gradA.fillRange(0, 3, 0);
      gradB.fillRange(0, 3, 0);
    } else {
      final List<int> o1 = cubeOffsets[c1];
      final List<int> o2 = cubeOffsets[c2];
      on.gradient(cubeI + o1[0], cubeJ + o1[1], cubeK + o1[2], gradA);
      on.gradient(cubeI + o2[0], cubeJ + o2[1], cubeK + o2[2], gradB);
    }

    return (
      at: Point3D(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      ),
      // The gradient is interpolated along the edge just as the position is,
      // so two triangles meeting on that edge agree about which way the
      // surface faces there and the shading runs smoothly across the join.
      nx: gradA[0] + (gradB[0] - gradA[0]) * t,
      ny: gradA[1] + (gradB[1] - gradA[1]) * t,
      nz: gradA[2] + (gradB[2] - gradA[2]) * t,
      root: root,
    );
  }

  ({Point3D at, double nx, double ny, double nz, bool root}) crossing(
    int c1,
    int c2,
  ) => found[c1 < c2 ? c1 * 8 + c2 : c2 * 8 + c1] ??= solveEdge(c1, c2);

  /// Keep a triangle and its three normals, each scaled to unit length.
  void emit(
    ({Point3D at, double nx, double ny, double nz, bool root}) a,
    ({Point3D at, double nx, double ny, double nz, bool root}) b,
    ({Point3D at, double nx, double ny, double nz, bool root}) c,
  ) {
    out.add((a: a.at, b: b.at, c: c.at));

    // Somewhere flat, or where a singularity left nothing to difference, the
    // gradient is no use. The triangle's own plane is the fallback, and a
    // triangle with no plane either is lit as though it faced straight up —
    // it has no area, so nothing is drawn for it anyway.
    double faceX = 0, faceY = 0, faceZ = 0;
    bool faceKnown = false;
    void takeFace() {
      if (faceKnown) return;
      faceKnown = true;
      final double ux = b.at.x - a.at.x;
      final double uy = b.at.y - a.at.y;
      final double uz = b.at.z - a.at.z;
      final double vx = c.at.x - a.at.x;
      final double vy = c.at.y - a.at.y;
      final double vz = c.at.z - a.at.z;
      faceX = uy * vz - uz * vy;
      faceY = uz * vx - ux * vz;
      faceZ = ux * vy - uy * vx;
      final double len = sqrt(faceX * faceX + faceY * faceY + faceZ * faceZ);
      if (len == 0 || !len.isFinite) {
        faceX = 0;
        faceY = 0;
        faceZ = 1;
      } else {
        faceX /= len;
        faceY /= len;
        faceZ /= len;
      }
    }

    for (final ({Point3D at, double nx, double ny, double nz, bool root}) v
        in <({Point3D at, double nx, double ny, double nz, bool root})>[
          a,
          b,
          c,
        ]) {
      final double len = sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz);
      if (len > 0 && len.isFinite) {
        normals.add(v.nx / len);
        normals.add(v.ny / len);
        normals.add(v.nz / len);
      } else {
        takeFace();
        normals.add(faceX);
        normals.add(faceY);
        normals.add(faceZ);
      }
    }
  }

  void marchCube(_Lattice lattice, int i, int j, int k) {
    for (int c = 0; c < 8; c++) {
      final List<int> o = cubeOffsets[c];
      fv[c] = lattice.value(i + o[0], j + o[1], k + o[2]);
      p[c] = lattice.point(i + o[0], j + o[1], k + o[2]);
    }
    straddling = false;
    nearCut = false;
    final double Function(double x, double y, double z)? continued = across;
    if (continued != null) {
      bool below = false, above = false;
      for (int c = 0; c < 8; c++) {
        final Point3D q = p[c]!;
        final int side = _sideOfCut(q.x, q.y);
        if (side < 0) below = true;
        if (side > 0) above = true;
        if (q.x > -lattice.hx && q.y.abs() <= lattice.hy * 1.0001) {
          nearCut = true;
        }
      }
      if (below && above) {
        straddling = true;
        for (int c = 0; c < 8; c++) {
          final Point3D q = p[c]!;
          if (_sideOfCut(q.x, q.y) > 0) fv[c] = continued(q.x, q.y, q.z);
        }
      }
    }
    for (int c = 0; c < 8; c++) {
      // A cube touching an undefined sample is skipped, leaving a hole
      // rather than a surface stitched across a singularity.
      if (!fv[c].isFinite) return;
    }
    on = lattice;
    cubeI = i;
    cubeJ = j;
    cubeK = k;
    found.fillRange(0, found.length, null);

    for (final List<int> t in tets) {
      int belowCount = 0;
      for (final int c in t) {
        if (fv[c] < 0) belowCount++;
      }
      if (belowCount == 0 || belowCount == 4) continue; // no crossing

      final List<int> below = <int>[];
      final List<int> above = <int>[];
      for (final int c in t) {
        if (fv[c] < 0) {
          below.add(c);
        } else {
          above.add(c);
        }
      }

      if (below.length == 1 || above.length == 1) {
        // One corner cut off: the cut is a single triangle.
        final int apex = below.length == 1 ? below[0] : above[0];
        final List<int> others = below.length == 1 ? above : below;
        final c0 = crossing(apex, others[0]);
        final c1 = crossing(apex, others[1]);
        final c2 = crossing(apex, others[2]);
        // If any edge is a jump, the surface does not pass through this
        // tetrahedron the way its corners suggest, and none of it is drawn
        // here.
        if (!c0.root || !c1.root || !c2.root) continue;
        emit(c0, c1, c2);
      } else {
        // Two-two split: the cut is a quad, emitted as two triangles.
        final q0 = crossing(below[0], above[0]);
        final q1 = crossing(below[0], above[1]);
        final q2 = crossing(below[1], above[1]);
        final q3 = crossing(below[1], above[0]);
        if (!q0.root || !q1.root || !q2.root || !q3.root) continue;
        emit(q0, q1, q2);
        emit(q0, q2, q3);
      }
    }
  }

  /// March the cube at (i, j, k) of [lattice] as [_refineSplit]³ smaller
  /// ones, looking into any of those that are still too thin to see through.
  void marchFiner(_Lattice lattice, int i, int j, int k, int level) {
    final _Lattice finer = lattice.finer;
    final int i0 = i * _refineSplit;
    final int j0 = j * _refineSplit;
    final int k0 = k * _refineSplit;
    for (int a = 0; a < _refineSplit; a++) {
      for (int b = 0; b < _refineSplit; b++) {
        for (int c = 0; c < _refineSplit; c++) {
          final int fi = i0 + a, fj = j0 + b, fk = k0 + c;
          if (level < _refineLevels && finer.thinCube(fi, fj, fk)) {
            marchFiner(finer, fi, fj, fk, level + 1);
          } else {
            marchCube(finer, fi, fj, fk);
          }
        }
      }
    }
  }

  final Uint8List? thin = refine ? _thinCells(lattice, resolution) : null;

  for (int i = 0; i < resolution; i++) {
    for (int j = 0; j < resolution; j++) {
      for (int k = 0; k < resolution; k++) {
        if (thin != null && thin[(i * resolution + j) * resolution + k] != 0) {
          marchFiner(lattice, i, j, k, 1);
        } else {
          marchCube(lattice, i, j, k);
        }
      }
    }
  }

  // An inequality is a solid, and the box cuts it: close it where it meets
  // the walls. Without these it was drawn as its boundary alone, a skin with
  // nothing to say which side was the region — x²+y² < 1 an open tube, a
  // ball a hollow sphere, z ≤ x²−y² a bare saddle.
  if (relation.isRegion && relation != PlotRelation.notEqual) {
    _addWallCaps(
      out,
      normals,
      samples,
      n,
      xMin,
      yMin,
      zMin,
      dx,
      dy,
      dz,
      relation,
    );
  }

  return (triangles: out, normals: Float32List.fromList(normals));
}

/// The parts of the box's six walls that lie in an inequality's region, as
/// triangles with the wall's own normal.
///
/// Each wall is a square of the march's lattice, and each of its cells is
/// clipped to where the relation holds, the edge placed by interpolating
/// between corners as marching squares does. A cell wholly inside is kept
/// whole; one the boundary crosses keeps the part on the region's side, so the
/// cap meets the boundary surface along the line where it reaches the wall.
void _addWallCaps(
  List<LevelTriangle> out,
  List<double> normals,
  Float64List samples,
  int n,
  double xMin,
  double yMin,
  double zMin,
  double dx,
  double dy,
  double dz,
  PlotRelation relation,
) {
  int idx(int i, int j, int k) => (i * n + j) * n + k;
  // Which side counts, as a sign: the region is where sign * F is below zero
  // (or at it, for a non-strict relation — the difference is the boundary,
  // which the surface itself already draws).
  final double sign =
      relation == PlotRelation.less || relation == PlotRelation.lessEqual
          ? 1
          : -1;

  final List<Point3D> poly = <Point3D>[];
  final Float64List cornerValue = Float64List(4);
  final List<Point3D?> corner = List<Point3D?>.filled(4, null);

  // A wall is fixed on one axis at [fixedAt]; (a, b) walk the other two.
  void wall(int axis, int fixedAt, double nx, double ny, double nz) {
    Point3D pointAt(int a, int b) => switch (axis) {
      0 => Point3D(xMin + fixedAt * dx, yMin + a * dy, zMin + b * dz),
      1 => Point3D(xMin + a * dx, yMin + fixedAt * dy, zMin + b * dz),
      _ => Point3D(xMin + a * dx, yMin + b * dy, zMin + fixedAt * dz),
    };
    double valueAt(int a, int b) => switch (axis) {
      0 => samples[idx(fixedAt, a, b)],
      1 => samples[idx(a, fixedAt, b)],
      _ => samples[idx(a, b, fixedAt)],
    };

    for (int a = 0; a < n - 1; a++) {
      for (int b = 0; b < n - 1; b++) {
        // Corners in order round the cell.
        const List<(int, int)> around = <(int, int)>[
          (0, 0),
          (1, 0),
          (1, 1),
          (0, 1),
        ];
        bool usable = true;
        int inside = 0;
        for (int c = 0; c < 4; c++) {
          final double v = sign * valueAt(a + around[c].$1, b + around[c].$2);
          if (!v.isFinite) {
            usable = false;
            break;
          }
          cornerValue[c] = v;
          corner[c] = pointAt(a + around[c].$1, b + around[c].$2);
          if (v < 0) inside++;
        }
        if (!usable || inside == 0) continue;

        // Sutherland–Hodgman against "below zero": keep the corners inside,
        // and the crossing on every edge that changes side.
        poly.clear();
        for (int c = 0; c < 4; c++) {
          final int d = (c + 1) % 4;
          final double va = cornerValue[c], vb = cornerValue[d];
          final Point3D pa = corner[c]!, pb = corner[d]!;
          if (va < 0) poly.add(pa);
          if ((va < 0) != (vb < 0)) {
            final double t = va / (va - vb);
            poly.add(
              Point3D(
                pa.x + (pb.x - pa.x) * t,
                pa.y + (pb.y - pa.y) * t,
                pa.z + (pb.z - pa.z) * t,
              ),
            );
          }
        }
        // A fan: the clipped piece of a square is convex.
        for (int v = 1; v + 1 < poly.length; v++) {
          out.add((a: poly[0], b: poly[v], c: poly[v + 1]));
          for (int k = 0; k < 3; k++) {
            normals
              ..add(nx)
              ..add(ny)
              ..add(nz);
          }
        }
      }
    }
  }

  final int last = n - 1;
  wall(0, 0, -1, 0, 0);
  wall(0, last, 1, 0, 0);
  wall(1, 0, 0, -1, 0);
  wall(1, last, 0, 1, 0);
  wall(2, 0, 0, 0, -1);
  wall(2, last, 0, 0, 1);
}

/// The cells of the march's own lattice to look into, one flag per cell, or
/// null when there are none — or so many that looking would cost more than
/// it could be worth (see [_refineCellLimit]).
///
/// Every lattice edge is tested once and marks the four cells around it, and
/// the marked cells are then grown by one in every direction. Where a refined
/// cell meets a plain one the two cut their shared face differently, by a
/// sliver; grown, that seam falls where the sheets are far enough apart for
/// the plain march to see them properly, and the sliver is under a pixel.
Uint8List? _thinCells(_Lattice lattice, int cells) {
  int at(int i, int j, int k) => (i * cells + j) * cells + k;
  final Uint8List marked = Uint8List(cells * cells * cells);
  bool any = false;

  void mark(int i, int j, int k) {
    if (i < 0 || j < 0 || k < 0 || i >= cells || j >= cells || k >= cells) {
      return;
    }
    marked[at(i, j, k)] = 1;
    any = true;
  }

  final int n = cells + 1;
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      for (int k = 0; k < n; k++) {
        // The edge along each axis from here, and the four cells around it.
        if (i < cells && lattice.dipsThrough(i, j, k, 0)) {
          for (int a = -1; a <= 0; a++) {
            for (int b = -1; b <= 0; b++) {
              mark(i, j + a, k + b);
            }
          }
        }
        if (j < cells && lattice.dipsThrough(i, j, k, 1)) {
          for (int a = -1; a <= 0; a++) {
            for (int b = -1; b <= 0; b++) {
              mark(i + a, j, k + b);
            }
          }
        }
        if (k < cells && lattice.dipsThrough(i, j, k, 2)) {
          for (int a = -1; a <= 0; a++) {
            for (int b = -1; b <= 0; b++) {
              mark(i + a, j + b, k);
            }
          }
        }
      }
    }
  }
  if (!any) return null;

  final Uint8List grown = Uint8List(marked.length);
  int count = 0;
  for (int i = 0; i < cells; i++) {
    for (int j = 0; j < cells; j++) {
      for (int k = 0; k < cells; k++) {
        if (marked[at(i, j, k)] == 0) continue;
        for (int a = max(0, i - 1); a <= min(cells - 1, i + 1); a++) {
          for (int b = max(0, j - 1); b <= min(cells - 1, j + 1); b++) {
            for (int c = max(0, k - 1); c <= min(cells - 1, k + 1); c++) {
              final int cell = at(a, b, c);
              if (grown[cell] == 0) {
                grown[cell] = 1;
                count++;
              }
            }
          }
        }
      }
    }
  }
  return count > _refineCellLimit ? null : grown;
}

/// A point of a traced curve in the plane.
typedef PlanePoint = ({double x, double y});

/// How many steps each turn of a polar curve is cut into before any is
/// refined.
const int _polarSteps = 360;

/// How many times one of those steps may be halved to bring it under the
/// chord it is drawn at.
const int _polarDepth = 10;

/// A polar curve `r = f(θ)` as a path: θ swept over
/// [PlotExpression.sweptThetaRange], with a null wherever the path breaks.
///
/// Refined where it needs to be rather than sampled finely everywhere: a step
/// whose chord is longer than [chord] is halved, and a step lying wholly
/// outside the window is left as it is, since none of it is drawn. A step
/// still too long after [_polarDepth] halvings is a pole — r running off to
/// infinity and back from the other side, as r = 1/cos θ does at θ = π/2 —
/// and the path is broken there instead of drawn across the window.
List<PlanePoint?> polarCurvePoints(
  PlotExpression f, {
  required double xMin,
  required double xMax,
  required double yMin,
  required double yMax,
  required double chord,
}) {
  final List<PlanePoint?> out = <PlanePoint?>[];
  if (!f.isPolarCurve || !(chord > 0)) return out;

  bool outside(PlanePoint a, PlanePoint b) =>
      max(a.x, b.x) < xMin - chord ||
      min(a.x, b.x) > xMax + chord ||
      max(a.y, b.y) < yMin - chord ||
      min(a.y, b.y) > yMax + chord;

  void step(double ta, PlanePoint? a, double tb, PlanePoint? b, int depth) {
    if (a == null || b == null) {
      out.add(b);
      return;
    }
    final double dx = b.x - a.x;
    final double dy = b.y - a.y;
    if (sqrt(dx * dx + dy * dy) <= chord || outside(a, b)) {
      out.add(b);
      return;
    }
    if (depth == _polarDepth) {
      out.add(null);
      out.add(b);
      return;
    }
    final double tm = (ta + tb) / 2;
    final PlanePoint? m = f.polarPoint(tm);
    step(ta, a, tm, m, depth + 1);
    step(tm, m, tb, b, depth + 1);
  }

  final ({double min, double max}) range = f.sweptThetaRange;
  final int steps = _thetaStepsFor(f, _polarSteps);
  double thetaAt(int i) => range.min + (range.max - range.min) * i / steps;
  PlanePoint? previous = f.polarPoint(thetaAt(0));
  out.add(previous);
  for (int i = 1; i <= steps; i++) {
    final double t = thetaAt(i);
    final PlanePoint? here = f.polarPoint(t);
    step(thetaAt(i - 1), previous, t, here, 0);
    previous = here;
  }
  return out;
}

/// The part of the segment from (x1, y1) to (x2, y2) inside the window, with
/// where along it that part starts and ends; null when none of it is inside.
({double x1, double y1, double x2, double y2, double t0, double t1})? _clip(
  double x1,
  double y1,
  double x2,
  double y2,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
) {
  // Liang–Barsky: each side of the window narrows the span [t0, t1] of the
  // segment that can still be inside.
  double t0 = 0, t1 = 1;
  final double dx = x2 - x1;
  final double dy = y2 - y1;
  bool keep(double p, double q) {
    if (p == 0) return q >= 0;
    final double r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  if (!keep(-dx, x1 - xMin) ||
      !keep(dx, xMax - x1) ||
      !keep(-dy, y1 - yMin) ||
      !keep(dy, yMax - y1)) {
    return null;
  }
  return (
    x1: x1 + t0 * dx,
    y1: y1 + t0 * dy,
    x2: x1 + t1 * dx,
    y2: y1 + t1 * dy,
    t0: t0,
    t1: t1,
  );
}

/// Where a polar curve's path crosses the line on which one coordinate is
/// [at]: the other coordinate at each crossing.
///
/// [across] reads the coordinate the line holds fixed, [along] the other.
List<double> _polarCrossings(
  List<PlanePoint?> path,
  double at,
  double Function(PlanePoint) across,
  double Function(PlanePoint) along,
) {
  final List<double> out = <double>[];
  for (int i = 0; i + 1 < path.length; i++) {
    final PlanePoint? a = path[i];
    final PlanePoint? b = path[i + 1];
    if (a == null || b == null) continue;
    final double da = across(a) - at;
    final double db = across(b) - at;
    // Half-open, so a path passing exactly through a vertex is counted once.
    if ((da < 0) == (db < 0)) continue;
    final double t = da / (da - db);
    out.add(along(a) + (along(b) - along(a)) * t);
  }
  return out;
}

/// A polar curve as the segments [marchingSquares] would have found, on
/// whichever plane is being looked at.
///
/// Held at z it is the curve itself. Held at x or y it is where the wall
/// standing on the curve meets that plane — a vertical line at each place
/// the curve crosses it, as x² + y² = 1 held at x = 0 is the two lines
/// y = ±1.
List<LevelSegment> _polarSegments(
  PlotExpression f,
  double hMin,
  double hMax,
  double vMin,
  double vMax,
  int resolution,
  PlaneSlice slice,
) {
  final List<LevelSegment> out = <LevelSegment>[];

  if (slice.axis == SliceAxis.z) {
    final List<PlanePoint?> path = polarCurvePoints(
      f,
      xMin: hMin,
      xMax: hMax,
      yMin: vMin,
      yMax: vMax,
      chord: min(hMax - hMin, vMax - vMin) / resolution,
    );
    for (int i = 0; i + 1 < path.length; i++) {
      final PlanePoint? a = path[i];
      final PlanePoint? b = path[i + 1];
      if (a == null || b == null) continue;
      final clipped = _clip(a.x, a.y, b.x, b.y, hMin, hMax, vMin, vMax);
      if (clipped == null) continue;
      out.add((x1: clipped.x1, y1: clipped.y1, x2: clipped.x2, y2: clipped.y2));
    }
    return out;
  }

  // Held at x = c the plane's horizontal is y; held at y = c it is x.
  final bool heldX = slice.axis == SliceAxis.x;
  final double c = slice.offset;
  final List<PlanePoint?> path = polarCurvePoints(
    f,
    xMin: heldX ? c : hMin,
    xMax: heldX ? c : hMax,
    yMin: heldX ? hMin : c,
    yMax: heldX ? hMax : c,
    chord: (hMax - hMin) / resolution,
  );
  final List<double> hits = _polarCrossings(
    path,
    c,
    heldX ? (PlanePoint p) => p.x : (PlanePoint p) => p.y,
    heldX ? (PlanePoint p) => p.y : (PlanePoint p) => p.x,
  );
  for (final double h in hits) {
    if (h < hMin || h > hMax) continue;
    out.add((x1: h, y1: vMin, x2: h, y2: vMax));
  }
  return out;
}

/// How far a polar curve reaches from the origin along x and along y, within
/// ±[probe] on both; null when none of it is inside.
///
/// Read off the traced path, for framing (see [levelSetExtent]): looking for
/// the curve by sampling would miss the parts of it with negative r.
({double x, double y})? polarCurveReach(PlotExpression f, double probe) {
  final List<PlanePoint?> path = polarCurvePoints(
    f,
    xMin: -probe,
    xMax: probe,
    yMin: -probe,
    yMax: probe,
    chord: probe / 200,
  );
  double reachX = 0, reachY = 0;
  bool any = false;
  for (int i = 0; i + 1 < path.length; i++) {
    final PlanePoint? a = path[i];
    final PlanePoint? b = path[i + 1];
    if (a == null || b == null) continue;
    final clipped = _clip(a.x, a.y, b.x, b.y, -probe, probe, -probe, probe);
    if (clipped == null) continue;
    any = true;
    reachX = max(reachX, max(clipped.x1.abs(), clipped.x2.abs()));
    reachY = max(reachY, max(clipped.y1.abs(), clipped.y2.abs()));
  }
  return any ? (x: reachX, y: reachY) : null;
}

/// The y values where a polar curve crosses the vertical line at [x], for
/// the trace (see [levelSetYAt]).
List<double> _polarCurveYAt(
  PlotExpression f,
  double x,
  double yMin,
  double yMax,
  int samples,
) {
  final List<PlanePoint?> path = polarCurvePoints(
    f,
    xMin: x,
    xMax: x,
    yMin: yMin,
    yMax: yMax,
    chord: (yMax - yMin) / samples,
  );
  final List<double> roots = <double>[];
  for (final double y in _polarCrossings(
    path,
    x,
    (PlanePoint p) => p.x,
    (PlanePoint p) => p.y,
  )) {
    if (y < yMin || y > yMax) continue;
    // A curve that retraces itself — r = sin θ goes round its circle twice
    // in one turn — meets the line again at the same place. One root is
    // enough.
    const double tol = 1e-7;
    if (roots.any((double seen) => (seen - y).abs() <= tol * (1 + y.abs()))) {
      continue;
    }
    roots.add(y);
  }
  return roots;
}

/// [path] with the points it can do without: every run between breaks is
/// cut down to the fewest points that keep it within [tolerance] of where it
/// was (Douglas–Peucker). Breaks are kept where they are.
List<PlanePoint?> _thinned(
  List<PlanePoint?> path,
  double tolerance, {
  double longest = double.infinity,
}) {
  final List<PlanePoint?> out = <PlanePoint?>[];
  // How far p is from the segment a–b, not from the line through them: a
  // closed loop starts and ends at one point, and the line through a point
  // and itself is no line at all.
  double away(PlanePoint p, PlanePoint a, PlanePoint b) {
    final double dx = b.x - a.x;
    final double dy = b.y - a.y;
    final double len2 = dx * dx + dy * dy;
    final double t =
        len2 == 0
            ? 0
            : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    final double ex = a.x + dx * t - p.x;
    final double ey = a.y + dy * t - p.y;
    return sqrt(ex * ex + ey * ey);
  }

  int start = 0;
  while (start < path.length) {
    if (path[start] == null) {
      out.add(null);
      start++;
      continue;
    }
    int end = start;
    while (end + 1 < path.length && path[end + 1] != null) {
      end++;
    }
    final List<bool> keep = List<bool>.filled(end - start + 1, false);
    keep[0] = true;
    keep[end - start] = true;
    final List<(int, int)> pending = <(int, int)>[(start, end)];
    while (pending.isNotEmpty) {
      final (int i, int j) = pending.removeLast();
      if (j - i < 2) continue;
      double furthest = -1;
      int at = -1;
      for (int k = i + 1; k < j; k++) {
        final double d = away(path[k]!, path[i]!, path[j]!);
        if (d > furthest) {
          furthest = d;
          at = k;
        }
      }
      final double dx = path[j]!.x - path[i]!.x;
      final double dy = path[j]!.y - path[i]!.y;
      final bool tooLong = dx * dx + dy * dy > longest * longest;
      if (furthest > tolerance || tooLong) {
        // Split where the path strays furthest, or for a run that only went
        // on too long, in the middle.
        final int split = furthest > tolerance ? at : (i + j) ~/ 2;
        keep[split - start] = true;
        pending.add((i, split));
        pending.add((split, j));
      }
    }
    for (int k = start; k <= end; k++) {
      if (keep[k - start]) out.add(path[k]);
    }
    start = end + 1;
  }
  return out;
}

/// A sampled polar curve in the box: the wall standing on it, built on the
/// curve the flat view traces.
///
/// The equation does not mention z, so the wall is all there is to it, and the
/// curve under it is traced address by address in the plane (see
/// [_marchingSquares]) — whole where its branches meet, which a march through
/// the box was not. The shading is smoothed round the curve by matching the
/// ends of neighbouring segments: two cells find a shared crossing from
/// opposite ends of its edge, so the ends agree only to rounding, and they are
/// matched on a grid far finer than any cell.
LevelSurface _wallOnCurve(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
) {
  final List<LevelSegment> curve = _marchingSquares(
    f,
    xMin,
    xMax,
    yMin,
    yMax,
    resolution * 2,
    const PlaneSlice(),
    0,
  );
  final int courses = max(1, resolution ~/ 2);
  final double dz = (zMax - zMin) / courses;

  ({double x, double y}) square(LevelSegment s) {
    final double dx = s.x2 - s.x1;
    final double dy = s.y2 - s.y1;
    final double len = sqrt(dx * dx + dy * dy);
    if (len == 0 || !len.isFinite) return (x: 0, y: 0);
    return (x: dy / len, y: -dx / len);
  }

  final double grain = (xMax - xMin) * 1e-9;
  (int, int) key(double x, double y) => (
    (x / grain).round(),
    (y / grain).round(),
  );
  final Map<(int, int), List<int>> ends = <(int, int), List<int>>{};
  for (int i = 0; i < curve.length; i++) {
    final LevelSegment s = curve[i];
    ends.putIfAbsent(key(s.x1, s.y1), () => <int>[]).add(i);
    ends.putIfAbsent(key(s.x2, s.y2), () => <int>[]).add(i);
  }

  // The level normal at an end of a segment, averaged with the segments that
  // share it — but only those running the same way: where two branches cross,
  // their directions have nothing to do with each other.
  ({double x, double y}) normalAt(
    double x,
    double y,
    ({double x, double y}) own,
  ) {
    double nx = 0, ny = 0;
    for (final int j in ends[key(x, y)] ?? const <int>[]) {
      final ({double x, double y}) n = square(curve[j]);
      final double d = n.x * own.x + n.y * own.y;
      if (d.abs() < 0.7) continue;
      nx += d < 0 ? -n.x : n.x;
      ny += d < 0 ? -n.y : n.y;
    }
    final double len = sqrt(nx * nx + ny * ny);
    return len == 0 ? own : (x: nx / len, y: ny / len);
  }

  final List<LevelTriangle> out = <LevelTriangle>[];
  final List<double> normals = <double>[];
  for (final LevelSegment s in curve) {
    final ({double x, double y}) own = square(s);
    if (own.x == 0 && own.y == 0) continue;
    final ({double x, double y}) n1 = normalAt(s.x1, s.y1, own);
    final ({double x, double y}) n2 = normalAt(s.x2, s.y2, own);
    for (int k = 0; k < courses; k++) {
      final double z0 = zMin + k * dz;
      final double z1 = k == courses - 1 ? zMax : z0 + dz;
      final Point3D a0 = Point3D(s.x1, s.y1, z0);
      final Point3D b0 = Point3D(s.x2, s.y2, z0);
      final Point3D b1 = Point3D(s.x2, s.y2, z1);
      final Point3D a1 = Point3D(s.x1, s.y1, z1);
      out.add((a: a0, b: b0, c: b1));
      normals.addAll(<double>[n1.x, n1.y, 0, n2.x, n2.y, 0, n2.x, n2.y, 0]);
      out.add((a: a0, b: b1, c: a1));
      normals.addAll(<double>[n1.x, n1.y, 0, n2.x, n2.y, 0, n1.x, n1.y, 0]);
    }
  }
  return (triangles: out, normals: Float32List.fromList(normals));
}

/// A polar curve in the box: the wall standing on it from floor to ceiling,
/// as [marchedSurface] makes of any curve in the plane.
///
/// Built straight from the traced path, a strip of quads per step, each cut
/// into [resolution] / 2 courses so the triangles are near the size the
/// lattice would have made them — the depth sort works triangle by triangle
/// and copes badly with slivers the height of the box. The normal is level,
/// square to the path, taken across each point's neighbours so the shading
/// runs smoothly round the curve rather than in facets.
LevelSurface _polarWall(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
) {
  final double chord = min(xMax - xMin, yMax - yMin) / resolution;
  // Thinned before it is stood up. The path is cut at least 360 times a
  // turn whatever its shape, and every step becomes a strip of triangles the
  // full height of the box, so the long gentle stretches of a curve cost
  // as much as its tight loops. Kept within an eighth of a lattice cell of
  // the path, which is under a pixel at any size the box is drawn.
  final List<PlanePoint?> path = _thinned(
    polarCurvePoints(
      f,
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
      chord: chord,
    ),
    chord / 8,
    longest: chord,
  );
  final int courses = max(1, resolution ~/ 2);
  final double dz = (zMax - zMin) / courses;
  final List<LevelTriangle> out = <LevelTriangle>[];
  final List<double> normals = <double>[];

  // The level normal at path[i], across its neighbours in the same run.
  ({double x, double y}) normalAt(int i) {
    final PlanePoint here = path[i]!;
    final PlanePoint before =
        i > 0 && path[i - 1] != null ? path[i - 1]! : here;
    final PlanePoint after =
        i + 1 < path.length && path[i + 1] != null ? path[i + 1]! : here;
    final double tx = after.x - before.x;
    final double ty = after.y - before.y;
    final double len = sqrt(tx * tx + ty * ty);
    if (len == 0 || !len.isFinite) return (x: 1, y: 0);
    return (x: ty / len, y: -tx / len);
  }

  for (int i = 0; i + 1 < path.length; i++) {
    final PlanePoint? a = path[i];
    final PlanePoint? b = path[i + 1];
    if (a == null || b == null) continue;
    final clipped = _clip(a.x, a.y, b.x, b.y, xMin, xMax, yMin, yMax);
    if (clipped == null) continue;
    if (clipped.x1 == clipped.x2 && clipped.y1 == clipped.y2) continue;

    final ({double x, double y}) na = normalAt(i);
    final ({double x, double y}) nb = normalAt(i + 1);
    // Normals at the clipped ends, part of the way along as the ends are.
    ({double x, double y}) between(double t) => (
      x: na.x + (nb.x - na.x) * t,
      y: na.y + (nb.y - na.y) * t,
    );
    final ({double x, double y}) n1 = between(clipped.t0);
    final ({double x, double y}) n2 = between(clipped.t1);

    for (int k = 0; k < courses; k++) {
      final double z0 = zMin + k * dz;
      final double z1 = k == courses - 1 ? zMax : z0 + dz;
      final Point3D a0 = Point3D(clipped.x1, clipped.y1, z0);
      final Point3D b0 = Point3D(clipped.x2, clipped.y2, z0);
      final Point3D b1 = Point3D(clipped.x2, clipped.y2, z1);
      final Point3D a1 = Point3D(clipped.x1, clipped.y1, z1);
      out.add((a: a0, b: b0, c: b1));
      normals.addAll(<double>[n1.x, n1.y, 0, n2.x, n2.y, 0, n2.x, n2.y, 0]);
      out.add((a: a0, b: b1, c: a1));
      normals.addAll(<double>[n1.x, n1.y, 0, n2.x, n2.y, 0, n1.x, n1.y, 0]);
    }
  }
  return (triangles: out, normals: Float32List.fromList(normals));
}

/// A point of a traced surface.
typedef SpacePoint = ({double x, double y, double z});

/// A spherical surface `ρ = f(θ, φ)` sampled on a grid of its angles: θ over
/// [PlotExpression.sweptThetaRange] in [thetaSteps] steps, φ from 0 to π in
/// [phiSteps]. Row by row in θ, null where f is undefined.
List<SpacePoint?> _sphericalGrid(
  PlotExpression f,
  int thetaSteps,
  int phiSteps,
) {
  final ({double min, double max}) range = f.sweptThetaRange;
  return <SpacePoint?>[
    for (int i = 0; i <= thetaSteps; i++)
      for (int j = 0; j <= phiSteps; j++)
        f.sphericalPoint(
          range.min + (range.max - range.min) * i / thetaSteps,
          pi * j / phiSteps,
        ),
  ];
}

/// How many steps θ is cut into for every turn it sweeps, given [perTurn].
int _thetaStepsFor(PlotExpression f, int perTurn) {
  final ({double min, double max}) range = f.sweptThetaRange;
  return max(1, (perTurn * (range.max - range.min) / (2 * pi)).ceil());
}

/// One corner of a triangle being clipped: where it is and its normal.
typedef _Corner =
    ({double x, double y, double z, double nx, double ny, double nz});

/// [corners], a convex polygon, with the part outside the box cut away.
///
/// Sutherland–Hodgman, a wall at a time; the normal is carried along each
/// cut edge the way the position is, so the shading does not change where
/// the box cuts the surface.
List<_Corner> _clipToBox(
  List<_Corner> corners,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
) {
  List<_Corner> polygon = corners;
  _Corner lerp(_Corner a, _Corner b, double t) => (
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t,
    nx: a.nx + (b.nx - a.nx) * t,
    ny: a.ny + (b.ny - a.ny) * t,
    nz: a.nz + (b.nz - a.nz) * t,
  );
  // Each wall as "how far inside it a corner is", positive when inside.
  for (final double Function(_Corner) inside in <double Function(_Corner)>[
    (_Corner c) => c.x - xMin,
    (_Corner c) => xMax - c.x,
    (_Corner c) => c.y - yMin,
    (_Corner c) => yMax - c.y,
    (_Corner c) => c.z - zMin,
    (_Corner c) => zMax - c.z,
  ]) {
    if (polygon.isEmpty) return polygon;
    final List<_Corner> kept = <_Corner>[];
    for (int i = 0; i < polygon.length; i++) {
      final _Corner a = polygon[i];
      final _Corner b = polygon[(i + 1) % polygon.length];
      final double da = inside(a);
      final double db = inside(b);
      if (da >= 0) kept.add(a);
      if ((da >= 0) != (db >= 0)) kept.add(lerp(a, b, da / (da - db)));
    }
    polygon = kept;
  }
  return polygon;
}

/// A spherical surface in the box, as [marchedSurface] makes of any level
/// surface — but built from the swept grid of its angles, so a negative ρ is
/// a point through the origin rather than no point at all, and θ covers the
/// whole of [PlotExpression.thetaRange].
///
/// θ is cut twice as finely as φ, since it covers twice the angle. The normal
/// at each grid point is square to the grid lines through it; at the poles,
/// where every θ meets at one point and there are no lines to be square to,
/// it points away from the origin. A cell is dropped when it is torn — its
/// corners further apart than the box is across, which is ρ running off to
/// infinity and back between them — rather than stretched across the box.
LevelSurface _sphericalSurface(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
) {
  final int phiSteps = max(4, resolution);
  final int thetaSteps = _thetaStepsFor(f, 2 * phiSteps);
  final List<SpacePoint?> grid = _sphericalGrid(f, thetaSteps, phiSteps);
  final int columns = phiSteps + 1;
  SpacePoint? at(int i, int j) {
    if (i < 0 || i > thetaSteps || j < 0 || j > phiSteps) return null;
    return grid[i * columns + j];
  }

  ({double x, double y, double z}) normalAt(int i, int j) {
    final SpacePoint here = at(i, j)!;
    final SpacePoint a = at(i - 1, j) ?? here;
    final SpacePoint b = at(i + 1, j) ?? here;
    final SpacePoint c = at(i, j - 1) ?? here;
    final SpacePoint d = at(i, j + 1) ?? here;
    final double ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
    final double vx = d.x - c.x, vy = d.y - c.y, vz = d.z - c.z;
    double nx = uy * vz - uz * vy;
    double ny = uz * vx - ux * vz;
    double nz = ux * vy - uy * vx;
    double len = sqrt(nx * nx + ny * ny + nz * nz);
    if (len == 0 || !len.isFinite) {
      (nx, ny, nz) = (here.x, here.y, here.z);
      len = sqrt(nx * nx + ny * ny + nz * nz);
      if (len == 0 || !len.isFinite) return (x: 0, y: 0, z: 1);
    }
    return (x: nx / len, y: ny / len, z: nz / len);
  }

  final double dx = xMax - xMin, dy = yMax - yMin, dz = zMax - zMin;
  final double tear = sqrt(dx * dx + dy * dy + dz * dz);
  bool torn(SpacePoint a, SpacePoint b) {
    final double ex = b.x - a.x, ey = b.y - a.y, ez = b.z - a.z;
    return sqrt(ex * ex + ey * ey + ez * ez) > tear;
  }

  bool outside(SpacePoint p) =>
      p.x < xMin ||
      p.x > xMax ||
      p.y < yMin ||
      p.y > yMax ||
      p.z < zMin ||
      p.z > zMax;

  final List<LevelTriangle> out = <LevelTriangle>[];
  final List<double> normals = <double>[];
  void emit(_Corner a, _Corner b, _Corner c) {
    out.add((
      a: Point3D(a.x, a.y, a.z),
      b: Point3D(b.x, b.y, b.z),
      c: Point3D(c.x, c.y, c.z),
    ));
    for (final _Corner v in <_Corner>[a, b, c]) {
      final double len = sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz);
      final double k = len == 0 || !len.isFinite ? 0 : 1 / len;
      normals.addAll(<double>[v.nx * k, v.ny * k, k == 0 ? 1 : v.nz * k]);
    }
  }

  _Corner corner(int i, int j) {
    final SpacePoint p = at(i, j)!;
    final ({double x, double y, double z}) n = normalAt(i, j);
    return (x: p.x, y: p.y, z: p.z, nx: n.x, ny: n.y, nz: n.z);
  }

  void triangle(int i0, int j0, int i1, int j1, int i2, int j2) {
    final SpacePoint a = at(i0, j0)!, b = at(i1, j1)!, c = at(i2, j2)!;
    if (torn(a, b) || torn(b, c) || torn(c, a)) return;
    // At a pole two corners are the same point and there is nothing to draw.
    if ((a.x == b.x && a.y == b.y && a.z == b.z) ||
        (b.x == c.x && b.y == c.y && b.z == c.z) ||
        (c.x == a.x && c.y == a.y && c.z == a.z)) {
      return;
    }
    final _Corner ca = corner(i0, j0), cb = corner(i1, j1), cc = corner(i2, j2);
    if (!outside(a) && !outside(b) && !outside(c)) {
      emit(ca, cb, cc);
      return;
    }
    final List<_Corner> kept = _clipToBox(
      <_Corner>[ca, cb, cc],
      xMin,
      xMax,
      yMin,
      yMax,
      zMin,
      zMax,
    );
    for (int k = 1; k + 1 < kept.length; k++) {
      emit(kept[0], kept[k], kept[k + 1]);
    }
  }

  for (int i = 0; i < thetaSteps; i++) {
    for (int j = 0; j < phiSteps; j++) {
      if (at(i, j) == null ||
          at(i + 1, j) == null ||
          at(i + 1, j + 1) == null ||
          at(i, j + 1) == null) {
        continue;
      }
      triangle(i, j, i + 1, j, i + 1, j + 1);
      triangle(i, j, i + 1, j + 1, i, j + 1);
    }
  }
  return (triangles: out, normals: Float32List.fromList(normals));
}

/// The last few cuts of spherical surfaces by a plane, before they are
/// fitted to a window.
///
/// Kept apart from [marchingSquares]'s cache, which is keyed on the window:
/// the cut does not depend on the window, only on the plane, and cutting
/// again on every frame of a pan would be the whole sweep each time.
final PlotCache<List<LevelSegment>> _sphericalCuts =
    PlotCache<List<LevelSegment>>(4);

/// Where a spherical surface meets the plane [slice] holds, as segments in
/// that plane's own coordinates, unclipped.
///
/// Found by marching squares over the angles rather than over the plane: the
/// surface is a grid in (θ, φ), and the distance of each grid point from the
/// plane changes sign wherever the surface crosses it. Each crossing is placed
/// on the surface — the angles there are swept to a point — so the cut lies on
/// the surface however coarse the grid. φ is cut into an odd number of steps,
/// so no row of the grid lies on the equator, where the plane z = 0 meets
/// every surface: a grid line lying in the plane has no sign to change.
List<LevelSegment> _sphericalCut(PlotExpression f, PlaneSlice slice) {
  return _sphericalCuts.resolve(
    plotCacheKey(f, <double>[slice.axis.index.toDouble(), slice.offset], 0),
    () {
      const int phiSteps = 181;
      final int thetaSteps = _thetaStepsFor(f, 360);
      final ({double min, double max}) range = f.sweptThetaRange;
      double thetaAt(double i) =>
          range.min + (range.max - range.min) * i / thetaSteps;
      double phiAt(double j) => pi * j / phiSteps;

      double across(SpacePoint p) =>
          switch (slice.axis) {
            SliceAxis.x => p.x,
            SliceAxis.y => p.y,
            SliceAxis.z => p.z,
          } -
          slice.offset;
      ({double h, double v}) onPlane(SpacePoint p) => switch (slice.axis) {
        SliceAxis.x => (h: p.y, v: p.z),
        SliceAxis.y => (h: p.x, v: p.z),
        SliceAxis.z => (h: p.x, v: p.y),
      };
      double distanceAt(double i, double j) {
        final SpacePoint? p = f.sphericalPoint(thetaAt(i), phiAt(j));
        return p == null ? double.nan : across(p);
      }

      final int columns = phiSteps + 1;
      final Float64List g = Float64List((thetaSteps + 1) * columns);
      for (int i = 0; i <= thetaSteps; i++) {
        for (int j = 0; j <= phiSteps; j++) {
          g[i * columns + j] = distanceAt(i.toDouble(), j.toDouble());
        }
      }

      final List<LevelSegment> out = <LevelSegment>[];
      for (int i = 0; i < thetaSteps; i++) {
        for (int j = 0; j < phiSteps; j++) {
          final double g00 = g[i * columns + j];
          final double g10 = g[(i + 1) * columns + j];
          final double g11 = g[(i + 1) * columns + j + 1];
          final double g01 = g[i * columns + j + 1];
          if (!g00.isFinite ||
              !g10.isFinite ||
              !g11.isFinite ||
              !g01.isFinite) {
            continue;
          }
          final List<({double h, double v})> hits = <({double h, double v})>[];
          void edge(
            double ga,
            double gb,
            double ai,
            double aj,
            double bi,
            double bj,
          ) {
            if ((ga < 0) == (gb < 0)) return;
            final bool root = crossesZero(
              (double t) => distanceAt(ai + (bi - ai) * t, aj + (bj - aj) * t),
              ga,
              gb,
            );
            if (!root) return;
            final double t = _crossing(ga, gb);
            final SpacePoint? p = f.sphericalPoint(
              thetaAt(ai + (bi - ai) * t),
              phiAt(aj + (bj - aj) * t),
            );
            if (p != null) hits.add(onPlane(p));
          }

          final double i0 = i.toDouble(), i1 = i + 1.0;
          final double j0 = j.toDouble(), j1 = j + 1.0;
          edge(g00, g10, i0, j0, i1, j0);
          edge(g10, g11, i1, j0, i1, j1);
          edge(g11, g01, i1, j1, i0, j1);
          edge(g01, g00, i0, j1, i0, j0);
          for (int k = 0; k + 1 < hits.length; k += 2) {
            out.add((
              x1: hits[k].h,
              y1: hits[k].v,
              x2: hits[k + 1].h,
              y2: hits[k + 1].v,
            ));
          }
        }
      }
      return out;
    },
  );
}

/// [segments] cut to the window.
List<LevelSegment> _clipSegments(
  List<LevelSegment> segments,
  double hMin,
  double hMax,
  double vMin,
  double vMax,
) => <LevelSegment>[
  for (final LevelSegment s in segments)
    if (_clip(s.x1, s.y1, s.x2, s.y2, hMin, hMax, vMin, vMax)
        case final clipped?)
      (x1: clipped.x1, y1: clipped.y1, x2: clipped.x2, y2: clipped.y2),
];

/// The heights at which [segments] cross the vertical line at [h], within
/// [vMin] to [vMax], for the trace.
List<double> _segmentsCrossingAt(
  List<LevelSegment> segments,
  double h,
  double vMin,
  double vMax,
) {
  final List<double> out = <double>[];
  for (final LevelSegment s in segments) {
    final double da = s.x1 - h;
    final double db = s.x2 - h;
    if ((da < 0) == (db < 0)) continue;
    final double v = s.y1 + (s.y2 - s.y1) * (da / (da - db));
    if (v < vMin || v > vMax) continue;
    const double tol = 1e-7;
    if (out.any((double seen) => (seen - v).abs() <= tol * (1 + v.abs()))) {
      continue;
    }
    out.add(v);
  }
  return out;
}

/// How far a spherical surface reaches from the origin along each axis,
/// within ±[probe]; null when none of it is inside.
///
/// Read off the swept grid, for framing (see [levelSetExtent]), as
/// [polarCurveReach] is for a curve.
({double x, double y, double z})? sphericalSurfaceReach(
  PlotExpression f,
  double probe,
) {
  const int phiSteps = 64;
  final List<SpacePoint?> grid = _sphericalGrid(
    f,
    _thetaStepsFor(f, 2 * phiSteps),
    phiSteps,
  );
  double rx = 0, ry = 0, rz = 0;
  bool any = false;
  for (final SpacePoint? p in grid) {
    if (p == null) continue;
    if (p.x.abs() > probe || p.y.abs() > probe || p.z.abs() > probe) {
      // Running out of the probe: it reaches the edge on that axis.
      if (p.x.abs() > probe) rx = probe;
      if (p.y.abs() > probe) ry = probe;
      if (p.z.abs() > probe) rz = probe;
      any = true;
      continue;
    }
    any = true;
    rx = max(rx, p.x.abs());
    ry = max(ry, p.y.abs());
    rz = max(rz, p.z.abs());
  }
  return any ? (x: rx, y: ry, z: rz) : null;
}

/// The y values where an implicit curve crosses the vertical line at [x].
///
/// A level set is not a function of x, which is the whole difficulty in
/// tracing one. x²+y²=1 has two y for |x| < 1, one at the extremes, and none
/// beyond — so the trace has to *solve* F(x, y) = 0 for y rather than evaluate
/// anything. Reading F(x, 0) instead reports how far the point (x, 0) is from
/// satisfying the equation, which for the unit circle at x = 0.65 gives
/// −0.578: a number that is not on the curve and not the y the reader wants.
///
/// Roots are found by walking [yMin] to [yMax] for sign changes and bisecting
/// each one. Only crossings are found: a curve that touches zero without
/// changing sign is missed, which is the usual and acceptable limit of this
/// approach.
List<double> levelSetYAt(
  PlotExpression f,
  double x,
  double yMin,
  double yMax, {
  int samples = 600,
  PlaneSlice slice = const PlaneSlice(),
  double iso = 0,
}) {
  if (!f.isValid || yMax <= yMin) return const <double>[];
  if (f.isPolarCurve && iso == 0 && slice.axis == SliceAxis.z) {
    return _polarCurveYAt(f, x, yMin, yMax, samples);
  }
  if (f.isSphericalSurface && iso == 0) {
    return _segmentsCrossingAt(_sphericalCut(f, slice), x, yMin, yMax);
  }
  final List<double> roots = <double>[];
  void add(double y) {
    // Two samples either side of a root can both bisect to it.
    const double tol = 1e-7;
    for (final double seen in roots) {
      if ((seen - y).abs() <= tol * (1 + y.abs())) return;
    }
    roots.add(y);
  }

  // Address by address for a sampled polar equation, as it is drawn (see
  // [_marchingSquares]). Up the line, an address is continued past the cut,
  // so it runs on instead of leaping there.
  final List<({int sign, int turn})> sheets =
      iso == 0 ? f.equationSheets : const <({int sign, int turn})>[];
  if (sheets.isNotEmpty) {
    for (final ({int sign, int turn}) sheet in sheets) {
      _rootsAlong(
        (double v) {
          final (double px, double py, double pz) = _pointOn(slice, x, v);
          return f.evaluateOnSheet(
            sheet,
            px,
            py,
            pz,
            continued: _sideOfCut(px, py) == 1,
          );
        },
        yMin,
        yMax,
        samples,
        add,
      );
    }
    return roots;
  }
  _rootsAlong(
    (double v) => slice.sample(f, x, v) - iso,
    yMin,
    yMax,
    samples,
    add,
  );
  return roots;
}

/// Every root of [valueAt] between [yMin] and [yMax], handed to [add]: the
/// line is walked in [samples] steps for changes of sign, and each one bisected
/// and kept only if it settles on zero rather than on a leap.
void _rootsAlong(
  double Function(double y) valueAt,
  double yMin,
  double yMax,
  int samples,
  void Function(double y) add,
) {
  double previousY = yMin;
  double previous = valueAt(yMin);
  if (previous == 0) add(yMin);

  for (int i = 1; i <= samples; i++) {
    final double y = yMin + (yMax - yMin) * i / samples;
    final double value = valueAt(y);

    if (value == 0) {
      add(y);
    } else if (previous.isFinite &&
        value.isFinite &&
        previous != 0 &&
        previous.isNegative != value.isNegative) {
      double lo = previousY;
      double hi = y;
      double atLo = previous;
      double atHi = value;
      bool defined = true;
      for (int step = 0; step < 60; step++) {
        final double mid = (lo + hi) / 2;
        final double atMid = valueAt(mid);
        if (!atMid.isFinite) {
          defined = false;
          break;
        }
        if (atMid.isNegative == atLo.isNegative) {
          lo = mid;
          atLo = atMid;
        } else {
          hi = mid;
          atHi = atMid;
        }
      }
      // Bisected to nothing, a root leaves nothing either side of it; a jump
      // or a pole leaves the leap (see [crossesZero]). Neither of those is
      // on the curve, and the trace used to report them as though they were.
      if (defined &&
          (atHi - atLo).abs() <= _rootShrink * (value - previous).abs()) {
        add((lo + hi) / 2);
      }
    }

    previousY = y;
    previous = value;
  }
}
