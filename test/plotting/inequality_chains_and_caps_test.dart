import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/point_3d.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_cache.dart';

/// Two things inequalities did not do.
///
/// A chain, `-1 < x < 2`, was split at its first comparison only and the
/// second was dropped by the converter: it plotted `-1 < 2x`, half a plane,
/// without a word. And in 3D a region was drawn as its boundary alone — a
/// skin, with nothing to say which side of it was the region.
void main() {
  PlotExpression fn(String text) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: text)]);

  /// Whether the region holds at a point.
  bool inside(PlotExpression e, double x, [double y = 0, double z = 0]) =>
      e.relation.holds(e.evaluate(x, y, z));

  group('a chain of comparisons', () {
    test('holds where every link does', () {
      final PlotExpression strip = fn('-1<x<2');
      expect(strip.isValid, isTrue, reason: strip.error);
      expect(strip.relation.isRegion, isTrue);
      expect(inside(strip, 0), isTrue);
      expect(inside(strip, 1.9), isTrue);
      expect(inside(strip, -2), isFalse, reason: 'left of -1');
      expect(inside(strip, 3), isFalse, reason: 'right of 2: was missed');
    });

    test('its boundary is every link\'s boundary', () {
      // The region's edge is where the largest link is zero: here x = -1 and
      // x = 2, and nothing in between.
      final PlotExpression strip = fn('-1<x<2');
      expect(strip.evaluate(-1).abs(), lessThan(1e-9));
      expect(strip.evaluate(2).abs(), lessThan(1e-9));
      expect(strip.evaluate(0.5), lessThan(0));
    });

    test('an annulus, a band between curves, a shell', () {
      final PlotExpression ring = fn('1<=x^2+y^2<=4');
      expect(ring.relation.includesBoundary, isTrue);
      expect(inside(ring, 1.5), isTrue);
      expect(inside(ring, 0.5), isFalse, reason: 'the hole');
      expect(inside(ring, 2.5), isFalse);

      final PlotExpression band = fn('x^2-3<y<x');
      expect(inside(band, 1, 0), isTrue);
      expect(inside(band, 1, 2), isFalse, reason: 'above y = x');
      expect(inside(band, 1, -2.5), isFalse, reason: 'below the parabola');

      final PlotExpression shell = fn('1<=x^2+y^2+z^2<=4');
      expect(shell.isImplicitSurface, isTrue);
      expect(inside(shell, 0, 0, 1.5), isTrue);
      expect(inside(shell, 0, 0, 0.5), isFalse);
    });

    test('either direction, and both at once', () {
      final PlotExpression down = fn('2>x>-1');
      expect(inside(down, 0), isTrue);
      expect(inside(down, 3), isFalse);
      expect(inside(down, -2), isFalse);
      // y below 1 and above x: two links facing opposite ways.
      final PlotExpression mixed = fn('x<y<1');
      expect(inside(mixed, 0, 0.5), isTrue);
      expect(inside(mixed, 0, 1.5), isFalse);
      expect(inside(mixed, 0.8, 0.5), isFalse);
    });

    test('strict only when every link is', () {
      expect(fn('-1<x<2').relation.includesBoundary, isFalse);
      expect(fn('-1<=x<2').relation.includesBoundary, isTrue);
    });

    test('an equals in a chain is refused rather than misread', () {
      final PlotExpression e = fn('0<x=1');
      expect(e.isValid, isFalse);
      expect(e.error, contains('chain'));
    });
  });

  group('a 3D region is closed where the box cuts it', () {
    setUp(releasePlotGeometry);

    /// How much of the plane z = [at] the triangles lying in it cover.
    ///
    /// Area, not a count: a marched surface meeting a wall leaves slivers
    /// lying in it along the line where it does, and a cap is a sheet.
    double onWall(LevelSurface s, double at) {
      double area = 0;
      for (final LevelTriangle t in s.triangles) {
        final List<Point3D> p = <Point3D>[t.a, t.b, t.c];
        if (!p.every((Point3D q) => (q.z - at).abs() < 1e-9)) continue;
        area +=
            ((p[1].x - p[0].x) * (p[2].y - p[0].y) -
                    (p[2].x - p[0].x) * (p[1].y - p[0].y))
                .abs() /
            2;
      }
      return area;
    }

    test('a rod is capped at the top and bottom of the box', () {
      final LevelSurface rod = marchedSurface(
        fn('x^2+y^2<1'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 20,
      );
      // A unit disc, give or take the lattice.
      expect(onWall(rod, 2), closeTo(3.14, 0.25), reason: 'no cap on top');
      expect(onWall(rod, -2), closeTo(3.14, 0.25), reason: 'no cap below');
      // And only over the rod: every cap vertex is inside the unit circle.
      for (final LevelTriangle t in rod.triangles) {
        for (final Point3D p in <Point3D>[t.a, t.b, t.c]) {
          if ((p.z - 2).abs() > 1e-9) continue;
          expect(p.x * p.x + p.y * p.y, lessThan(1.05), reason: '$p');
        }
      }
    });

    test('a surface that is not a region is not capped', () {
      final LevelSurface tube = marchedSurface(
        fn('x^2+y^2=1'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 20,
      );
      expect(onWall(tube, 2), lessThan(0.05));
    });

    test('a region inside the box needs no cap', () {
      final LevelSurface ball = marchedSurface(
        fn('x^2+y^2+z^2<=1'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 20,
      );
      expect(onWall(ball, 2), lessThan(0.05));
      expect(onWall(ball, -2), lessThan(0.05));
    });

    test('the side that is capped is the region\'s', () {
      // Below the saddle: the floor of the box is in the region everywhere,
      // its lid only where x² − y² reaches the top.
      final LevelSurface below = marchedSurface(
        fn('z<=x^2-y^2'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 20,
      );
      final LevelSurface above = marchedSurface(
        fn('z>=x^2-y^2'),
        -2,
        2,
        -2,
        2,
        -2,
        2,
        resolution: 20,
      );
      expect(onWall(below, -2), greaterThan(onWall(below, 2)));
      expect(onWall(above, 2), greaterThan(onWall(above, -2)));
    });
  });
}
