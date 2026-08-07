import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('ExactMathEngine AnsNode Support', () {
    test('resolves simple AnsNode', () {
      // Cell 0: 1 + 2 = 3
      final expr0 = IntExpr.from(3);

      // Cell 1: ans0 * 4
      final expression = <MathNode>[
        AnsNode(index: [LiteralNode(text: '0')]),
        LiteralNode(text: '*'),
        LiteralNode(text: '4'),
      ];

      final result = ExactMathEngine.evaluate(
        expression,
        ansExpressions: {0: expr0},
      );

      expect(result.hasError, false);
      expect(result.expr, isA<IntExpr>());
      expect((result.expr as IntExpr).value, BigInt.from(12));
    });

    test('resolves nested AnsNode', () {
      // Cell 0: sqrt(2)
      final expr0 = RootExpr.sqrt(IntExpr.from(2));

      // Cell 1: ans0 * ans0
      final expression = <MathNode>[
        AnsNode(index: [LiteralNode(text: '0')]),
        LiteralNode(text: '*'),
        AnsNode(index: [LiteralNode(text: '0')]),
      ];

      final result = ExactMathEngine.evaluate(
        expression,
        ansExpressions: {0: expr0},
      );

      expect(result.hasError, false);
      expect(result.expr, isA<IntExpr>());
      expect((result.expr as IntExpr).value, BigInt.from(2));
    });

    test('falls back to variable when AnsNode unresolvable', () {
      final expression = <MathNode>[
        AnsNode(index: [LiteralNode(text: '5')]),
        LiteralNode(text: '+'),
        LiteralNode(text: '1'),
      ];

      final result = ExactMathEngine.evaluate(
        expression,
        ansExpressions: {}, // No ans5 provided
      );

      expect(result.hasError, false);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      expect(sum.terms[0], isA<VarExpr>());
      expect((sum.terms[0] as VarExpr).name, 'ans5');
    });

    test('resolves multiple different AnsNodes', () {
      // Cell 0: 10
      // Cell 1: 20
      final expr0 = IntExpr.from(10);
      final expr1 = IntExpr.from(20);

      // Cell 2: ans0 + ans1
      final expression = <MathNode>[
        AnsNode(index: [LiteralNode(text: '0')]),
        LiteralNode(text: '+'),
        AnsNode(index: [LiteralNode(text: '1')]),
      ];

      final result = ExactMathEngine.evaluate(
        expression,
        ansExpressions: {0: expr0, 1: expr1},
      );

      expect(result.hasError, false);
      expect(result.expr, isA<IntExpr>());
      expect((result.expr as IntExpr).value, BigInt.from(30));
    });
  });
}
