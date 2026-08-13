import '../models/point_3d.dart';
import '../parsers/plot_expression.dart';

/// A straight piece of an implicit curve, in data coordinates.
typedef LevelSegment = ({double x1, double y1, double x2, double y2});

/// A triangle of an implicit surface, in data coordinates.
typedef LevelTriangle = ({Point3D a, Point3D b, Point3D c});

/// Remembers the last few marched results.
///
/// Marching depends only on the expression, the box and the resolution — not
/// on the camera. Rotating or panning a 3D plot repaints continuously without
/// changing any of those, so without a cache every frame re-sampled a 29³
/// lattice and re-tested 130,000 tetrahedra. A handful of entries is enough:
/// a plot has one surface, and the previous box is worth keeping across a
/// zoom step.
class _MarchCache<T> {
  _MarchCache(this._capacity);

  final int _capacity;
  final Map<Object, T> _entries = <Object, T>{};

  T resolve(Object key, T Function() compute) {
    final T? hit = _entries[key];
    if (hit != null) {
      // Refresh recency so the entry in active use is not the one evicted.
      _entries.remove(key);
      _entries[key] = hit;
      return hit;
    }
    final T value = compute();
    _entries[key] = value;
    if (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }
}

final _MarchCache<List<LevelSegment>> _squaresCache =
    _MarchCache<List<LevelSegment>>(4);
final _MarchCache<List<LevelTriangle>> _tetsCache =
    _MarchCache<List<LevelTriangle>>(3);

/// Identity of the expression plus the box, which is all the geometry depends
/// on. The expression is compiled once per edit, so its identity is a sound
/// key — a new object means a new expression.
Object _marchKey(PlotExpression f, List<double> bounds, int resolution) =>
    Object.hash(identityHashCode(f), Object.hashAll(bounds), resolution);

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

List<LevelSegment> marchingSquares(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax, {
  int resolution = marchingSquaresDefaultResolution,
}) {
  return _squaresCache.resolve(
    _marchKey(f, <double>[xMin, xMax, yMin, yMax], resolution),
    () => _marchingSquares(f, xMin, xMax, yMin, yMax, resolution),
  );
}

List<LevelSegment> _marchingSquares(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  int resolution,
) {
  if (!f.isValid || xMax <= xMin || yMax <= yMin) {
    return const <LevelSegment>[];
  }

  final double dx = (xMax - xMin) / resolution;
  final double dy = (yMax - yMin) / resolution;

  // Sample the corner lattice once; every cell reuses its neighbours' corners.
  final List<List<double>> v = <List<double>>[
    for (int i = 0; i <= resolution; i++)
      <double>[
        for (int j = 0; j <= resolution; j++)
          f.evaluate(xMin + i * dx, yMin + j * dy),
      ],
  ];

  final List<LevelSegment> out = <LevelSegment>[];

  for (int i = 0; i < resolution; i++) {
    for (int j = 0; j < resolution; j++) {
      final double f00 = v[i][j];
      final double f10 = v[i + 1][j];
      final double f11 = v[i + 1][j + 1];
      final double f01 = v[i][j + 1];
      if (!f00.isFinite || !f10.isFinite || !f11.isFinite || !f01.isFinite) {
        continue;
      }

      final double x0 = xMin + i * dx;
      final double x1 = xMin + (i + 1) * dx;
      final double y0 = yMin + j * dy;
      final double y1 = yMin + (j + 1) * dy;

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
        final double t = _crossing(fa, fb);
        hits.add((x: ax + (bx - ax) * t, y: ay + (by - ay) * t));
      }

      edge(f00, f10, x0, y0, x1, y0); // bottom
      edge(f10, f11, x1, y0, x1, y1); // right
      edge(f11, f01, x1, y1, x0, y1); // top
      edge(f01, f00, x0, y1, x0, y0); // left

      // Two crossings is one segment. Four is a saddle, where the cell is
      // genuinely ambiguous — either pairing is a valid curve, so pair them
      // in walk order rather than pretending one reading is correct.
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
}) {
  return _tetsCache.resolve(
    _marchKey(f, <double>[xMin, xMax, yMin, yMax, zMin, zMax], resolution),
    () =>
        _marchingTetrahedra(f, xMin, xMax, yMin, yMax, zMin, zMax, resolution),
  );
}

List<LevelTriangle> _marchingTetrahedra(
  PlotExpression f,
  double xMin,
  double xMax,
  double yMin,
  double yMax,
  double zMin,
  double zMax,
  int resolution,
) {
  if (!f.isValid ||
      xMax <= xMin ||
      yMax <= yMin ||
      zMax <= zMin ||
      resolution < 1) {
    return const <LevelTriangle>[];
  }

  final double dx = (xMax - xMin) / resolution;
  final double dy = (yMax - yMin) / resolution;
  final double dz = (zMax - zMin) / resolution;

  // One sample per lattice point, shared by the eight cubes that touch it.
  final int n = resolution + 1;
  final List<double> samples = List<double>.filled(n * n * n, double.nan);
  int idx(int i, int j, int k) => (i * n + j) * n + k;
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      for (int k = 0; k < n; k++) {
        samples[idx(i, j, k)] = f.evaluate(
          xMin + i * dx,
          yMin + j * dy,
          zMin + k * dz,
        );
      }
    }
  }

  final List<LevelTriangle> out = <LevelTriangle>[];

  Point3D corner(int i, int j, int k) =>
      Point3D(xMin + i * dx, yMin + j * dy, zMin + k * dz);

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

  Point3D lerp(Point3D a, Point3D b, double fa, double fb) {
    final double t = _crossing(fa, fb);
    return Point3D(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }

  for (int i = 0; i < resolution; i++) {
    for (int j = 0; j < resolution; j++) {
      for (int k = 0; k < resolution; k++) {
        final List<Point3D> p = <Point3D>[];
        final List<double> fv = <double>[];
        bool usable = true;
        for (final List<int> o in cubeOffsets) {
          final double value = samples[idx(i + o[0], j + o[1], k + o[2])];
          if (!value.isFinite) {
            usable = false;
            break;
          }
          fv.add(value);
          p.add(corner(i + o[0], j + o[1], k + o[2]));
        }
        // A cube touching an undefined sample is skipped, leaving a hole
        // rather than a surface stitched across a singularity.
        if (!usable) continue;

        for (final List<int> t in tets) {
          final List<Point3D> below = <Point3D>[];
          final List<double> belowF = <double>[];
          final List<Point3D> above = <Point3D>[];
          final List<double> aboveF = <double>[];

          for (final int c in t) {
            if (fv[c] < 0) {
              below.add(p[c]);
              belowF.add(fv[c]);
            } else {
              above.add(p[c]);
              aboveF.add(fv[c]);
            }
          }

          if (below.isEmpty || above.isEmpty) continue; // no crossing

          if (below.length == 1 || above.length == 1) {
            // One corner cut off: the cut is a single triangle.
            final Point3D apex = below.length == 1 ? below[0] : above[0];
            final double apexF = below.length == 1 ? belowF[0] : aboveF[0];
            final List<Point3D> others = below.length == 1 ? above : below;
            final List<double> othersF = below.length == 1 ? aboveF : belowF;
            out.add((
              a: lerp(apex, others[0], apexF, othersF[0]),
              b: lerp(apex, others[1], apexF, othersF[1]),
              c: lerp(apex, others[2], apexF, othersF[2]),
            ));
          } else {
            // Two-two split: the cut is a quad, emitted as two triangles.
            final Point3D q0 = lerp(below[0], above[0], belowF[0], aboveF[0]);
            final Point3D q1 = lerp(below[0], above[1], belowF[0], aboveF[1]);
            final Point3D q2 = lerp(below[1], above[1], belowF[1], aboveF[1]);
            final Point3D q3 = lerp(below[1], above[0], belowF[1], aboveF[0]);
            out.add((a: q0, b: q1, c: q2));
            out.add((a: q0, b: q2, c: q3));
          }
        }
      }
    }
  }

  return out;
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
}) {
  if (!f.isValid || yMax <= yMin) return const <double>[];

  final List<double> roots = <double>[];
  void add(double y) {
    // Two samples either side of a root can both bisect to it.
    const double tol = 1e-7;
    for (final double seen in roots) {
      if ((seen - y).abs() <= tol * (1 + y.abs())) return;
    }
    roots.add(y);
  }

  double previousY = yMin;
  double previous = f.evaluate(x, yMin);
  if (previous == 0) add(yMin);

  for (int i = 1; i <= samples; i++) {
    final double y = yMin + (yMax - yMin) * i / samples;
    final double value = f.evaluate(x, y);

    if (value == 0) {
      add(y);
    } else if (previous.isFinite &&
        value.isFinite &&
        previous != 0 &&
        previous.isNegative != value.isNegative) {
      double lo = previousY;
      double hi = y;
      double atLo = previous;
      for (int step = 0; step < 60; step++) {
        final double mid = (lo + hi) / 2;
        final double atMid = f.evaluate(x, mid);
        if (!atMid.isFinite) break;
        if (atMid.isNegative == atLo.isNegative) {
          lo = mid;
          atLo = atMid;
        } else {
          hi = mid;
        }
      }
      add((lo + hi) / 2);
    }

    previousY = y;
    previous = value;
  }
  return roots;
}
