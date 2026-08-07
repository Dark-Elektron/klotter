import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Complex Number Verification', () {
    test('i * i = -1', () {
      final nodes = [LiteralNode(text: 'i*i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, -1.0);
      expect(result.toNumericalString(), '\u22121');
    });

    test('5i * 5i = -25', () {
      final nodes = [LiteralNode(text: '5i*5i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, -25.0);
      expect(result.toNumericalString(), '\u221225');
    });

    test('5i display', () {
      final nodes = [LiteralNode(text: '5i')];
      final result = ExactMathEngine.evaluate(nodes);
      // toExactString uses unicode dot \u00B7
      expect(result.toExactString(), '5\u00B7i');
      expect(result.toNumericalString(), '5i');
    });

    test('2i display', () {
      final nodes = [LiteralNode(text: '2i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toExactString(), '2\u00B7i');
      expect(result.toNumericalString(), '2i');
    });

    test('i display', () {
      final nodes = [LiteralNode(text: 'i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toExactString(), 'i');
      expect(result.toNumericalString(), 'i');
    });

    test('sqrt(-4) = 2i', () {
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '-4')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toExactString(), '2\u00B7i');
      expect(result.toNumericalString(), '2i');
    });

    test('complex sum: 3 + 4i', () {
      final nodes = [LiteralNode(text: '3+4i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '3 + 4i');
    });

    test('complex subtraction: 3 - i', () {
      final nodes = [LiteralNode(text: '3-i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '3 \u2212 i');
    });

    test('negative imaginary: -2i', () {
      final nodes = [LiteralNode(text: '-2i')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '\u22122i');
    });

    test('abs of complex number', () {
      final nodes = [
        TrigNode(function: 'abs', argument: [LiteralNode(text: '3+4i')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '5');
    });

    test('arg of complex number', () {
      final nodes = [
        TrigNode(function: 'arg', argument: [LiteralNode(text: '3+4i')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      final value = double.parse(result.toNumericalString());
      expect(value, closeTo(atan2(4, 3), 1e-6));
    });

    test('arg of negative real is pi', () {
      final nodes = [
        TrigNode(function: 'arg', argument: [LiteralNode(text: '-2')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      final value = double.parse(result.toNumericalString());
      expect(value, closeTo(pi, 1e-6));
    });

    test('Re and Im of complex number', () {
      final reNodes = [
        TrigNode(function: 'Re', argument: [LiteralNode(text: '3+4i')]),
      ];
      final imNodes = [
        TrigNode(function: 'Im', argument: [LiteralNode(text: '3+4i')]),
      ];
      final reResult = ExactMathEngine.evaluate(reNodes);
      final imResult = ExactMathEngine.evaluate(imNodes);
      expect(reResult.toNumericalString(), '3');
      expect(imResult.toNumericalString(), '4');
    });

    test('Im of real number is 0', () {
      final nodes = [
        TrigNode(function: 'Im', argument: [LiteralNode(text: '7')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '0');
    });

    test('sgn of complex number', () {
      final nodes = [
        TrigNode(function: 'sgn', argument: [LiteralNode(text: '3+4i')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.toNumericalString(), '0.6 + 0.8i');
    });
  });
}
