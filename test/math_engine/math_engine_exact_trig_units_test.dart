// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  Expr _sqrt2Over2() =>
      DivExpr(RootExpr.sqrt(IntExpr.two), IntExpr.two).simplify();

  ExactResult _evalExactTrig(String function, String argument) {
    return ExactMathEngine.evaluate(<MathNode>[
      TrigNode(
        function: function,
        argument: <MathNode>[LiteralNode(text: argument)],
      ),
    ]);
  }

  double? _evalDecimal(String expression) {
    final String? result = MathSolverNew.evaluate(expression);
    if (result == null || result.isEmpty) return null;
    final String normalized = result
        .replaceAll('\u1D07', 'E')
        .replaceAll('\u2212', '-')
        .replaceAll(',', '');
    return double.tryParse(normalized);
  }

  void _expectClose(double? actual, double expected, {double eps = 1e-6}) {
    expect(actual, isNotNull);
    expect((actual! - expected).abs(), lessThan(eps));
  }

  void _expectExprEquals(Expr actual, Expr expected) {
    expect(actual.simplify().structurallyEquals(expected.simplify()), isTrue);
  }

  group('MathNodeToExpr angle unit tokenization', () {
    test('135° tokenizes to 3π/4', () {
      final Expr expr = MathNodeToExpr.convert(<MathNode>[
        LiteralNode(text: '135°'),
      ]);
      final Expr expected =
          DivExpr(
            ProdExpr(<Expr>[IntExpr.from(3), ConstExpr.pi]),
            IntExpr.from(4),
          ).simplify();

      _expectExprEquals(expr, expected);
    });

    test('(90+45)° tokenizes to 3π/4', () {
      final Expr expr = MathNodeToExpr.convert(<MathNode>[
        LiteralNode(text: '(90+45)°'),
      ]);
      final Expr expected =
          DivExpr(
            ProdExpr(<Expr>[IntExpr.from(3), ConstExpr.pi]),
            IntExpr.from(4),
          ).simplify();

      _expectExprEquals(expr, expected);
    });

    test('rad suffix is a no-op in default radian mode', () {
      final Expr expr = MathNodeToExpr.convert(<MathNode>[
        LiteralNode(text: '1rad'),
      ]);
      _expectExprEquals(expr, IntExpr.one);
    });
  });

  group('Exact trig nodes with degree input', () {
    test('sin(135°) = √2/2 exactly', () {
      final ExactResult result = _evalExactTrig('sin', '135°');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, _sqrt2Over2());
    });

    test('cos(135°) = -√2/2 exactly', () {
      final ExactResult result = _evalExactTrig('cos', '135°');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, _sqrt2Over2().negate());
    });

    test('tan(135°) = -1 exactly', () {
      final ExactResult result = _evalExactTrig('tan', '135°');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, IntExpr.negOne);
    });

    test('sin((180-45)°) = √2/2 exactly', () {
      final ExactResult result = _evalExactTrig('sin', '(180-45)°');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, _sqrt2Over2());
    });

    test('without degree symbol, trig input remains radians', () {
      final ExactResult result = _evalExactTrig('sin', '135');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectClose(result.numerical, math.sin(135));
    });
  });

  group('Decimal trig unit behavior', () {
    test('sin/cos/tan with ° use degree conversion', () {
      _expectClose(_evalDecimal('sin(135°)'), math.sqrt(2) / 2);
      _expectClose(_evalDecimal('cos(135°)'), -math.sqrt(2) / 2);
      _expectClose(_evalDecimal('tan(135°)'), -1.0);
    });

    test('without ° the default interpretation is radians', () {
      _expectClose(_evalDecimal('sin(135)'), math.sin(135));
      _expectClose(_evalDecimal('cos(135)'), math.cos(135));
      _expectClose(_evalDecimal('tan(135)'), math.tan(135));
    });

    test('explicit rad suffix behaves the same as default radians', () {
      _expectClose(_evalDecimal('sin(1rad)'), math.sin(1));
      _expectClose(_evalDecimal('cos((π/2)rad)'), math.cos(math.pi / 2));
      _expectClose(_evalDecimal('tan((π/4)rad)'), math.tan(math.pi / 4));
    });
  });
}
