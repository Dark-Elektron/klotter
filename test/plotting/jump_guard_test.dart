import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// A change of sign between two samples is only a crossing if f passes
/// through zero there.
///
/// It can also leap over zero — at a pole, at a step, or where θ comes round
/// from 2π to 0 — and marching used to draw every such leap as part of the
/// curve. `θ = π/4` grew a second ray where θ starts its turn, `z = θ` a wall
/// there, and a pole the lattice did not land on exactly drew the asymptote.
void main() {
  PlotExpression compile(List<MathNode> nodes) => PlotExpression.compile(nodes);
  PlotExpression lit(String s) => compile(<MathNode>[LiteralNode(text: s)]);
  MathNode frac(List<MathNode> num, List<MathNode> den) =>
      FractionNode(num: num, den: den);
  MathNode trig(String fn, String arg) =>
      TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: arg)]);

  /// Segments whose middle lies within [band] of the line x = [at] (when
  /// [vertical]) or y = [at], and on the given side of the other axis.
  int along(
    List<LevelSegment> segments, {
    required bool vertical,
    double at = 0,
    double band = 0.06,
    bool Function(double)? where,
  }) =>
      segments.where((LevelSegment s) {
        final double mx = (s.x1 + s.x2) / 2;
        final double my = (s.y1 + s.y2) / 2;
        final double off = vertical ? mx - at : my - at;
        final double on = vertical ? my : mx;
        return off.abs() < band && (where == null || where(on));
      }).length;

  test('θ = π/4 is the line through the origin, with nothing on the cut', () {
    final PlotExpression ray = compile(<MathNode>[
      LiteralNode(text: 'θ='),
      frac(
        <MathNode>[LiteralNode(text: 'π')],
        <MathNode>[LiteralNode(text: '4')],
      ),
    ]);
    final List<LevelSegment> segments = marchingSquares(
      ray,
      -4,
      4,
      -4,
      4,
      resolution: 160,
    );
    // Where θ starts its turn: the positive x axis.
    expect(along(segments, vertical: false, where: (double x) => x > 0.05), 0);
    // The whole line, both sides of the origin: the half below it is
    // θ = π/4 with a negative radius, as in any polar plotter.
    for (final LevelSegment s in segments) {
      expect(s.x1, closeTo(s.y1, 1e-6));
    }
    expect(
      segments.where((LevelSegment s) => s.x1 > 0.1).length,
      greaterThan(100),
    );
    expect(
      segments.where((LevelSegment s) => s.x1 < -0.1).length,
      greaterThan(100),
    );
  });

  test('a pole the lattice does not land on is not drawn', () {
    // Written so it is sampled rather than traced: 2r = 2/cos θ is the line
    // x = 1, with a pole all down the y axis.
    final PlotExpression line = compile(<MathNode>[
      LiteralNode(text: '2r='),
      frac(<MathNode>[LiteralNode(text: '2')], <MathNode>[trig('cos', 'θ')]),
    ]);
    expect(line.isPolarCurve, isFalse);
    final List<LevelSegment> polar = marchingSquares(line, -4, 4, -4, 4);
    expect(along(polar, vertical: true), 0);
    expect(along(polar, vertical: true, at: 1), greaterThan(100));

    // The Cartesian pole of y = 1/x, in a window whose lattice misses x = 0.
    // On a symmetric window a sample lands on the pole, comes back infinite,
    // and the cell is skipped — which is the only reason it ever looked
    // right.
    final PlotExpression hyperbola = compile(<MathNode>[
      LiteralNode(text: 'y='),
      frac(
        <MathNode>[LiteralNode(text: '1')],
        <MathNode>[LiteralNode(text: 'x')],
      ),
    ]);
    final List<LevelSegment> cartesian = marchingSquares(
      hyperbola,
      -4,
      4.13,
      -4,
      4,
    );
    expect(along(cartesian, vertical: true), 0);
    expect(cartesian.length, greaterThan(100));
  });

  test('z = θ is the helicoid, both blades, with no wall where θ starts '
      'its turn', () {
    final List<LevelTriangle> surface = marchingTetrahedra(
      lit('z=θ'),
      -2,
      2,
      -2,
      2,
      -1,
      7,
      resolution: 30,
      refine: false,
    );
    expect(surface, isNotEmpty);
    // Every triangle lies on the helicoid: at its own angle, z = θ give or
    // take a whole number of half-turns — whole turns from θ's range, odd
    // half-turns from the blade a negative radius sweeps. A wall on the cut
    // would stand at θ = 0 at every height in between.
    bool otherBlade = false;
    for (final LevelTriangle t in surface) {
      final double x = (t.a.x + t.b.x + t.c.x) / 3;
      final double y = (t.a.y + t.b.y + t.c.y) / 3;
      final double z = (t.a.z + t.b.z + t.c.z) / 3;
      if (math.sqrt(x * x + y * y) < 0.3) continue; // θ turns fast by the axis
      final double halfTurns = (z - math.atan2(y, x)) / math.pi;
      final double miss = (halfTurns - halfTurns.roundToDouble()).abs();
      expect(miss * math.pi, lessThan(0.25));
      if (halfTurns.round().isOdd) otherBlade = true;
    }
    expect(otherBlade, isTrue);
  });

  test('the trace reports roots, not jumps or poles', () {
    final PlotExpression ray = compile(<MathNode>[
      LiteralNode(text: 'θ='),
      frac(
        <MathNode>[LiteralNode(text: 'π')],
        <MathNode>[LiteralNode(text: '4')],
      ),
    ]);
    final List<double> ys = levelSetYAt(ray, 1, -4, 4);
    expect(ys, hasLength(1));
    expect(ys.single, closeTo(1, 1e-6));

    // x = 1/y crosses x = 2 at y = 1/2, and has a pole at y = 0 that the
    // bisection used to settle on as a second root.
    final PlotExpression pole = compile(<MathNode>[
      LiteralNode(text: 'x='),
      frac(
        <MathNode>[LiteralNode(text: '1')],
        <MathNode>[LiteralNode(text: 'y')],
      ),
    ]);
    final List<double> at = levelSetYAt(pole, 2, -4, 4.13);
    expect(at, hasLength(1));
    expect(at.single, closeTo(0.5, 1e-6));
  });

  test('smooth curves and surfaces lose nothing', () {
    // Every edge of a circle changes sign through a root, so all of them are
    // kept: the curve closes, and every piece of it is on the circle.
    final List<LevelSegment> circle = marchingSquares(
      lit('x^2+y^2=1'),
      -2,
      2,
      -2,
      2,
    );
    double turned = 0;
    for (final LevelSegment s in circle) {
      expect(math.sqrt(s.x1 * s.x1 + s.y1 * s.y1), closeTo(1, 2e-3));
      turned += math.sqrt(
        math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2).toDouble(),
      );
    }
    expect(turned, closeTo(2 * math.pi, 1e-2));

    final List<LevelTriangle> sphere = marchingTetrahedra(
      lit('x^2+y^2+z^2=1'),
      -1.5,
      1.5,
      -1.5,
      1.5,
      -1.5,
      1.5,
      resolution: 20,
    );
    double area = 0;
    for (final LevelTriangle t in sphere) {
      final double ux = t.b.x - t.a.x, uy = t.b.y - t.a.y, uz = t.b.z - t.a.z;
      final double vx = t.c.x - t.a.x, vy = t.c.y - t.a.y, vz = t.c.z - t.a.z;
      final double cx = uy * vz - uz * vy;
      final double cy = uz * vx - ux * vz;
      final double cz = ux * vy - uy * vx;
      area += math.sqrt(cx * cx + cy * cy + cz * cz) / 2;
    }
    expect(area, closeTo(4 * math.pi, 0.15), reason: 'a closed sphere');
  });
}
