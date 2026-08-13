import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// An equation is a level set, not a height.
///
/// The '=' used to be dropped by the converter, so only the left side was
/// plotted: x²+y²=1 came out as a paraboloid with no error to say so.
void main() {
  group('equations become lhs - rhs', () {
    test('a circle vanishes on its own radius', () {
      final p = fn('xx+yy=1');
      expect(p.error, isNull);
      expect(p.isLevelSet, isTrue);

      // On the unit circle F = 0; inside negative, outside positive.
      expect(p.evaluate(1, 0), closeTo(0, 1e-12));
      expect(p.evaluate(0, 1), closeTo(0, 1e-12));
      expect(p.evaluate(0, 0), lessThan(0));
      expect(p.evaluate(2, 0), greaterThan(0));
    });

    test('a sphere vanishes on its own surface', () {
      final p = fn('xx+yy+zz=1');
      expect(p.error, isNull);
      expect(p.isLevelSet, isTrue);
      expect(p.isImplicitSurface, isTrue, reason: 'depends on z');

      expect(p.evaluate(1, 0, 0), closeTo(0, 1e-12));
      expect(p.evaluate(0, 0, 1), closeTo(0, 1e-12));
      expect(p.evaluate(0, 0, 0), closeTo(-1, 1e-12));
      expect(p.evaluate(1, 1, 1), closeTo(2, 1e-12));
    });

    test('a non-zero right side is subtracted, not ignored', () {
      // The old behaviour plotted the left side alone, so this was x²+y².
      final p = fn('xx+yy=4');
      expect(p.evaluate(2, 0), closeTo(0, 1e-12));
      expect(p.evaluate(0, 0), closeTo(-4, 1e-12));
    });

    test('an expression on the right is handled, not just a constant', () {
      // y = 2x  ->  y - 2x, zero along the line.
      final p = fn('y=2x');
      expect(p.isLevelSet, isTrue);
      expect(p.evaluate(1, 2), closeTo(0, 1e-12));
      expect(p.evaluate(3, 6), closeTo(0, 1e-12));
      expect(p.evaluate(1, 0), closeTo(-2, 1e-12));
    });

    test('the right side is parenthesised so its sign is not lost', () {
      // x = 1+1  must be x - (1+1), not x - 1 + 1.
      final p = fn('x=1+1');
      expect(p.evaluate(2, 0), closeTo(0, 1e-12));
      expect(p.evaluate(0, 0), closeTo(-2, 1e-12));
    });
  });

  group('a plain expression is unchanged', () {
    test('no equals means no level set', () {
      final p = fn('xx+yy');
      expect(p.isLevelSet, isFalse);
      expect(p.isImplicitSurface, isFalse);
      expect(p.evaluate(1, 1), closeTo(2, 1e-12));
    });

    test('a 2D level set is a curve, not a surface', () {
      expect(fn('xx+yy=1').isImplicitSurface, isFalse);
    });
  });

  group('malformed equations are refused', () {
    test('a missing side is an error rather than a guess', () {
      expect(fn('xx+yy=').isValid, isFalse);
      expect(fn('=1').isValid, isFalse);
    });

    test('an unknown variable is still caught', () {
      expect(fn('xx+qq=1').error, contains('unknown variable'));
    });
  });
}
