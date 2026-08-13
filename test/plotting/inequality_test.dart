import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// Relations, and what each one means on a plot.
///
/// An equation is a curve; an inequality is a region. Whether the boundary
/// belongs to the answer is drawn too — solid when it does, dashed when it
/// does not — so the operator has to survive compilation, not just the sides.
void main() {
  PlotExpression fn(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  group('the operator is recognised', () {
    test('each one compiles to its own relation', () {
      expect(fn('x=2').relation, PlotRelation.equal);
      expect(fn('x≥2').relation, PlotRelation.greaterEqual);
      expect(fn('x>2').relation, PlotRelation.greater);
      expect(fn('x≤2').relation, PlotRelation.lessEqual);
      expect(fn('x<2').relation, PlotRelation.less);
      expect(fn('x≠2').relation, PlotRelation.notEqual);
    });

    test('the ascii two-character forms work too', () {
      expect(fn('x>=2').relation, PlotRelation.greaterEqual);
      expect(fn('x<=2').relation, PlotRelation.lessEqual);
    });

    test('">=" is not read as ">" with a stray "="', () {
      final e = fn('x>=2');
      expect(e.relation, PlotRelation.greaterEqual);
      expect(e.isValid, isTrue, reason: e.error);
      // The right side is 2, so the boundary is at x = 2.
      expect(e.evaluate(2, 0).abs(), lessThan(1e-9));
    });

    test('an expression with no operator is not a relation', () {
      expect(fn('x^2').isLevelSet, isFalse);
      expect(fn('x^2').relation, PlotRelation.equal);
    });
  });

  group('what each relation draws', () {
    test('only an equation is a bare curve', () {
      expect(PlotRelation.equal.isRegion, isFalse);
      for (final r in PlotRelation.values.where(
        (r) => r != PlotRelation.equal,
      )) {
        expect(r.isRegion, isTrue, reason: '$r should shade');
      }
    });

    test('strict relations exclude their boundary', () {
      expect(PlotRelation.greaterEqual.includesBoundary, isTrue);
      expect(PlotRelation.lessEqual.includesBoundary, isTrue);
      expect(PlotRelation.equal.includesBoundary, isTrue);
      expect(PlotRelation.greater.includesBoundary, isFalse);
      expect(PlotRelation.less.includesBoundary, isFalse);
      expect(PlotRelation.notEqual.includesBoundary, isFalse);
    });
  });

  group('which side is shaded', () {
    test('x ≥ 2 holds to the right of the line and on it', () {
      final e = fn('x≥2');
      bool at(double x) => e.relation.holds(e.evaluate(x, 0));
      expect(at(3), isTrue);
      expect(at(2), isTrue, reason: 'the boundary is included');
      expect(at(1), isFalse);
    });

    test('x > 2 excludes the line itself', () {
      final e = fn('x>2');
      expect(e.relation.holds(e.evaluate(2, 0)), isFalse);
      expect(e.relation.holds(e.evaluate(2.001, 0)), isTrue);
    });

    test('x² + y² < 4 is the open disc', () {
      final e = fn('x^2+y^2<4');
      bool at(double x, double y) => e.relation.holds(e.evaluate(x, y));
      expect(at(0, 0), isTrue);
      expect(at(1.9, 0), isTrue);
      expect(at(2, 0), isFalse, reason: 'the rim is excluded');
      expect(at(3, 0), isFalse);
    });

    test('a non-finite sample satisfies nothing', () {
      expect(PlotRelation.greater.holds(double.nan), isFalse);
      expect(PlotRelation.less.holds(double.nan), isFalse);
      expect(PlotRelation.notEqual.holds(double.nan), isFalse);
    });
  });
}
