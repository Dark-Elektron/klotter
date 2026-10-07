import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_extent.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// An explicit spherical surface, ρ = f(θ, φ), is swept over its angles
/// rather than sampled, for the reason a polar curve is: sampled, ρ is never
/// negative and θ never leaves one turn, so parts of the surface were never
/// found.
void main() {
  PlotExpression compile(List<MathNode> nodes) => PlotExpression.compile(nodes);
  PlotExpression lit(String s) => compile(<MathNode>[LiteralNode(text: s)]);
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

  double area(List<LevelTriangle> triangles) {
    double sum = 0;
    for (final LevelTriangle t in triangles) {
      final double ux = t.b.x - t.a.x, uy = t.b.y - t.a.y, uz = t.b.z - t.a.z;
      final double vx = t.c.x - t.a.x, vy = t.c.y - t.a.y, vz = t.c.z - t.a.z;
      sum +=
          math.sqrt(
            math.pow(uy * vz - uz * vy, 2) +
                math.pow(uz * vx - ux * vz, 2) +
                math.pow(ux * vy - uy * vx, 2),
          ) /
          2;
    }
    return sum;
  }

  test('ρ = f(θ, φ) is swept; anything else is still sampled', () {
    expect(lit('ρ=1').isSphericalSurface, isTrue);
    expect(lit('ρ=θφ').isSphericalSurface, isTrue);
    expect(
      compile(<MathNode>[
        LiteralNode(text: '2'),
        trig('cos', 'φ'),
      ]).isSphericalSurface,
      isTrue,
      reason: 'a bare f(θ, φ) means ρ = f(θ, φ)',
    );
    for (final String s in <String>['ρ^2=1', 'ρ<1', '2ρ=φ', 'r=θ']) {
      expect(lit(s).isSphericalSurface, isFalse, reason: s);
    }
  });

  test('the unit sphere, swept, is the whole sphere and only once', () {
    final PlotExpression sphere = lit('ρ=1');
    // It repeats every turn, so two turns would draw it twice over itself.
    expect(
      sphere.sweptThetaRange.max - sphere.sweptThetaRange.min,
      closeTo(2 * math.pi, 1e-12),
    );
    final List<LevelTriangle> surface = marchingTetrahedra(
      sphere,
      -1.5,
      1.5,
      -1.5,
      1.5,
      -1.5,
      1.5,
    );
    expect(area(surface), closeTo(4 * math.pi, 0.05));
    for (final LevelTriangle t in surface) {
      for (final p in <dynamic>[t.a, t.b, t.c]) {
        final double r = math.sqrt(
          (p.x as double) * p.x + (p.y as double) * p.y + (p.z as double) * p.z,
        );
        expect(r, closeTo(1, 1e-9));
      }
    }
  });

  test('a box that cuts the surface cuts it cleanly', () {
    final List<LevelTriangle> surface = marchingTetrahedra(
      lit('ρ=1'),
      -0.5,
      0.5,
      -0.5,
      0.5,
      -0.5,
      1.5,
    );
    expect(surface, isNotEmpty);
    for (final LevelTriangle t in surface) {
      for (final p in <dynamic>[t.a, t.b, t.c]) {
        expect(p.x as double, inInclusiveRange(-0.5 - 1e-9, 0.5 + 1e-9));
        expect(p.y as double, inInclusiveRange(-0.5 - 1e-9, 0.5 + 1e-9));
        expect(p.z as double, inInclusiveRange(-0.5 - 1e-9, 1.5 + 1e-9));
      }
    }
  });

  test('a pole tears the surface rather than stretching across the box', () {
    // ρ = 1/cos φ is the plane z = 1. At φ = π/2 ρ runs off to +∞ and comes
    // back from −∞ on the other side, and the cells across that would join
    // the two edges of the plane straight through the middle of the box.
    final PlotExpression plane = compile(<MathNode>[
      LiteralNode(text: 'ρ='),
      FractionNode(
        num: <MathNode>[LiteralNode(text: '1')],
        den: <MathNode>[trig('cos', 'φ')],
      ),
    ]);
    final List<LevelTriangle> surface = marchingTetrahedra(
      plane,
      -2,
      2,
      -2,
      2,
      -2,
      2,
    );
    expect(surface, isNotEmpty);
    for (final LevelTriangle t in surface) {
      for (final p in <dynamic>[t.a, t.b, t.c]) {
        expect(p.z as double, closeTo(1, 1e-9));
      }
    }
  });

  group('cut by a plane, for the flat view', () {
    test('the unit sphere at z = 0 is the unit circle', () {
      final List<LevelSegment> cut = marchingSquares(lit('ρ=1'), -2, 2, -2, 2);
      expect(cut.length, greaterThan(100));
      for (final LevelSegment s in cut) {
        expect(math.sqrt(s.x1 * s.x1 + s.y1 * s.y1), closeTo(1, 1e-9));
      }
    });

    test('ρ = 2 cos φ held at z = 1 is the circle of radius 1', () {
      final List<LevelSegment> cut = marchingSquares(
        compile(<MathNode>[LiteralNode(text: 'ρ=2'), trig('cos', 'φ')]),
        -2,
        2,
        -2,
        2,
        slice: const PlaneSlice(offset: 1),
      );
      expect(cut, isNotEmpty);
      for (final LevelSegment s in cut) {
        expect(math.sqrt(s.x1 * s.x1 + s.y1 * s.y1), closeTo(1, 1e-3));
      }
    });

    test('ρ = sin(3θ)/(3θ) has its far side and its other half', () {
      // The case that came in from the phone: drawn as ρ, the loop where ρ is
      // negative and the half of the shape from negative θ were both missing.
      final PlotExpression sinc = compile(<MathNode>[
        LiteralNode(text: 'ρ='),
        FractionNode(
          num: <MathNode>[trig('sin', '3θ')],
          den: <MathNode>[LiteralNode(text: '3θ')],
        ),
      ]);
      final List<LevelSegment> cut = marchingSquares(
        sinc,
        -0.3,
        1.1,
        -0.6,
        0.6,
      );
      // θ = π/6 and its mirror θ = −π/6.
      expect(distanceTo(cut, 0.551, 0.318), lessThan(2e-3));
      expect(distanceTo(cut, 0.551, -0.318), lessThan(2e-3));
      // θ = π/2, where ρ = −0.212: through the origin, below it.
      expect(distanceTo(cut, 0, -0.212), lessThan(2e-3));
    });

    test('the trace reads the same cut', () {
      final List<double> ys = levelSetYAt(lit('ρ=1'), 0.6, -2, 2);
      expect(ys, hasLength(2));
      expect(ys.map((double y) => y.abs()), everyElement(closeTo(0.8, 1e-3)));
    });
  });

  test('framing takes the reach of the swept surface', () {
    final LevelExtent? frame = levelSetFraming(lit('ρ=1'));
    expect(frame, isNotNull);
    expect(frame!.x, closeTo(1.05, 0.02));
    expect(frame.y, closeTo(1.05, 0.02));
    expect(frame.z, closeTo(1.05, 0.02));
  });
}
