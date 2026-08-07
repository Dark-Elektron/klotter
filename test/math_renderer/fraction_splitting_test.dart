import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Fraction Splitting', () {
    test('Distributes division over addition: (9+6-8/45 + sin(pi/5))/2', () {
      // (9 + 6 - 8/45 + sin(pi/5)) / 2
      // Numerator nodes:
      final numNodes = [
        LiteralNode(text: "9"),
        LiteralNode(text: "+"),
        LiteralNode(text: "6"),
        LiteralNode(text: "-"),
        FractionNode(
          num: [LiteralNode(text: "8")],
          den: [LiteralNode(text: "45")],
        ),
        LiteralNode(text: "+"),
        TrigNode(
          function: "sin",
          argument: [
            FractionNode(
              num: [LiteralNode(text: "pi")],
              den: [LiteralNode(text: "5")],
            ),
          ],
        ),
      ];

      final expression = [
        FractionNode(num: numNodes, den: [LiteralNode(text: "2")]),
      ];

      final result = ExactMathEngine.evaluate(expression);
      // ignore: avoid_print
      print('DEBUG: result.expr = ${result.expr}');
      // ignore: avoid_print
      print('DEBUG: result.expr.toString() = ${result.expr.toString()}');

      // Expected: 667/90 + sin(pi/5)/2
      // We check the simplified Expr structure
      expect(result.isEmpty, isFalse);
      expect(result.hasError, isFalse);

      // The result should be a SumExpr containing a FracExpr and a DivExpr (or ProdExpr with 1/2)
      // Printing for manual verification of the structure if needed
      // ignore: avoid_print
      print('Simplified expression: ${result.expr.toString()}');

      // Verify rational part: 9/2 + 6/2 - 8/(45*2) = 4.5 + 3 - 8/90 = 7.5 - 4/45 = 15/2 - 4/45 = (675 - 8)/90 = 667/90
      expect(result.expr.toString(), contains('667/90'));
      expect(result.expr.toString(), contains('sin'));
      expect(
        result.expr.toString(),
        anyOf(contains(')/(2)'), contains('/ 2'), contains('1/2 *')),
      );
    });

    test('Distributes simple sum: (x + y) / 2', () {
      final expression = [
        FractionNode(
          num: [
            LiteralNode(text: "x"),
            LiteralNode(text: "+"),
            LiteralNode(text: "y"),
          ],
          den: [LiteralNode(text: "2")],
        ),
      ];

      final result = ExactMathEngine.evaluate(expression);
      expect(result.expr.toString(), contains('(x)/(2)'));
      expect(result.expr.toString(), contains('(y)/(2)'));
    });

    test('Simplifies stacked fractions: (7/2) / (6 * sin(2))', () {
      // (7/2) / (6 * sin(2))
      final expression = [
        FractionNode(
          num: [
            FractionNode(
              num: [LiteralNode(text: "7")],
              den: [LiteralNode(text: "2")],
            ),
          ],
          den: [
            LiteralNode(text: "6"),
            TrigNode(function: "sin", argument: [LiteralNode(text: "2")]),
          ],
        ),
      ];

      final result = ExactMathEngine.evaluate(expression);
      // Expected: 7 / (12 * sin(2))
      // ignore: avoid_print
      print('DEBUG: result.expr = ${result.expr}');
      expect(result.expr.toString(), contains('(7)/(12'));
      expect(result.expr.toString(), contains('sin(2)'));
    });

    test('Simplifies inverse fractions: 1 / (1/x)', () {
      final expression = [
        FractionNode(
          num: [LiteralNode(text: "1")],
          den: [
            FractionNode(
              num: [LiteralNode(text: "1")],
              den: [LiteralNode(text: "x")],
            ),
          ],
        ),
      ];

      final result = ExactMathEngine.evaluate(expression);
      // Expected: x
      expect(result.expr.toString(), equals('x'));
    });
  });
}
