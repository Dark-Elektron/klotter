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
}
