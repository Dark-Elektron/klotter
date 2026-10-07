import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// A sampled polar line is read at every address of a point, not only the
/// one with r ≥ 0 and θ in its first turn.
///
/// (r, θ), (r, θ + 2π) and (−r, θ + π) are one point. A traced curve reaches
/// it by any of them, so a sampled line that asked about only one disagreed
/// with the traced form of the same curve: `2r = θ` drew one arm where
/// `r = θ/2` drew two. Equations now take every address in the θ range;
/// inequalities every turn in the range but only r ≥ 0, which is the rule
/// Desmos keeps — with a negative radius allowed, `r < 1` holds everywhere.
void main() {
  PlotExpression lit(String s, {({double min, double max})? range}) =>
      PlotExpression.compile(<MathNode>[
        LiteralNode(text: s),
      ], thetaRange: range ?? PlotExpression.defaultThetaRange);
  MathNode trig(String fn, String arg) =>
      TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: arg)]);

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
      best = math.min(
        best,
        math.sqrt(
          math.pow(s.x1 + t * dx - x, 2) + math.pow(s.y1 + t * dy - y, 2),
        ),
      );
    }
    return best;
  }

  group('equations', () {
    test('2r = θ has both arms, as r = θ/2 does', () {
      final List<LevelSegment> spiral = marchingSquares(
        lit('2r=θ'),
        -4,
        4,
        -4,
        4,
      );
      // θ = π/4 and θ = −π/4, which is the first point mirrored in the y axis.
      expect(distanceTo(spiral, 0.2777, 0.2777), lessThan(2e-3));
      expect(distanceTo(spiral, -0.2777, 0.2777), lessThan(2e-3));
    });

    test('where its arms cross there is no gap', () {
      // θ = 3π/2 on one arm and θ = −3π/2 on the other both land on
      // (0, −3π/4). Read as one value, the nearest to zero, the curve
      // switched arms there in a leap and lost a few pixels either side.
      final List<LevelSegment> spiral = marchingSquares(
        lit('2r=θ'),
        -4,
        4,
        -4,
        4,
      );
      expect(distanceTo(spiral, 0, -3 * math.pi / 4), lessThan(2e-3));
      // And both arms run right up to it: the points of each a little way
      // either side of the crossing, inside where the gap used to be.
      for (final double t in <double>[3 * math.pi / 2, -3 * math.pi / 2]) {
        for (final double d in <double>[
          -0.03,
          -0.02,
          -0.01,
          0.01,
          0.02,
          0.03,
        ]) {
          final double theta = t + d;
          expect(
            distanceTo(
              spiral,
              theta / 2 * math.cos(theta),
              theta / 2 * math.sin(theta),
            ),
            lessThan(2e-3),
            reason: 'θ = $theta',
          );
        }
      }
    });

    test('θ = π/4 is a line through the origin', () {
      final List<LevelSegment> line = marchingSquares(
        PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'θ='),
          FractionNode(
            num: <MathNode>[LiteralNode(text: 'π')],
            den: <MathNode>[LiteralNode(text: '4')],
          ),
        ]),
        -2,
        2,
        -2,
        2,
      );
      expect(distanceTo(line, 1, 1), lessThan(1e-6));
      expect(distanceTo(line, -1, -1), lessThan(1e-6));
      for (final LevelSegment s in line) {
        expect(s.x1, closeTo(s.y1, 1e-6));
      }
    });

    test('a negative radius is a point on the far side', () {
      final List<LevelSegment> circle = marchingSquares(
        lit('2r=-2'),
        -2,
        2,
        -2,
        2,
      );
      expect(circle, isNotEmpty);
      for (final LevelSegment s in circle) {
        expect(math.sqrt(s.x1 * s.x1 + s.y1 * s.y1), closeTo(1, 1e-3));
      }
    });

    test('a line that reads alike at every address is read once', () {
      // r² = cos 2θ repeats every turn and does not care about the sign of r,
      // so nothing is gained by reading it more than once.
      final PlotExpression lemniscate = PlotExpression.compile(<MathNode>[
        LiteralNode(text: 'r^2='),
        trig('cos', '2θ'),
      ]);
      expect(lemniscate.equationSheets, isEmpty);
      expect(lit('2r=θ').equationSheets, isNotEmpty);
    });

    test('z = θ in the box is two turns of the helicoid', () {
      final List<LevelTriangle> surface = marchingTetrahedra(
        lit('z=θ'),
        -2,
        2,
        -2,
        2,
        -7,
        7,
        resolution: 30,
      );
      final double lowest = surface
          .map((LevelTriangle t) => t.a.z)
          .reduce(math.min);
      final double highest = surface
          .map((LevelTriangle t) => t.a.z)
          .reduce(math.max);
      expect(lowest, lessThan(-5.5));
      expect(highest, greaterThan(5.5));
    });

    test('φ = π/4 is both halves of the cone', () {
      final List<LevelTriangle> cone = marchingTetrahedra(
        PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'φ='),
          FractionNode(
            num: <MathNode>[LiteralNode(text: 'π')],
            den: <MathNode>[LiteralNode(text: '4')],
          ),
        ]),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 30,
      );
      expect(cone.any((LevelTriangle t) => t.a.z > 0.5), isTrue);
      expect(cone.any((LevelTriangle t) => t.a.z < -0.5), isTrue);
    });
  });

  group('in the box', () {
    PlotExpression sinc(String lhs) => PlotExpression.compile(<MathNode>[
      LiteralNode(text: '$lhs='),
      FractionNode(
        num: <MathNode>[trig('sin', '3θ')],
        den: <MathNode>[LiteralNode(text: '3θ')],
      ),
    ]);

    test('the wall on r² = sin(3θ)/(3θ) stands on the whole curve', () {
      // Marched through the box as one value standing for every address, it
      // had a slit wherever two branches meet — a third of the wall missing,
      // most of it round the origin where the small loops crowd together.
      final PlotExpression f = sinc('r^2');
      const double b = 2.5;
      final List<LevelSegment> curve = marchingSquares(f, -b, b, -b, b);
      final List<LevelTriangle> wall = marchingTetrahedra(
        f,
        -b,
        b,
        -b,
        b,
        -b,
        b,
      );
      // Where the wall meets z = 0.
      final List<LevelSegment> section = <LevelSegment>[];
      for (final LevelTriangle t in wall) {
        final List<({double x, double y})> hits = <({double x, double y})>[];
        final List<dynamic> corners = <dynamic>[t.a, t.b, t.c];
        for (int i = 0; i < 3; i++) {
          final dynamic p = corners[i];
          final dynamic q = corners[(i + 1) % 3];
          final double pz = p.z as double, qz = q.z as double;
          if ((pz < 0) == (qz < 0)) continue;
          final double s = pz / (pz - qz);
          hits.add((
            x: (p.x as double) + ((q.x as double) - (p.x as double)) * s,
            y: (p.y as double) + ((q.y as double) - (p.y as double)) * s,
          ));
        }
        if (hits.length == 2) {
          section.add((
            x1: hits[0].x,
            y1: hits[0].y,
            x2: hits[1].x,
            y2: hits[1].y,
          ));
        }
      }
      for (final LevelSegment s in curve) {
        expect(
          distanceTo(section, (s.x1 + s.x2) / 2, (s.y1 + s.y2) / 2),
          lessThan(0.05),
          reason: 'wall missing at (${s.x1}, ${s.y1})',
        );
      }
    });

    test('z = sin(3θ)/(3θ) is whole where its turns meet', () {
      // Its two turns are mirror images, and meet along the half-plane
      // θ = π. Each is marched on its own, so neither breaks off there.
      final List<LevelTriangle> surface = marchingTetrahedra(
        sinc('z'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
      );
      double toMesh(double x, double y, double z) {
        double best = double.infinity;
        for (final LevelTriangle t in surface) {
          final double cx = (t.a.x + t.b.x + t.c.x) / 3;
          final double cy = (t.a.y + t.b.y + t.c.y) / 3;
          final double cz = (t.a.z + t.b.z + t.c.z) / 3;
          final double d =
              (cx - x) * (cx - x) + (cy - y) * (cy - y) + (cz - z) * (cz - z);
          if (d < best) best = d;
        }
        return math.sqrt(best);
      }

      double g(double t) => math.sin(3 * t) / (3 * t);
      for (final double r in <double>[0.5, 1.0, 1.5]) {
        for (final double d in <double>[-0.06, -0.03, 0.03, 0.06]) {
          for (final double t in <double>[math.pi + d, -math.pi + d]) {
            expect(
              toMesh(r * math.cos(t), r * math.sin(t), g(t)),
              lessThan(0.06),
              reason: 'r = $r, θ = $t',
            );
          }
        }
      }
    });
  });

  group('inequalities', () {
    test('only a radius of zero or more counts', () {
      final PlotExpression disc = lit('r<1');
      expect(disc.evaluate(0.5, 0), lessThan(0));
      expect(disc.evaluate(3, 0), greaterThan(0));
    });

    test('a wedge either side of θ = 0 is whole', () {
      // While θ only ran from 0 to 2π this was its top half.
      final PlotExpression wedge = lit('-π/2<θ<π/2');
      expect(wedge.evaluate(1, 1), lessThan(0));
      expect(wedge.evaluate(1, -1), lessThan(0));
      expect(wedge.evaluate(-1, 0.5), greaterThan(0));
    });

    test('a one-sided bound holds wherever some θ in the range meets it', () {
      // Over the default two turns every direction has a θ below π/4 — the
      // negative ones — so θ < π/4 is everything. Over one turn from 0 it is
      // the wedge. Desmos, whose range starts at 0, does the same to θ > c.
      final PlotExpression below = lit('θ<π/4');
      expect(below.evaluate(-1, -1), lessThan(0));
      final PlotExpression wedge = lit(
        'θ<π/4',
        range: (min: 0, max: 2 * math.pi),
      );
      expect(wedge.evaluate(1, 0.5), lessThan(0));
      expect(wedge.evaluate(-1, -1), greaterThan(0));
    });

    test('r < θ over two turns from 0 covers both', () {
      final PlotExpression oneTurn = lit(
        'r<θ',
        range: (min: 0, max: 2 * math.pi),
      );
      final PlotExpression twoTurns = lit(
        'r<θ',
        range: (min: 0, max: 4 * math.pi),
      );
      // Out along θ = π/2 at r = 5: past the first turn's π/2, inside the
      // second's 5π/2.
      expect(oneTurn.evaluate(0, 5), greaterThan(0));
      expect(twoTurns.evaluate(0, 5), lessThan(0));
    });
  });

  test('a range that covers part of a turn confines the line to it', () {
    final PlotExpression half = lit('r<2', range: (min: 0, max: math.pi));
    expect(half.evaluate(0, 1), lessThan(0));
    expect(half.evaluate(0, -1).isNaN, isTrue);
  });
}
