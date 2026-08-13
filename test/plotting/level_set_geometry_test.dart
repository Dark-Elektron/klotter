import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// Contouring is checked against shapes whose answer is known exactly, so a
/// wrong lookup or a bad interpolation shows up as geometry that is off the
/// true surface rather than as something that merely "looks plausible".
void main() {
  group('marching squares traces a circle', () {
    final segments = marchingSquares(fn('xx+yy=1'), -2, 2, -2, 2);

    test('produces a curve at all', () {
      expect(segments, isNotEmpty);
    });

    test('every point lies on the unit circle', () {
      for (final s in segments) {
        expect(math.sqrt(s.x1 * s.x1 + s.y1 * s.y1), closeTo(1.0, 0.02));
        expect(math.sqrt(s.x2 * s.x2 + s.y2 * s.y2), closeTo(1.0, 0.02));
      }
    });

    test('the traced length is about the circumference', () {
      double total = 0;
      for (final s in segments) {
        total += math.sqrt(math.pow(s.x2 - s.x1, 2) + math.pow(s.y2 - s.y1, 2));
      }
      expect(total, closeTo(2 * math.pi, 0.1));
    });

    test('the curve spans all four quadrants', () {
      final quadrants = <int>{};
      for (final s in segments) {
        quadrants.add((s.x1 >= 0 ? 1 : 0) * 2 + (s.y1 >= 0 ? 1 : 0));
      }
      expect(quadrants.length, equals(4));
    });

    test('an equation with no solution yields nothing', () {
      // x²+y² = -1 never vanishes.
      expect(marchingSquares(fn('xx+yy=-1'), -2, 2, -2, 2), isEmpty);
    });

    test('a line is traced too', () {
      final line = marchingSquares(fn('y=2x'), -2, 2, -4, 4);
      expect(line, isNotEmpty);
      for (final s in line) {
        expect(s.y1, closeTo(2 * s.x1, 0.05));
      }
    });
  });

  group('marching tetrahedra traces a sphere', () {
    final tris = marchingTetrahedra(fn('xx+yy+zz=1'), -2, 2, -2, 2, -2, 2);

    test('produces a surface at all', () {
      expect(tris, isNotEmpty);
    });

    test('every vertex lies on the unit sphere', () {
      double worst = 0;
      for (final t in tris) {
        for (final p in <dynamic>[t.a, t.b, t.c]) {
          final r = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
          worst = math.max(worst, (r - 1.0).abs());
        }
      }
      expect(worst, lessThan(0.05), reason: 'vertices off the true sphere');
    });

    test('the surface encloses the origin on all six sides', () {
      double minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0;
      for (final t in tris) {
        for (final p in <dynamic>[t.a, t.b, t.c]) {
          minX = math.min(minX, p.x as double);
          maxX = math.max(maxX, p.x as double);
          minY = math.min(minY, p.y as double);
          maxY = math.max(maxY, p.y as double);
          minZ = math.min(minZ, p.z as double);
          maxZ = math.max(maxZ, p.z as double);
        }
      }
      expect(minX, closeTo(-1, 0.1));
      expect(maxX, closeTo(1, 0.1));
      expect(minY, closeTo(-1, 0.1));
      expect(maxY, closeTo(1, 0.1));
      expect(minZ, closeTo(-1, 0.1));
      expect(maxZ, closeTo(1, 0.1));
    });

    test('total area approximates 4πr²', () {
      double area = 0;
      for (final t in tris) {
        final ux = t.b.x - t.a.x, uy = t.b.y - t.a.y, uz = t.b.z - t.a.z;
        final vx = t.c.x - t.a.x, vy = t.c.y - t.a.y, vz = t.c.z - t.a.z;
        final cx = uy * vz - uz * vy;
        final cy = uz * vx - ux * vz;
        final cz = ux * vy - uy * vx;
        area += 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz);
      }
      // A faceted sphere slightly under-measures the true area.
      expect(area, closeTo(4 * math.pi, 0.6));
    });

    test('a radius-2 sphere scales accordingly', () {
      final big = marchingTetrahedra(fn('xx+yy+zz=4'), -3, 3, -3, 3, -3, 3);
      expect(big, isNotEmpty);
      for (final t in big) {
        final r = math.sqrt(t.a.x * t.a.x + t.a.y * t.a.y + t.a.z * t.a.z);
        expect(r, closeTo(2.0, 0.12));
      }
    });

    test('a box far larger than the shape still finds it', () {
      // The default view is x,y,z in [-5,5]; a unit sphere must still appear.
      final t = marchingTetrahedra(fn('xx+yy+zz=1'), -5, 5, -5, 5, -5, 5);
      expect(t, isNotEmpty);
      for (final tri in t) {
        final r = math.sqrt(
          tri.a.x * tri.a.x + tri.a.y * tri.a.y + tri.a.z * tri.a.z,
        );
        expect(r, closeTo(1.0, 0.2));
      }
    });

    test('the shape survives the default view box', () {
      // The 3D view defaults to x,y,z in [-5,5]. Auto-z-scaling used to stretch
      // that to about ±59 for a level set, because it scaled z by max|F| and F
      // is not a height — for x²+y²+z²=1 over [-5,5], max|F| is 49. The guard
      // in _computeAutoZRange keeps the box proportionate.
      final fitted = marchingTetrahedra(fn('xx+yy+zz=1'), -5, 5, -5, 5, -5, 5);
      expect(fitted, isNotEmpty);
      for (final tri in fitted) {
        final r = math.sqrt(
          tri.a.x * tri.a.x + tri.a.y * tri.a.y + tri.a.z * tri.a.z,
        );
        expect(r, closeTo(1.0, 0.2));
      }
    });

    test('an equation with no solution yields nothing', () {
      expect(
        marchingTetrahedra(fn('xx+yy+zz=-1'), -2, 2, -2, 2, -2, 2),
        isEmpty,
      );
    });

    test('a degenerate box yields nothing rather than throwing', () {
      expect(marchingTetrahedra(fn('xx+yy+zz=1'), 0, 0, -2, 2, -2, 2), isEmpty);
    });
  });
}
