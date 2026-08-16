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

/// How many cells a parametric surface is drawn with, all directions
/// together.
///
/// A budget rather than a resolution, because the two parameters rarely
/// deserve the same treatment — see [parametricGridFor], which spends this on
/// whichever direction the surface actually moves in.
///
/// One figure, used whether the plot is moving or still. It used to drop to a
/// coarser grid under a finger, which is the usual bargain for a mesh with no
/// cache behind it — but a spin carries on after the finger has gone, so the
/// surface visibly thinned out and stayed thin until it came to rest.
///
/// Caching the sweep did not buy a finer grid: sampling was never the cost.
/// Projecting the corners and sorting the triangles is, and that happens every
/// frame whatever is cached. What did buy it was shading and projecting each
/// vertex once instead of once per cell that touches it — every interior
/// corner belongs to four. Measured per frame on a CPU canvas, after that:
/// 4,096 cells 12.0 ms, 9,216 cells 23.1 ms, 16,384 cells 40.6 ms.
const int parametricCellBudget = 8100;

/// Fallback resolution when the surface gives nothing to measure.
const int parametricSurfaceCells = 90;

/// A direction never gets fewer steps than this, however little it moves: two
/// steps is not a surface, and the shading needs neighbours to average.
const int parametricMinSteps = 12;

/// Nor more than this, however much it moves. Past here the cells are smaller
/// than a pixel and the only thing still growing is the frame time.
const int parametricMaxSteps = 400;

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
  int steps = 0,
  int? uSteps,
  int? vSteps,
}) {
  final int rows = uSteps ?? (steps > 0 ? steps : parametricSurfaceCells);
  final int cols = vSteps ?? (steps > 0 ? steps : parametricSurfaceCells);
  if (!field.isParametric || rows < 1 || cols < 1) {
    return const <List<ParametricPoint?>>[];
  }
  return <List<ParametricPoint?>>[
    for (int i = 0; i <= rows; i++)
      <ParametricPoint?>[
        for (int j = 0; j <= cols; j++)
          _pointAt(
            field,
            u.min + (u.max - u.min) * i / rows,
            v.min + (v.max - v.min) * j / cols,
          ),
      ],
  ];
}

/// How many steps to give each parameter, in proportion to how far the
/// surface actually travels along it.
///
/// One count for both was what made a spiral look like a stack of plates.
/// `sin(u)/v x̂ + cos(u)/v ŷ + √(u²+v²) ẑ` over `u ∈ [0, 35]` is five and a
/// half turns; sharing 64 steps between the two directions left eleven
/// samples per revolution, and eleven-sided circles are what you saw. The v
/// direction, meanwhile, barely moves and was being sampled just as finely.
///
/// The two are chosen so their product is [budget] and their ratio matches
/// the ratio of the distances travelled, which is the allocation that
/// minimises the worst gap for a fixed number of cells.
({int u, int v}) parametricGridFor(
  VectorFieldParser field, {
  ParameterRange u = defaultParameterRange,
  ParameterRange v = defaultParameterRange,
  int budget = parametricCellBudget,
}) {
  // A coarse probe first. Its own resolution hardly matters — this is
  // measuring which direction moves more, not how much.
  const int probe = 12;
  final List<List<ParametricPoint?>> sample = sampleParametricSurface(
    field,
    u: u,
    v: v,
    steps: probe,
  );
  if (sample.length < 2) {
    final int side = math.sqrt(budget).round();
    return (u: side, v: side);
  }

  double along(bool inU) {
    double total = 0;
    for (int a = 0; a <= probe; a++) {
      for (int b = 0; b < probe; b++) {
        final ParametricPoint? p = inU ? sample[b][a] : sample[a][b];
        final ParametricPoint? q = inU ? sample[b + 1][a] : sample[a][b + 1];
        if (p == null || q == null) continue;
        final double dx = q.x - p.x, dy = q.y - p.y, dz = q.z - p.z;
        total += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
    }
    return total;
  }

  final double lu = along(true), lv = along(false);
  // A degenerate direction still needs enough steps to be a surface.
  if (lu <= 0 || lv <= 0) {
    final int side = math.sqrt(budget).round();
    return (u: side, v: side);
  }

  final double ratio = lu / lv;
  final int uSteps = (math.sqrt(
    budget * ratio,
  )).round().clamp(parametricMinSteps, parametricMaxSteps);
  final int vSteps = (budget / uSteps).round().clamp(
    parametricMinSteps,
    parametricMaxSteps,
  );
  return (u: uSteps, v: vSteps);
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
}) {
  final ({int u, int v}) grid = parametricGridFor(field, u: u, v: v);
  final Object key = Object.hash(
    identityHashCode(field),
    u.min,
    u.max,
    v.min,
    v.max,
    grid.u,
    grid.v,
  );
  return _surfaceCache.resolve(
    key,
    () => sampleParametricSurface(
      field,
      u: u,
      v: v,
      uSteps: grid.u,
      vSteps: grid.v,
    ),
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
