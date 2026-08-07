import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Final Math Engine Tests (Exact)', () {
    test('Hyperbolic Function Tokenization & Roundtrip', () {
      final funcs = ['sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh'];

      for (var f in funcs) {
        final node = TrigNode(function: f, argument: [LiteralNode(text: '1')]);

        final expr = MathNodeToExpr.convert([node]);
        expect(expr, isNotNull, reason: 'Failed to convert $f');

        final backNodes = expr.toMathNode();
        expect(backNodes[0], isA<TrigNode>());
        expect((backNodes[0] as TrigNode).function, equals(f));
      }
    });

    test('Physical Constants Representation', () {
      final constants = {
        '\u03B5\u2080': 'epsilon0', // ε₀
        '\u03BC\u2080': 'mu0', // μ₀
        'c\u2080': 'c0', // c₀
      };

      constants.forEach((symbol, name) {
        final node = ConstantNode(symbol);
        final expr = MathNodeToExpr.convert([node]);
        expect(expr, isNotNull);

        final backNodes = expr.toMathNode();
        expect(backNodes[0], isA<ConstantNode>());
        expect((backNodes[0] as ConstantNode).constant, equals(symbol));
      });
    });

    test('Symbolic Evaluation of Constants', () {
      // 1/mu0 should remain symbolic if not simplified to decimal
      final node = FractionNode(
        num: [LiteralNode(text: '1')],
        den: [ConstantNode('\u03BC\u2080')],
      );
      final expr = MathNodeToExpr.convert([node]);

      final backNodes = expr.toMathNode();
      expect(backNodes[0], isA<FractionNode>());
      final frac = backNodes[0] as FractionNode;
      expect(
        (frac.denominator[0] as ConstantNode).constant,
        equals('\u03BC\u2080'),
      );
    });

    test('Exact Trig Known Values (Basic check)', () {
      // sinh(0) -> 0
      final node = TrigNode(
        function: 'sinh',
        argument: [LiteralNode(text: '0')],
      );
      final expr = MathNodeToExpr.convert([node]).simplify();
      expect(expr is IntExpr && expr.isZero, isTrue);
    });
  });
}
