import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_extent.dart';

/// Framing an equation means finding where it is.
///
/// A level set has no height to measure, and sizing the box by `max|F|` is
/// worse than useless — for the unit sphere over ±5 that maximum is 74, asking
/// for a box thirty times too big. So home never framed these at all: a unit
/// circle sat as a dot in the middle of a ±5 window.
void main() {
  PlotExpression eq(String text) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: text),
    ]);
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isLevelSet, isTrue, reason: '$text is not an equation');
    return e;
  }

  test('a unit circle reaches about one', () {
    final LevelExtent? e = levelSetExtent(eq('x^2+y^2=1'), volume: false);
    expect(e, isNotNull, reason: 'the circle was not found at all');
    expect(e!.x, closeTo(1, 4), reason: 'x reach ${e.x}');
    expect(e.y, closeTo(1, 4));
  });

  test('a bigger circle reaches further', () {
    // The measure has to track the shape, not return a constant.
    final LevelExtent? small = levelSetExtent(eq('x^2+y^2=1'), volume: false);
    final LevelExtent? big = levelSetExtent(eq('x^2+y^2=64'), volume: false);
    expect(big!.x, greaterThan(small!.x * 3));
  });

  test('a unit sphere reaches about one on every axis', () {
    final LevelExtent? e = levelSetExtent(eq('x^2+y^2+z^2=1'));
    expect(e, isNotNull, reason: 'the sphere was not found');
    expect(e!.x, closeTo(1, 4));
    expect(e.z, closeTo(1, 4), reason: 'z reach ${e.z} — the sphere has depth');
  });

  test('a surface unbounded in z is framed by the axes that are bounded', () {
    // x²+y²=1 read in 3D is a cylinder: it runs the whole z window, so z never
    // narrows and its step stays at the probe's coarsest. That step used to be
    // added to every axis, which reported x as reaching 5 — wider than the ±5
    // box this was meant to improve on. Each axis is padded by its own step
    // now, so the bounded axes are framed properly and only z stays wide.
    final LevelExtent? e = levelSetExtent(eq('x^2+y^2=1'));
    expect(e, isNotNull, reason: 'the cylinder was not found at all');
    expect(e!.x, closeTo(1, 0.6), reason: 'x reach ${e.x}');
    expect(e.y, closeTo(1, 0.6), reason: 'y reach ${e.y}');
    // z is honestly wide: the surface really does run the whole window.
    expect(
      e.z,
      greaterThan(10),
      reason: 'z reach ${e.z} should span the probe',
    );
  });

  test('a surface that falls between the first lattice is still found', () {
    // Negative only in four lobes along the diagonals, none of which holds a
    // point of a lattice four units apart — so the first pass saw F positive
    // everywhere, reported nothing, and the surface was never framed.
    final LevelExtent? e = levelSetExtent(
      eq('x^4+y^4+z^4-2x^2-2y^2-2z^2+8xyz+1=0'),
    );
    expect(e, isNotNull, reason: 'the surface was not found at all');
    // Along (t, t, -t) it stays inside until t is about 3.5.
    for (final double reach in <double>[e!.x, e.y, e.z]) {
      expect(reach, inInclusiveRange(2.5, 5), reason: 'reach $e');
    }
  });

  test('an equation that is nowhere reports nothing', () {
    // No real solution, so there is nothing to frame and the caller should
    // keep whatever window it had.
    expect(levelSetExtent(eq('x^2+y^2=-1'), volume: false), isNull);
  });

  test('a height surface is refused', () {
    // It is not a level set, and it has its own fit that works.
    final PlotExpression h = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x^2+y^2'),
    ]);
    expect(h.isLevelSet, isFalse);
    expect(levelSetExtent(h), isNull);
  });

  group('framing an unbounded surface', () {
    // The extent of an unbounded surface is the edge of the probe, which is
    // true but no frame: two paraboloids touching at the origin were framed
    // sixty units across, a speck in the middle of the box.
    LevelExtent frame(String text) => levelSetFraming(eq(text))!;

    test('a bounded shape is framed by its reach, as before', () {
      final LevelExtent f = frame('x^2+y^2+z^2=1');
      final LevelExtent e = levelSetExtent(eq('x^2+y^2+z^2=1'))!;
      expect(f, e);
    });

    test('unbounded every way, through the origin: a few units', () {
      for (final String text in <String>[
        'x^4+z^4+2x^2z^2-3y(x^2+z^2)+2y^2=0', // paraboloids at their tips
        'x^2+y^2=z', // a paraboloid
        'x+y+z=0', // a plane
        'x^2+y^2-z^2=0', // a cone
      ]) {
        final LevelExtent f = frame(text);
        for (final double reach in <double>[f.x, f.y, f.z]) {
          expect(reach, closeTo(unboundedFrame, 0.01), reason: '$text: $f');
        }
      }
    });

    test('unbounded every way, away from the origin: it is kept in view', () {
      // The plane's nearest point is 17.3 from the origin.
      final LevelExtent plane = frame('x+y+z=30');
      expect(plane.x, inInclusiveRange(30, 40), reason: '$plane');
      // A hyperboloid's waist has radius 5, and is shown whole.
      final LevelExtent waist = frame('x^2+y^2-z^2=25');
      expect(waist.x, inInclusiveRange(8, 12), reason: '$waist');
    });

    test('unbounded one way: three times the bounded reach that way', () {
      // A unit cylinder is a stretch of tube, not a speck in a tall column.
      final LevelExtent tube = frame('x^2+y^2=1');
      expect(tube.x, closeTo(1.28, 0.1));
      expect(tube.z, closeTo(3 * tube.x, 0.3), reason: '$tube');
      // A plane parallel to the floor keeps its height and gets some floor.
      final LevelExtent floor = frame('z=0.5');
      expect(floor.z, lessThan(1), reason: '$floor');
      expect(floor.x, closeTo(unboundedFrame, 0.01), reason: '$floor');
    });
  });
}
