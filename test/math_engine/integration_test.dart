import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/renderer.dart';

void main() {
  group('Integration - Expression to Result', () {
    test('simple addition: 2+3 = 5', () {
      final expression = [LiteralNode(text: '2+3')];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('5'));
    });

    test('fraction: 1/2 = 0.5', () {
      final expression = [
        FractionNode(
          num: [LiteralNode(text: '1')],
          den: [LiteralNode(text: '2')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('0.5'));
    });

    test('exponent: 2^3 = 8', () {
      final expression = [
        ExponentNode(
          base: [LiteralNode(text: '2')],
          power: [LiteralNode(text: '3')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('8'));
    });

    test('square root: sqrt(16) = 4', () {
      final expression = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '16')]),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('4'));
    });

    test('trig function: sin(0) = 0', () {
      final expression = [
        TrigNode(function: 'sin', argument: [LiteralNode(text: '0')]),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('0'));
    });

    test('permutation: 5P2 = 20', () {
      final expression = [
        PermutationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('20'));
    });

    test('combination: 5C2 = 10', () {
      final expression = [
        CombinationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('10'));
    });

    test('complex expression: (2+3)*4/2 = 10', () {
      final expression = [
        FractionNode(
          num: [
            ParenthesisNode(content: [LiteralNode(text: '2+3')]),
            LiteralNode(text: '*4'),
          ],
          den: [LiteralNode(text: '2')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('10'));
    });

    test('natural log: ln(1) = 0', () {
      final expression = [
        LogNode(isNaturalLog: true, argument: [LiteralNode(text: '1')]),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('0'));
    });

    test('log base 10: log10(100) = 2', () {
      final expression = [
        LogNode(
          isNaturalLog: false,
          base: [LiteralNode(text: '10')],
          argument: [LiteralNode(text: '100')],
        ),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('2'));
    });

    test('equation solving: x+5=10 gives x=5', () {
      final expression = [LiteralNode(text: 'x+5=10')];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, equals('x = 5'));
    });

    test('system of equations', () {
      final expression = [
        LiteralNode(text: 'x+y=5'),
        NewlineNode(),
        LiteralNode(text: 'x-y=1'),
      ];
      final serialized = MathExpressionSerializer.serialize(expression);
      final result = MathSolverNew.solve(serialized);
      expect(result, contains('x = 3'));
      expect(result, contains('y = 2'));
    });
  });

  group('Integration - Persistence Round Trip', () {
    test('simple expression survives JSON round trip', () {
      final original = [LiteralNode(text: '2+3')];

      // Serialize to JSON
      final json = MathExpressionSerializer.serializeToJson(original);

      // Deserialize from JSON
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      // Serialize both to string and compare
      final originalStr = MathExpressionSerializer.serialize(original);
      final restoredStr = MathExpressionSerializer.serialize(restored);

      expect(restoredStr, equals(originalStr));
    });

    test('complex expression survives JSON round trip', () {
      final original = [
        LiteralNode(text: '2'),
        FractionNode(
          num: [
            TrigNode(function: 'sin', argument: [LiteralNode(text: '30')]),
          ],
          den: [LiteralNode(text: '2')],
        ),
        LiteralNode(text: '+'),
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '16')]),
      ];

      final json = MathExpressionSerializer.serializeToJson(original);
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      final originalStr = MathExpressionSerializer.serialize(original);
      final restoredStr = MathExpressionSerializer.serialize(restored);

      expect(restoredStr, equals(originalStr));
    });
  });

  group('Integration - ANS References', () {
    test('ans reference uses previous result', () {
      // Simulate first calculation
      final expr1 = [LiteralNode(text: '2+3')];
      final serialized1 = MathExpressionSerializer.serialize(expr1);
      final result1 = MathSolverNew.solve(serialized1);
      expect(result1, equals('5'));

      // Create ans values map
      final ansValues = {0: result1!};

      // Second calculation using ans0
      final expr2 = [
        AnsNode(index: [LiteralNode(text: '0')]),
        LiteralNode(text: '*2'),
      ];
      final serialized2 = MathExpressionSerializer.serialize(expr2);
      final result2 = MathSolverNew.solve(serialized2, ansValues: ansValues);

      expect(result2, equals('10'));
    });
  });
}
