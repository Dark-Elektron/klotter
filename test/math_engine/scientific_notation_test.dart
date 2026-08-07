import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  group('Smart Scientific Notation Tests', () {
    setUp(() {
      MathSolverNew.numberFormat = NumberFormat.automatic;
      MathSolverNew.precision = 6;
    });

    test('Large integer becomes scientific with automatic format (>= 1e6)', () {
      final expr = IntExpr(BigInt.from(123456789));
      final nodes = expr.toMathNode();
      expect(nodes.length, equals(1));
      expect((nodes[0] as LiteralNode).text, equals('1.234568\u1D078'));
    });

    test('Large integer (>1e15) uses scientific notation', () {
      final expr = IntExpr(BigInt.from(10).pow(16));
      final nodes = expr.toMathNode();
      expect(nodes.length, equals(1));
      expect((nodes[0] as LiteralNode).text, equals('1\u1D0716'));
    });

    test('Negative large integer uses scientific notation with minus sign', () {
      final expr = IntExpr(-BigInt.from(10).pow(16));
      final nodes = expr.toMathNode();
      expect(nodes.length, equals(1));
      expect((nodes[0] as LiteralNode).text, equals('−1\u1D0716'));
    });

    test('Fraction with small numbers remain plain', () {
      final expr = FracExpr(IntExpr(BigInt.from(21)), IntExpr(BigInt.from(5)));
      final nodes = expr.toMathNode();
      expect(nodes[0], isA<FractionNode>());
      final frac = nodes[0] as FractionNode;
      expect((frac.numerator[0] as LiteralNode).text, equals('21'));
      expect((frac.denominator[0] as LiteralNode).text, equals('5'));
    });

    test(
      'Fraction with extremely large numerator uses scientific notation',
      () {
        final expr = FracExpr(
          IntExpr(BigInt.from(10).pow(20)),
          IntExpr(BigInt.from(3)),
        );
        final nodes = expr.toMathNode();
        final frac = nodes[0] as FractionNode;
        expect((frac.numerator[0] as LiteralNode).text, equals('1\u1D0720'));
        expect((frac.denominator[0] as LiteralNode).text, equals('3'));
      },
    );

    test('Respects scientific mode for small whole numbers', () {
      MathSolverNew.numberFormat = NumberFormat.scientific;
      final expr = IntExpr(BigInt.from(123));
      final nodes = expr.toMathNode();
      expect((nodes[0] as LiteralNode).text, equals('1.23\u1D072'));
    });

    test(
      'Fraction DOES use scientific notation for components in scientific mode',
      () {
        MathSolverNew.numberFormat = NumberFormat.scientific;
        final expr = FracExpr(
          IntExpr(BigInt.from(21)),
          IntExpr(BigInt.from(5)),
        );
        final nodes = expr.toMathNode();
        final frac = nodes[0] as FractionNode;
        expect((frac.numerator[0] as LiteralNode).text, equals('2.1\u1D071'));
        expect((frac.denominator[0] as LiteralNode).text, equals('5\u1D070'));
      },
    );

    test('Rounds up correctly: 129,999 with precision 2', () {
      MathSolverNew.numberFormat = NumberFormat.scientific;
      MathSolverNew.precision = 2;
      final expr = IntExpr(BigInt.from(129999));
      final nodes = expr.toMathNode();
      expect((nodes[0] as LiteralNode).text, equals('1.3\u1D075'));
    });

    test('Carry over rounding: 9,999,999 with precision 2', () {
      MathSolverNew.numberFormat = NumberFormat.scientific;
      MathSolverNew.precision = 2;
      final expr = IntExpr(BigInt.from(9999999));
      final nodes = expr.toMathNode();
      expect((nodes[0] as LiteralNode).text, equals('1\u1D077'));
    });

    test('Large threshold rounding: 1.2345e15 with precision 2', () {
      MathSolverNew.numberFormat = NumberFormat.automatic;
      MathSolverNew.precision = 2;
      final expr = IntExpr(BigInt.from(12345) * BigInt.from(10).pow(11));
      final nodes = expr.toMathNode();
      expect((nodes[0] as LiteralNode).text, equals('1.23\u1D0715'));
    });
  });
}
