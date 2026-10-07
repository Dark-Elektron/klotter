import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';

/// A tap on a 3D plot lands on what was drawn.
///
/// A traced line — r = f(θ) standing as a wall, ρ = f(θ, φ) — is tested
/// against its own triangles. Its equation, sampled, knows only the points
/// with a radius of zero or more and θ in one turn, so a tap on a part drawn
/// by a negative radius found nothing. And a sampled line is only hit where
/// its value passes through zero, not where it leaps over it.
void main() {
  final PlotCamera camera = PlotCamera(
    size: const Size(400, 400),
    rotationX: 0.6,
    rotationZ: 0.8,
    panX: 0,
    panY: 0,
    rangeX: 2,
    rangeY: 2,
    rangeZ: 2,
  );
  PlotExpression lit(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  test('r = −1 is the unit circle, and a tap finds its wall', () {
    // Sampled, r + 1 is never zero; traced, every point is on the circle.
    final PlotExpression circle = lit('r=-1');
    expect(circle.isPolarCurve, isTrue);
    for (final List<double> p in <List<double>>[
      <double>[1, 0, 0],
      <double>[0, 1, 0.5],
      <double>[-0.6, -0.8, -0.5],
    ]) {
      final SurfaceHit? hit = pickSurface(camera, <PlotExpression>[
        circle,
      ], camera.project(p[0], p[1], p[2]));
      expect(hit, isNotNull, reason: '$p');
      // On the drawn wall, which keeps within an eighth of a lattice cell
      // of the circle.
      expect(
        math.sqrt(hit!.x * hit.x + hit.y * hit.y),
        closeTo(1, 1e-2),
        reason: '$p',
      );
    }
  });

  test('ρ = −1 is the unit sphere, and a tap finds it', () {
    final PlotExpression sphere = lit('ρ=-1');
    expect(sphere.isSphericalSurface, isTrue);
    final SurfaceHit? hit = pickSurface(camera, <PlotExpression>[
      sphere,
    ], camera.project(0, 0, 0));
    expect(hit, isNotNull);
    final double r = math.sqrt(hit!.x * hit.x + hit.y * hit.y + hit.z * hit.z);
    // On the drawn mesh, which sits inside the true sphere by at most its
    // chords' sag.
    expect(r, closeTo(1, 5e-3));
  });

  test('a sampled polar equation is picked on the wall that was drawn', () {
    // r² = sin(3θ)/(3θ) is drawn one address at a time; solved along the ray
    // as one value it leapt between branches, so a tap is tested against the
    // triangles instead.
    final PlotExpression lobes = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'r^2='),
      FractionNode(
        num: <MathNode>[
          TrigNode(
            function: 'sin',
            argument: <MathNode>[LiteralNode(text: '3θ')],
          ),
        ],
        den: <MathNode>[LiteralNode(text: '3θ')],
      ),
    ]);
    expect(lobes.equationSheets, isNotEmpty);
    final List<LevelSegment> curve = marchingSquares(lobes, -2, 2, -2, 2);
    double offCurve(double x, double y) {
      double best = double.infinity;
      for (final LevelSegment s in curve) {
        final double dx = s.x2 - s.x1, dy = s.y2 - s.y1;
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

    for (final double theta in <double>[0.2, -0.2, 0.5]) {
      final double r = math.sqrt(math.sin(3 * theta) / (3 * theta));
      final SurfaceHit? hit = pickSurface(camera, <PlotExpression>[
        lobes,
      ], camera.project(r * math.cos(theta), r * math.sin(theta), 0.3));
      expect(hit, isNotNull, reason: 'θ = $theta');
      expect(offCurve(hit!.x, hit.y), lessThan(0.02), reason: 'θ = $theta');
    }
  });

  test('a tap on empty space finds nothing', () {
    expect(
      pickSurface(camera, <PlotExpression>[lit('r=-1')], const Offset(2, 2)),
      isNull,
    );
  });

  test('a sampled line is not hit where its value leaps over zero', () {
    // θ = π/4 stands as the plane through the z axis at 45°. Across the
    // half-plane where θ comes round from 2π to 0 the value used to change
    // sign without passing zero, and a tap there was reported as a hit on a
    // surface that is not drawn.
    final PlotExpression plane = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'θ='),
      FractionNode(
        num: <MathNode>[LiteralNode(text: 'π')],
        den: <MathNode>[LiteralNode(text: '4')],
      ),
    ]);
    for (final List<double> p in <List<double>>[
      <double>[1, 0, 0],
      <double>[1.5, 0, 0.8],
      <double>[0.4, 0, -1],
    ]) {
      final SurfaceHit? hit = pickSurface(camera, <PlotExpression>[
        plane,
      ], camera.project(p[0], p[1], p[2]));
      if (hit != null) {
        expect(hit.x, closeTo(hit.y, 1e-3), reason: 'hit off the plane: $p');
      }
    }
  });
}
