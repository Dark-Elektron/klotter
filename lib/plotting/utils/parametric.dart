import 'dart:math' as math;

import '../parsers/vector_field_parser.dart';

/// A point on a parametric path or surface, in data coordinates.
typedef ParametricPoint = ({double x, double y, double z});

/// The span a parameter is swept over.
///
/// A full turn by default, since most parametric curves worth typing close on
/// themselves over 0..2π — a circle, a cardioid, a Lissajous figure.
typedef ParameterRange = ({double min, double max});

const ParameterRange defaultParameterRange = (min: 0.0, max: 2 * math.pi);

/// How many steps a curve is sampled at.
///
/// Fine enough that a circle of a few hundred pixels shows no corners; a
/// parametric curve is one pass, not a lattice, so this costs far less than
/// the surface grids do.
const int parametricCurveSteps = 400;

/// How many steps each way a parametric surface is swept at.
const int parametricSurfaceSteps = 60;

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
