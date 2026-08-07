import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Incomplete Nodes Result Suppression', () {
    test('Summation with empty variable returns empty result', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: '')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Summation with empty lower bound returns empty result', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Summation with empty upper bound returns empty result', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Product with empty variable returns empty result', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: '')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Product with empty lower bound returns empty result', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Product with empty upper bound returns empty result', () {
      final nodes = [
        ProductNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'i')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Expression containing incomplete summation returns empty result', () {
      final incompleteSum = SummationNode(
        variable: [LiteralNode(text: 'i')],
        lower: [LiteralNode(text: '1')],
        upper: [LiteralNode(text: '')],
        body: [LiteralNode(text: 'i')],
      );
      final nodes = [LiteralNode(text: '5 + '), incompleteSum];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Derivative with empty variable returns empty result', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: '')],
          at: [LiteralNode(text: '0')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });

    test('Integral with empty variable returns empty result', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: '')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, isTrue);
    });
  });
}
