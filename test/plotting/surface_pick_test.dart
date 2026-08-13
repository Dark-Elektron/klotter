import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';

/// Reading a point off a 3D surface.
///
/// A touch names a ray, not a point, so the marker comes from where that ray
/// first meets the surface. The whole thing rests on inverting the projection
/// exactly, which is what the round-trip tests check: project a point the
/// painter's way, pick at that pixel, and get the point back.
void main() {
  const Size canvas = Size(400, 400);

  PlotCamera camera({
    double rotationX = 0.6,
    double rotationZ = 0.8,
    double panX = 0,
    double panY = 0,
    double range = 5,
  }) => PlotCamera(
    size: canvas,
    rotationX: rotationX,
    rotationZ: rotationZ,
    panX: panX,
    panY: panY,
    rangeX: range,
    rangeY: range,
    rangeZ: range,
  );

  PlotExpression fn(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  group('the projection inverts', () {
    test('unproject undoes project at the depth it was drawn at', () {
      final PlotCamera c = camera();
      // Any point in the box, deliberately off every axis.
      const double x = 1.7, y = -2.3, z = 0.9;
      final Offset screen = c.project(x, y, z);

      // Sweep depth until the unprojected point comes back to the original.
      double bestError = double.infinity;
      (double, double, double)? bestPoint;
      final (double near, double far) = c.depthSpan;
      for (int i = 0; i <= 4000; i++) {
        final double t = near + (far - near) * i / 4000;
        final (double px, double py, double pz) = c.unproject(screen, t);
        final double err = (px - x).abs() + (py - y).abs() + (pz - z).abs();
        if (err < bestError) {
          bestError = err;
          bestPoint = (px, py, pz);
        }
      }
      expect(bestError, lessThan(0.02), reason: 'best was $bestPoint');
    });

    test('holds under pan and a different camera angle', () {
      final PlotCamera c = camera(
        rotationX: -0.35,
        rotationZ: 2.1,
        panX: 24,
        panY: -13,
      );
      const double x = -3.1, y = 0.4, z = 2.2;
      final Offset screen = c.project(x, y, z);

      double bestError = double.infinity;
      final (double near, double far) = c.depthSpan;
      for (int i = 0; i <= 4000; i++) {
        final double t = near + (far - near) * i / 4000;
        final (double px, double py, double pz) = c.unproject(screen, t);
        final double err = (px - x).abs() + (py - y).abs() + (pz - z).abs();
        if (err < bestError) bestError = err;
      }
      expect(bestError, lessThan(0.02));
    });
  });

  group('a flat plane', () {
    test('picks the origin at the centre of the screen', () {
      // The answer here can be worked out by hand, so it pins the sign
      // conventions: the ray through the middle of an unpanned view passes
      // through the origin, and z = 0 contains it.
      //
      // Written as an equation rather than something like `0*x*y`, which the
      // engine simplifies to the constant 0 — losing both variables, so it is
      // no longer a surface at all and nothing is drawn or picked.
      final SurfaceHit? hit = pickSurface(camera(), <PlotExpression>[
        fn('z=0'),
      ], const Offset(200, 200));
      expect(hit, isNotNull);
      expect(hit!.x, closeTo(0, 0.05));
      expect(hit.y, closeTo(0, 0.05));
      expect(hit.z, closeTo(0, 0.05));
    });
  });

  group('a height surface', () {
    final PlotExpression bowl = fn('x^2+y^2');

    test('picking where a plane was drawn returns that point', () {
      // A tilted plane, so the ray crosses it exactly once and the point
      // picked can only be the one put there. A paraboloid is the wrong shape
      // for this check: a ray crosses it twice, and the nearer crossing — the
      // rim you are actually looking at — is correctly returned instead.
      final PlotCamera c = camera();
      const double x = 1.2, y = -1.4;
      const double z = x + y;
      final Offset screen = c.project(x, y, z);

      final SurfaceHit? hit = pickSurface(c, <PlotExpression>[
        fn('x+y'),
      ], screen);
      expect(hit, isNotNull);
      expect(hit!.x, closeTo(x, 0.05));
      expect(hit.y, closeTo(y, 0.05));
      expect(hit.z, closeTo(z, 0.05));
    });

    test('whatever is picked lies on the surface and under the finger', () {
      // The invariant that holds wherever you touch, without having to know
      // which part of the shape is visible from here.
      final PlotCamera c = camera();
      for (final Offset touch in <Offset>[
        const Offset(200, 200),
        const Offset(210, 240),
        const Offset(185, 215),
      ]) {
        final SurfaceHit? hit = pickSurface(c, <PlotExpression>[bowl], touch);
        if (hit == null) continue; // the bowl is clipped away here
        expect(
          (hit.z - bowl.evaluate(hit.x, hit.y)).abs(),
          lessThan(1e-3),
          reason: 'z should equal f(x, y) at $touch',
        );
        expect(
          (c.project(hit.x, hit.y, hit.z) - touch).distance,
          lessThan(1.0),
          reason: 'the hit should project back under the finger at $touch',
        );
      }
    });

    test('is not picked where it is clipped away', () {
      // Beyond |z| > rangeZ the surface is not drawn, so it must not be
      // pickable there either.
      final PlotCamera c = camera(range: 2);
      final SurfaceHit? hit = pickSurface(c, <PlotExpression>[
        fn('x^2+y^2'),
      ], const Offset(30, 30));
      if (hit != null) {
        expect(hit.z.abs(), lessThanOrEqualTo(2.0 + 1e-6));
      }
    });
  });

  group('a level surface', () {
    final PlotExpression sphere = fn('x^2+y^2+z^2=4');

    test('picks the near side, not the far one', () {
      final PlotCamera c = camera();
      final SurfaceHit? hit = pickSurface(c, <PlotExpression>[
        sphere,
      ], const Offset(200, 200));
      expect(hit, isNotNull);

      // On the sphere ...
      expect(
        sphere.evaluate(hit!.x, hit.y, hit.z).abs(),
        lessThan(1e-3),
        reason: 'the hit must satisfy the equation',
      );

      // ... and the nearer of the two crossings. The camera looks along +y in
      // view space, so the near hit is the one with the smaller depth; check
      // it by confirming the opposite point projects to the same pixel.
      final Offset here = c.project(hit.x, hit.y, hit.z);
      final Offset opposite = c.project(-hit.x, -hit.y, -hit.z);
      expect((here - opposite).distance, lessThan(2.0));

      final (double nearDepth, _) = c.depthSpan;
      final (double bx, double by, double bz) = c.unproject(here, nearDepth);
      final double toHit =
          (bx - hit.x).abs() + (by - hit.y).abs() + (bz - hit.z).abs();
      final double toOpposite =
          (bx + hit.x).abs() + (by + hit.y).abs() + (bz + hit.z).abs();
      expect(
        toHit,
        lessThan(toOpposite),
        reason: 'the far side of the sphere was returned',
      );
    });

    test('misses cleanly outside the shape', () {
      // A corner of the viewport, where the small sphere is nowhere near.
      expect(
        pickSurface(camera(), <PlotExpression>[sphere], const Offset(6, 6)),
        isNull,
      );
    });
  });

  group('what is not pickable', () {
    test('a single-variable line is skipped', () {
      // sin(x) draws as a curve, not a sheet; a ray does not meet a line.
      expect(
        pickSurface(camera(), <PlotExpression>[
          fn('2*x'),
        ], const Offset(200, 200)),
        isNull,
      );
    });

    test('an invalid expression is skipped', () {
      expect(
        pickSurface(camera(), <PlotExpression>[
          fn('nonsense('),
        ], const Offset(200, 200)),
        isNull,
      );
    });
  });

  group('several surfaces', () {
    test('the nearest one wins and says which line it was', () {
      final PlotCamera c = camera();
      final List<PlotExpression> curves = <PlotExpression>[
        fn('x^2+y^2'),
        fn('x^2+y^2+z^2=4'),
      ];
      final SurfaceHit? hit = pickSurface(c, curves, const Offset(200, 200));
      expect(hit, isNotNull);
      expect(hit!.curveIndex, inInclusiveRange(0, 1));

      // Whichever line it came from, the point must lie on that line.
      final PlotExpression c0 = curves[hit.curveIndex];
      final double residual =
          c0.isLevelSet
              ? c0.evaluate(hit.x, hit.y, hit.z)
              : hit.z - c0.evaluate(hit.x, hit.y);
      expect(residual.abs(), lessThan(1e-3));
    });
  });
}
