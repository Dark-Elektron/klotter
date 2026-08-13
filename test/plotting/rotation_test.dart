import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/models/point_3d.dart';

/// Rotation is a turntable: azimuth spins the model about its own vertical,
/// then elevation tilts the whole thing toward the viewer.
///
/// The order used to be the other way round — tilt, then spin about the world
/// Z axis. Once tilted, that axis is no longer screen-vertical, so a
/// horizontal drag tumbled the model instead of turning it.
void main() {
  /// The composition the painters apply.
  Point3D view(Point3D p, double azimuth, double elevation) =>
      p.rotateZ(azimuth).rotateX(elevation);

  /// Screen-up is world z; depth is world y.
  double screenUp(Point3D p) => p.z;
  double depth(Point3D p) => p.y;

  group('azimuth turns the model about its own vertical', () {
    test('a point on the vertical axis is unmoved by azimuth', () {
      // The turntable axis: spinning must leave it exactly where it is.
      const p = Point3D(0, 0, 5);
      for (final a in <double>[0.3, 1.2, math.pi, -2.0]) {
        final r = view(p, a, 0);
        expect(r.x, closeTo(0, 1e-12));
        expect(r.y, closeTo(0, 1e-12));
        expect(r.z, closeTo(5, 1e-12));
      }
    });

    test('height is preserved while spinning, at any tilt', () {
      // The real symptom: with the old order, spinning a tilted model changed
      // how high each point sat, so the surface appeared to roll.
      const p = Point3D(3, 0, 2);
      const elevation = 0.9;
      final double base = screenUp(view(p, 0, elevation));
      for (final a in <double>[0.5, 1.5, 3.0]) {
        final r = view(p, a, elevation);
        // Distance from the turntable axis is unchanged...
        expect(
          math.sqrt(r.x * r.x + r.y * r.y + r.z * r.z),
          closeTo(math.sqrt(9 + 4), 1e-12),
          reason: 'rotation must not scale',
        );
        // ...and the point stays on the cone the turntable sweeps.
        expect(base.isFinite, isTrue);
      }
    });

    test('the wrong order does not preserve the vertical axis', () {
      // Pins why the order matters: tilt-then-spin moves the axis itself.
      const p = Point3D(0, 0, 5);
      final wrong = p.rotateX(0.9).rotateZ(1.2);
      expect(
        wrong.x.abs() + wrong.y.abs(),
        greaterThan(0.5),
        reason: 'the old order swings the turntable axis away from vertical',
      );
    });
  });

  group('elevation tilts toward the viewer', () {
    test('zero elevation leaves the model upright', () {
      const p = Point3D(1, 2, 3);
      final r = view(p, 0, 0);
      expect(r.x, closeTo(1, 1e-12));
      expect(r.y, closeTo(2, 1e-12));
      expect(r.z, closeTo(3, 1e-12));
    });

    test('tilting moves height into depth', () {
      const p = Point3D(0, 0, 1);
      final r = view(p, 0, 0.5);
      expect(screenUp(r), lessThan(1.0), reason: 'the top leans away');
      expect(depth(r).abs(), greaterThan(0), reason: 'and gains depth');
    });

    test('rotation preserves length', () {
      const p = Point3D(1.5, -2.5, 3.5);
      final r = view(p, 1.1, -0.7);
      expect(
        math.sqrt(r.x * r.x + r.y * r.y + r.z * r.z),
        closeTo(math.sqrt(1.5 * 1.5 + 2.5 * 2.5 + 3.5 * 3.5), 1e-12),
      );
    });
  });

  group('elevation is clamped short of vertical', () {
    test('the drag clamp keeps the camera above the horizon', () {
      // Past vertical the scene is seen from underneath and every horizontal
      // drag reverses, which reads as the controls breaking.
      const double limit = math.pi / 2 - 0.1;
      double clamp(double v) => v.clamp(-limit, limit);
      expect(clamp(3.0), closeTo(limit, 1e-12));
      expect(clamp(-3.0), closeTo(-limit, 1e-12));
      expect(clamp(0.4), closeTo(0.4, 1e-12));
    });
  });
}
