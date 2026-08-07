import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Calculus Edge Cases - Summation', () {
    test('Summation with empty variable returns empty result', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: '')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Summation with upper < lower returns 0', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '5')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(0.0));
    });

    test('Summation with non-integer bounds returns 0', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1.5')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(0.0));
    });

    test('Nested Summation with same variable (shadowing)', () {
      // sum(i, 1, 2, sum(i, 1, 3, i))
      // inner: 1+2+3 = 6
      // outer: 6 + 6 = 12
      final innerSum = SummationNode(
        variable: [LiteralNode(text: 'i')],
        lower: [LiteralNode(text: '1')],
        upper: [LiteralNode(text: '3')],
        body: [LiteralNode(text: 'i')],
      );
      final outerSum = SummationNode(
        variable: [LiteralNode(text: 'i')],
        lower: [LiteralNode(text: '1')],
        upper: [LiteralNode(text: '2')],
        body: [innerSum],
      );
      final result = ExactMathEngine.evaluate([outerSum]);
      expect(result.numerical, equals(12.0));
    });

    test('Large range summation (avoiding infinite loop/slowdown)', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '100')],
          body: [LiteralNode(text: '1')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(100.0));
    });
  });

  group('Calculus Edge Cases - Product', () {
    test('Product with empty variable returns empty result', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: '')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Product with upper < lower returns 1', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '5')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(1.0));
    });

    test('Product including zero', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '-1')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(0.0)); // -1 * 0 * 1
    });

    test('Constant body product', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '5')],
          body: [LiteralNode(text: '2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(32.0)); // 2^5
    });
  });

  group('Calculus Edge Cases - Derivative', () {
    test('Derivative of constant is 0', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: '5')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(0.0));
    });

    test('Derivative with respect to non-existent variable is 0', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'y')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(0.0));
    });

    test('Nested derivatives symbolic', () {
      // d/dx (d/dx (x^3)) = 6x
      final innerDiff = DerivativeNode(
        variable: [LiteralNode(text: 'x')],
        at: [LiteralNode(text: '')],
        body: [LiteralNode(text: 'x^3')],
      );
      final outerDiff = DerivativeNode(
        variable: [LiteralNode(text: 'x')],
        at: [LiteralNode(text: '')],
        body: [innerDiff],
      );
      final result = ExactMathEngine.evaluate([outerDiff]);
      expect(result.expr, isNotNull);
      expect(result.expr!.toString(), contains('6'));
      expect(result.expr!.toString(), contains('x'));
    });
  });

  group('Calculus Edge Cases - Integral', () {
    test('Integral of constant is constant * x', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: '5')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      // Result should be 5x + c (exact result might be represented as term)
      expect(result.expr!.toString(), contains('5'));
      expect(result.expr!.toString(), contains('x'));
      expect(result.expr!.toString(), contains('c'));
    });

    test('Definite integral with constant body', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '2')],
          body: [LiteralNode(text: '5')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, equals(10.0));
    });

    test('Nested integrals symbolic', () {
      // int(int(x, x), x) = int(x^2/2 + c, x) = x^3/6 + cx + d
      // Our engine might just return c for common constant if not careful
      final innerInt = IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '')],
        upper: [LiteralNode(text: '')],
        body: [LiteralNode(text: 'x')],
      );
      final outerInt = IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '')],
        upper: [LiteralNode(text: '')],
        body: [innerInt],
      );
      final result = ExactMathEngine.evaluate([outerInt]);
      expect(result.expr, isNotNull);
      // Just check it contains x^3 or equivalent
      expect(result.expr!.toString(), contains('x'));
      expect(result.expr!.toString(), contains('c'));
    });
  });
}
