import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_extent.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// An explicit polar curve, r = f(θ), is traced by sweeping θ rather than by
/// sampling the equation.
///
/// Sampling asks of each point what its r and θ are, and gets one answer:
/// r ≥ 0, θ within one turn. A polar curve reaches points under other
/// addresses too — (−r, θ + π) above all — so sampled, r = cos 2θ lost two of
/// its four petals and the limaçon its inner loop. Swept, every θ is placed
/// where it belongs, negative r included.
void main() {
  PlotExpression compile(List<MathNode> nodes) => PlotExpression.compile(nodes);
  PlotExpression lit(String s) => compile(<MathNode>[LiteralNode(text: s)]);
  MathNode trig(String fn, String arg) =>
      TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: arg)]);

  /// How far (x, y) is from the nearest of [segments].
  double distanceTo(List<LevelSegment> segments, double x, double y) {
    double best = double.infinity;
    for (final LevelSegment s in segments) {
      final double dx = s.x2 - s.x1;
      final double dy = s.y2 - s.y1;
      final double len2 = dx * dx + dy * dy;
      final double t =
          len2 == 0
              ? 0
              : (((x - s.x1) * dx + (y - s.y1) * dy) / len2).clamp(0.0, 1.0);
      final double px = s.x1 + t * dx - x;
      final double py = s.y1 + t * dy - y;
      best = math.min(best, math.sqrt(px * px + py * py));
    }
    return best;
  }

  group('which lines are traced', () {
    test('r = f(θ), either way round, and a bare f(θ)', () {
      expect(lit('r=θ').isPolarCurve, isTrue);
      expect(lit('θ=r').isPolarCurve, isTrue);
      expect(lit('r=2').isPolarCurve, isTrue, reason: 'a circle');
      expect(
        compile(<MathNode>[
          LiteralNode(text: '1+'),
          trig('cos', 'θ'),
        ]).isPolarCurve,
        isTrue,
        reason: 'a bare f(θ) means r = f(θ)',
      );
    });

    test('anything else is still sampled', () {
      for (final String s in <String>[
        '2r=θ', // r is not on its own
        'r^2=θ',
        'r<θ', // a region
        'r=θz', // not a function of θ alone
        'x^2+y^2=1',
        'ρ=1',
      ]) {
        expect(lit(s).isPolarCurve, isFalse, reason: s);
      }
    });

    test('the equation still answers r − f(θ) where it is sampled', () {
      final PlotExpression e = lit('r=θ');
      expect(e.evaluate(0, 1), closeTo(1 - math.pi / 2, 1e-12));
    });
  });

  group('the whole curve is drawn', () {
    test('r = cos 2θ has all four petals', () {
      final List<LevelSegment> rose = marchingSquares(
        compile(<MathNode>[LiteralNode(text: 'r='), trig('cos', '2θ')]),
        -1.5,
        1.5,
        -1.5,
        1.5,
      );
      // Sampled, the petals on the y axis were missing: there r = cos 2θ is
      // negative, and the point lies on the opposite side of the origin.
      for (final List<double> tip in <List<double>>[
        <double>[1, 0],
        <double>[-1, 0],
        <double>[0, 1],
        <double>[0, -1],
      ]) {
        expect(
          distanceTo(rose, tip[0], tip[1]),
          lessThan(1e-3),
          reason: '$tip',
        );
      }
    });

    test('r = 1 + 2 cos θ has its inner loop', () {
      final List<LevelSegment> limacon = marchingSquares(
        compile(<MathNode>[LiteralNode(text: 'r=1+2'), trig('cos', 'θ')]),
        -4,
        4,
        -4,
        4,
      );
      expect(distanceTo(limacon, 3, 0), lessThan(1e-3), reason: 'outer loop');
      // θ = π gives r = −1, which is the point (1, 0).
      expect(distanceTo(limacon, 1, 0), lessThan(1e-3), reason: 'inner loop');
    });

    test('r = θ runs a turn either way from the origin', () {
      // θ from −2π to 2π. The negative half is the positive half mirrored in
      // the y axis: r and θ both change sign, so −θ lands at (−x, y).
      final List<LevelSegment> spiral = marchingSquares(
        lit('r=θ'),
        -7,
        7,
        -7,
        7,
      );
      expect(distanceTo(spiral, 0, -3 * math.pi / 2), lessThan(1e-3));
      expect(distanceTo(spiral, 2 * math.pi, 0), lessThan(1e-3));
      expect(distanceTo(spiral, -2 * math.pi, 0), lessThan(1e-3));
      for (final LevelSegment s in spiral) {
        expect(
          math.sqrt(s.x2 * s.x2 + s.y2 * s.y2),
          lessThan(2 * math.pi + 1e-9),
        );
      }
    });

    test('and only as far as the θ range says', () {
      final List<LevelSegment> oneTurn = marchingSquares(
        PlotExpression.compile(
          <MathNode>[LiteralNode(text: 'r=θ')],
          thetaRange: (min: 0, max: 2 * math.pi),
        ),
        -7,
        7,
        -7,
        7,
      );
      expect(distanceTo(oneTurn, 2 * math.pi, 0), lessThan(1e-3));
      expect(distanceTo(oneTurn, -2 * math.pi, 0), greaterThan(1));

      // Backwards is the same span.
      final PlotExpression backwards = PlotExpression.compile(
        <MathNode>[LiteralNode(text: 'r=θ')],
        thetaRange: (min: 2 * math.pi, max: 0),
      );
      expect(backwards.sweptThetaRange, (min: 0.0, max: 2 * math.pi));
    });

    test('sin(3θ)/(3θ) has both halves and its far side', () {
      // The case that came in from the phone. The function is the same at θ
      // and −θ, so the shape is symmetric about the x axis — but over 0 to 2π
      // alone only its top half was drawn.
      final List<LevelSegment> sinc = marchingSquares(
        compile(<MathNode>[
          LiteralNode(text: 'r='),
          FractionNode(
            num: <MathNode>[trig('sin', '3θ')],
            den: <MathNode>[LiteralNode(text: '3θ')],
          ),
        ]),
        -0.3,
        1.1,
        -0.6,
        0.6,
      );
      expect(distanceTo(sinc, 0.551, 0.318), lessThan(1e-3), reason: 'θ = π/6');
      expect(
        distanceTo(sinc, 0.551, -0.318),
        lessThan(1e-3),
        reason: 'θ = −π/6',
      );
      expect(
        distanceTo(sinc, 0, -0.212),
        lessThan(1e-3),
        reason: 'θ = π/2, where r = −0.212',
      );
    });

    test('a curve that repeats every turn is swept over one', () {
      // Over two turns it would be drawn twice, on top of itself.
      final PlotExpression rose = compile(<MathNode>[
        LiteralNode(text: 'r='),
        trig('cos', '2θ'),
      ]);
      final ({double min, double max}) swept = rose.sweptThetaRange;
      expect(swept.max - swept.min, closeTo(2 * math.pi, 1e-12));
      // One that does not repeat keeps the whole range.
      final PlotExpression half = compile(<MathNode>[
        LiteralNode(text: 'r='),
        trig('cos', 'θ/2'),
      ]);
      expect(half.sweptThetaRange, PlotExpression.defaultThetaRange);
    });

    test('a pole breaks the curve instead of being drawn across', () {
      // r = 1/cos θ is the line x = 1. At θ = π/2 r runs off to +∞ and comes
      // back from −∞, and joining the two would draw a segment down the
      // window far from the line.
      final List<LevelSegment> line = marchingSquares(
        compile(<MathNode>[
          LiteralNode(text: 'r='),
          FractionNode(
            num: <MathNode>[LiteralNode(text: '1')],
            den: <MathNode>[trig('cos', 'θ')],
          ),
        ]),
        -4,
        4,
        -4,
        4,
      );
      expect(line, isNotEmpty);
      for (final LevelSegment s in line) {
        expect(s.x1, closeTo(1, 1e-9));
        expect(s.x2, closeTo(1, 1e-9));
      }
      expect(distanceTo(line, 1, 3.9), lessThan(1e-3));
      expect(distanceTo(line, 1, -3.9), lessThan(1e-3));
    });

    test('in 3D the wall is thinned, not coarsened', () {
      // Cut 360 times a turn, every step a strip the height of the box, the
      // two turns of r = θ stood 28,800 triangles high — more than the
      // hyperboloid, the heaviest surface in the suite. The long gentle
      // stretches do not need the steps, and are thinned to within an eighth
      // of a lattice cell — but no step is left longer than a cell, or where
      // another surface crosses the wall a strip that wide sorts by a centre
      // far from the crossing, and shows as teeth down it.
      final List<LevelTriangle> wall = marchingTetrahedra(
        lit('r=θ'),
        -7,
        7,
        -7,
        7,
        -7,
        7,
      );
      expect(wall.length, lessThan(8000));

      // Still on the curve: where the wall meets the floor, every corner and
      // every point between corners lies close to r = θ.
      final List<({double x, double y})> dense = <({double x, double y})>[
        for (int i = 0; i <= 20000; i++)
          (() {
            final double t = -2 * math.pi + 4 * math.pi * i / 20000;
            return (x: t * math.cos(t), y: t * math.sin(t));
          })(),
      ];
      double offCurve(double x, double y) {
        double best = double.infinity;
        for (final ({double x, double y}) p in dense) {
          final double dx = p.x - x, dy = p.y - y;
          best = math.min(best, dx * dx + dy * dy);
        }
        return math.sqrt(best);
      }

      for (final LevelTriangle t in wall) {
        if (t.a.z != -7 || t.b.z != -7) continue;
        expect(offCurve(t.a.x, t.a.y), lessThan(0.02));
        expect(
          offCurve((t.a.x + t.b.x) / 2, (t.a.y + t.b.y) / 2),
          lessThan(14 / 40 / 8 + 0.02),
        );
      }
    });

    test('everything drawn stays inside the window', () {
      for (final LevelSegment s in marchingSquares(lit('r=θ'), -2, 2, -1, 1)) {
        for (final double x in <double>[s.x1, s.x2]) {
          expect(x, inInclusiveRange(-2 - 1e-9, 2 + 1e-9));
        }
        for (final double y in <double>[s.y1, s.y2]) {
          expect(y, inInclusiveRange(-1 - 1e-9, 1 + 1e-9));
        }
      }
    });
  });

  group('everything else that reads the curve agrees', () {
    final PlotExpression rose = compile(<MathNode>[
      LiteralNode(text: 'r='),
      trig('cos', '2θ'),
    ]);

    test('the trace finds the petals on the y axis', () {
      final List<double> ys = levelSetYAt(rose, 0, -1.5, 1.5);
      expect(ys.any((double y) => (y - 1).abs() < 1e-3), isTrue);
      expect(ys.any((double y) => (y + 1).abs() < 1e-3), isTrue);
    });

    test('held at x = 0, r = 1 is the two lines y = ±1', () {
      // In the box a curve in the plane is the wall standing on it, as
      // x² + y² = 1 is a cylinder.
      final List<LevelSegment> cut = marchingSquares(
        lit('r=1'),
        -2,
        2,
        -2,
        2,
        slice: const PlaneSlice(axis: SliceAxis.x),
      );
      expect(cut, hasLength(2));
      final List<double> at = <double>[for (final s in cut) s.x1]..sort();
      expect(at[0], closeTo(-1, 1e-3));
      expect(at[1], closeTo(1, 1e-3));
      for (final LevelSegment s in cut) {
        expect(s.y1, -2);
        expect(s.y2, 2);
      }
    });

    test('in 3D it is the wall on the whole curve, floor to ceiling', () {
      final List<LevelTriangle> wall = marchingTetrahedra(
        rose,
        -1.5,
        1.5,
        -1.5,
        1.5,
        -2,
        2,
      );
      expect(wall, isNotEmpty);
      double lowest = double.infinity, highest = double.negativeInfinity;
      bool reachesLowerPetal = false;
      for (final LevelTriangle t in wall) {
        for (final p in <dynamic>[t.a, t.b, t.c]) {
          final double x = p.x as double, y = p.y as double, z = p.z as double;
          lowest = math.min(lowest, z);
          highest = math.max(highest, z);
          if (x.abs() < 1e-3 && (y + 1).abs() < 1e-3) reachesLowerPetal = true;
          // Every vertex lies on the curve: r = |cos 2θ| at its own angle,
          // since a negative r is the same point seen from the other side.
          // At the origin there is no angle to speak of.
          final double r = math.sqrt(x * x + y * y);
          if (r < 1e-9) continue;
          final double theta = math.atan2(y, x);
          expect(r, closeTo(math.cos(2 * theta).abs(), 2e-2));
        }
      }
      expect(lowest, -2);
      expect(highest, 2);
      expect(reachesLowerPetal, isTrue);
    });

    test('framing takes the reach of the whole curve', () {
      final LevelExtent? frame = levelSetFraming(rose, volume: false);
      expect(frame, isNotNull);
      expect(frame!.x, closeTo(1.05, 0.02));
      expect(frame.y, closeTo(1.05, 0.02));
    });
  });
}
