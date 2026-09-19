import 'dart:math';
import 'dart:typed_data';

import '../models/plane_slice.dart';
import '../models/point_3d.dart';
import '../parsers/plot_expression.dart';

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
final _MarchCache<LevelSurface> _tetsCache = _MarchCache<LevelSurface>(3);

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
double _solveCrossing(
  PlotExpression f,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double fa,
  double fb,
) {
  if (fa == 0) return 0;
  if (fb == 0) return 1;

  double t = _crossing(fa, fb);
  double lo = 0;
  double hi = 1;
  double atLo = fa;
  double atHi = fb;

  for (int step = 0; step < _crossingRefinements; step++) {
    final double v = f.evaluate(
      ax + (bx - ax) * t,
      ay + (by - ay) * t,
      az + (bz - az) * t,
    );
    // Undefined partway along, or already exact: keep the best t so far rather
    // than stepping somewhere arbitrary.
    if (!v.isFinite || v == 0) return t;

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
  return t;
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
    _marchKey(f, <double>[
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

  final double dx = (xMax - xMin) / resolution;
  final double dy = (yMax - yMin) / resolution;

  // Sample the corner lattice once; every cell reuses its neighbours' corners.
  final List<List<double>> v = <List<double>>[
    for (int i = 0; i <= resolution; i++)
      <double>[
        for (int j = 0; j <= resolution; j++)
          slice.sample(f, xMin + i * dx, yMin + j * dy) - iso,
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
    ).triangles;

/// The same march, with the surface normal at every vertex.
///
/// Separate from [marchingTetrahedra] only so that callers with no use for
/// normals keep reading as they did; both go through one cache, so asking for
/// the normals never marches anything twice.
LevelSurface marchedSurface(
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

LevelSurface _marchingTetrahedra(
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
    return (triangles: const <LevelTriangle>[], normals: Float32List(0));
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
  final List<double> normals = <double>[];

  Point3D corner(int i, int j, int k) =>
      Point3D(xMin + i * dx, yMin + j * dy, zMin + k * dz);

  // The surface normal is the gradient of f, and the lattice the marcher has
  // already sampled hands it over for nothing — a difference of neighbouring
  // samples, no further calls into the expression.
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
  final Float64List gradA = Float64List(3);
  final Float64List gradB = Float64List(3);

  void gradientAt(int i, int j, int k, Float64List into) {
    final double here = samples[idx(i, j, k)];
    into[0] = _slope(
      i > 0 ? samples[idx(i - 1, j, k)] : double.nan,
      here,
      i < n - 1 ? samples[idx(i + 1, j, k)] : double.nan,
      dx,
    );
    into[1] = _slope(
      j > 0 ? samples[idx(i, j - 1, k)] : double.nan,
      here,
      j < n - 1 ? samples[idx(i, j + 1, k)] : double.nan,
      dy,
    );
    into[2] = _slope(
      k > 0 ? samples[idx(i, j, k - 1)] : double.nan,
      here,
      k < n - 1 ? samples[idx(i, j, k + 1)] : double.nan,
      dz,
    );
  }

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

  // A crossing: where the surface cuts the edge between two cube corners, and
  // the normal there. Corners are named by their index into [cubeOffsets] so
  // that the lattice position — and so the gradient — can be recovered from
  // them; carrying `Point3D`s alone lost that.
  late int cubeI, cubeJ, cubeK;
  late List<Point3D> p;
  late List<double> fv;

  ({Point3D at, double nx, double ny, double nz}) crossing(int c1, int c2) {
    final double fa = fv[c1];
    final double fb = fv[c2];
    final Point3D a = p[c1];
    final Point3D b = p[c2];
    final double t = _solveCrossing(f, a.x, a.y, a.z, b.x, b.y, b.z, fa, fb);

    final List<int> o1 = cubeOffsets[c1];
    final List<int> o2 = cubeOffsets[c2];
    gradientAt(cubeI + o1[0], cubeJ + o1[1], cubeK + o1[2], gradA);
    gradientAt(cubeI + o2[0], cubeJ + o2[1], cubeK + o2[2], gradB);

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
    );
  }

  /// Keep a triangle and its three normals, each scaled to unit length.
  void emit(
    ({Point3D at, double nx, double ny, double nz}) a,
    ({Point3D at, double nx, double ny, double nz}) b,
    ({Point3D at, double nx, double ny, double nz}) c,
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

    for (final ({Point3D at, double nx, double ny, double nz}) v
        in <({Point3D at, double nx, double ny, double nz})>[a, b, c]) {
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

  for (int i = 0; i < resolution; i++) {
    for (int j = 0; j < resolution; j++) {
      for (int k = 0; k < resolution; k++) {
        p = <Point3D>[];
        fv = <double>[];
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
        cubeI = i;
        cubeJ = j;
        cubeK = k;

        for (final List<int> t in tets) {
          final List<int> below = <int>[];
          final List<int> above = <int>[];

          for (final int c in t) {
            if (fv[c] < 0) {
              below.add(c);
            } else {
              above.add(c);
            }
          }

          if (below.isEmpty || above.isEmpty) continue; // no crossing

          if (below.length == 1 || above.length == 1) {
            // One corner cut off: the cut is a single triangle.
            final int apex = below.length == 1 ? below[0] : above[0];
            final List<int> others = below.length == 1 ? above : below;
            emit(
              crossing(apex, others[0]),
              crossing(apex, others[1]),
              crossing(apex, others[2]),
            );
          } else {
            // Two-two split: the cut is a quad, emitted as two triangles.
            final q0 = crossing(below[0], above[0]);
            final q1 = crossing(below[0], above[1]);
            final q2 = crossing(below[1], above[1]);
            final q3 = crossing(below[1], above[0]);
            emit(q0, q1, q2);
            emit(q0, q2, q3);
          }
        }
      }
    }
  }

  return (triangles: out, normals: Float32List.fromList(normals));
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
  double valueAt(double h, double v) => slice.sample(f, h, v) - iso;

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
  double previous = valueAt(x, yMin);
  if (previous == 0) add(yMin);

  for (int i = 1; i <= samples; i++) {
    final double y = yMin + (yMax - yMin) * i / samples;
    final double value = valueAt(x, y);

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
        final double atMid = valueAt(x, mid);
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
