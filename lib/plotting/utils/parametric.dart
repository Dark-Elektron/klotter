import 'dart:math' as math;

import '../parsers/vector_field_parser.dart';
import 'plot_cache.dart';

/// A point on a parametric path or surface, in data coordinates.
typedef ParametricPoint = ({double x, double y, double z});

/// The span a parameter is swept over.
typedef ParameterRange = ({double min, double max});

/// The unit interval, which is what a parameter means before you decide
/// otherwise: u runs from one end of the thing to the other. Ranges that want
/// an angle say so — and the panel takes `2pi` as readily as `1`.
const ParameterRange defaultParameterRange = (min: 0.0, max: 1.0);

/// A full turn, the range an angular sweep usually wants.
const ParameterRange fullTurn = (min: 0.0, max: 2 * math.pi);

/// How many steps a curve is sampled at.
///
/// Fine enough that a circle of a few hundred pixels shows no corners; a
/// parametric curve is one pass, not a lattice, so this costs far less than
/// the surface grids do.
const int parametricCurveSteps = 400;

/// How many steps each way a parametric surface is swept at.
///
/// One figure, used whether the plot is moving or still. It used to drop to a
/// coarser grid under a finger, which is the usual bargain for a mesh with no
/// cache behind it — but a spin carries on after the finger has gone, so the
/// surface visibly thinned out and stayed thin until it came to rest.
///
/// Caching the sweep did not buy the finer grid back: sampling was never the
/// cost. Projecting the corners and sorting the triangles is, and that happens
/// every frame whatever is cached. So the resolution is set where a moving
/// frame is affordable and left there. Measured per frame on a CPU canvas:
/// 48 steps 12.5 ms, 64 steps 14.7 ms, 80 steps 25.1 ms, 96 steps 36.7 ms.
///
/// Losing the old still-frame 96 costs less than it sounds. What smooths a
/// parametric surface is shading it from averaged corner normals, not the
/// number of cells; the grid only decides how round the silhouette is.
const int parametricSurfaceSteps = 64;

/// Sweep [field] over its parameter and return the path.
///
/// Breaks are kept as nulls rather than dropped: a curve with a pole comes
/// back in pieces, and joining across the gap would draw a line through
/// somewhere the curve never goes.
List<ParametricPoint?> sampleParametricCurve(
  VectorFieldParser field, {
  ParameterRange u = defaultParameterRange,
  int steps = parametricCurveSteps,
}) {
  if (!field.isParametric || steps < 1) return const <ParametricPoint?>[];
  final List<ParametricPoint?> out = <ParametricPoint?>[];
  for (int i = 0; i <= steps; i++) {
    final double t = u.min + (u.max - u.min) * i / steps;
    out.add(_pointAt(field, t, 0));
  }
  return out;
}

/// Sweep [field] over both parameters, row by row in u.
///
/// The result is `(steps + 1)` rows of `(steps + 1)` points, so a renderer can
/// walk it as a quad mesh the same way it walks a height grid.
List<List<ParametricPoint?>> sampleParametricSurface(
  VectorFieldParser field, {
  ParameterRange u = defaultParameterRange,
  ParameterRange v = defaultParameterRange,
  int steps = parametricSurfaceSteps,
}) {
  if (!field.isParametric || steps < 1) return const <List<ParametricPoint?>>[];
  return <List<ParametricPoint?>>[
    for (int i = 0; i <= steps; i++)
      <ParametricPoint?>[
        for (int j = 0; j <= steps; j++)
          _pointAt(
            field,
            u.min + (u.max - u.min) * i / steps,
            v.min + (v.max - v.min) * j / steps,
          ),
      ],
  ];
}

/// The position at one parameter pair, or null where it is undefined.
///
/// A component the expression leaves out is zero, not a gap: `cos(u)x̂ +
/// sin(u)ŷ` is a circle in the plane z = 0, and treating the missing ẑ as
/// undefined would throw the whole curve away.
ParametricPoint? _pointAt(VectorFieldParser field, double u, double v) {
  double at(dynamic component) {
    if (component == null) return 0;
    final double value = component.evaluateAt(u: u, v: v) as double;
    return value;
  }

  final double x = at(field.xComponent);
  final double y = at(field.yComponent);
  final double z = at(field.zComponent);
  if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
  return (x: x, y: y, z: z);
}

/// The box a sampled path or surface occupies, for auto-ranging.
///
/// Null when nothing was defined anywhere, which is the honest answer for a
/// curve that never resolves.
({double x, double y, double z})? parametricExtent(
  Iterable<ParametricPoint?> points,
) {
  double mx = 0, my = 0, mz = 0;
  bool any = false;
  for (final ParametricPoint? p in points) {
    if (p == null) continue;
    any = true;
    mx = math.max(mx, p.x.abs());
    my = math.max(my, p.y.abs());
    mz = math.max(mz, p.z.abs());
  }
  return any ? (x: mx, y: my, z: mz) : null;
}

final PlotCache<List<List<ParametricPoint?>>> _surfaceCache =
    PlotCache<List<List<ParametricPoint?>>>(4);

final PlotCache<List<ParametricPoint?>> _curveCache =
    PlotCache<List<ParametricPoint?>>(6);

/// [sampleParametricSurface], remembered between frames.
///
/// A sweep depends on the expression and the parameter ranges and nothing
/// else — turning the camera does not move a single point of it. Without this
/// a spin re-evaluated the expression 9,409 times a frame, which is why the
/// mesh had to be thinned while the plot was moving and visibly coarsened
/// until it came to rest.
///
/// Keyed on the parser's identity, which is sound because it is rebuilt on
/// every edit: a new object means a new expression.
List<List<ParametricPoint?>> cachedParametricSurface(
  VectorFieldParser field, {
  ParameterRange u = defaultParameterRange,
  ParameterRange v = defaultParameterRange,
  int steps = parametricSurfaceSteps,
}) {
  final Object key = Object.hash(
    identityHashCode(field),
    u.min,
    u.max,
    v.min,
    v.max,
    steps,
  );
  return _surfaceCache.resolve(
    key,
    () => sampleParametricSurface(field, u: u, v: v, steps: steps),
  );
}

/// [sampleParametricCurve], remembered between frames, for the same reason.
List<ParametricPoint?> cachedParametricCurve(
  VectorFieldParser field, {
  ParameterRange u = defaultParameterRange,
  int steps = parametricCurveSteps,
}) {
  final Object key = Object.hash(identityHashCode(field), u.min, u.max, steps);
  return _curveCache.resolve(
    key,
    () => sampleParametricCurve(field, u: u, steps: steps),
  );
}
