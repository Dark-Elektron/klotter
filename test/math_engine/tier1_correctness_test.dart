// Regression tests for the Tier 1 correctness fixes in the math engines.
//
// Covers:
//   1.2/1.3 unary-minus vs power precedence and right-associativity of `^`
//   1.4     real odd roots of negative numbers
//   1.5     factorial no longer overflows (BigInt)
//   1.6     lowercase-'e' scientific notation is not corrupted by Euler's e
//   1.7     sin exact values for arguments outside [0, 2pi)
//
// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  // Parse a solver result string into a double (handles ×10 superscript E,
  // unicode minus and thousands separators).
  double? _dec(String expression) {
    final String? result = MathSolverNew.solve(expression);
    if (result == null || result.isEmpty) return null;
    final String normalized = result
        .replaceAll('ᴇ', 'E')
        .replaceAll('−', '-')
        .replaceAll(',', '');
    return double.tryParse(normalized);
  }

  void _expectExprEquals(Expr actual, Expr expected) {
    expect(actual.simplify().structurallyEquals(expected.simplify()), isTrue,
        reason: 'expected $expected but got $actual');
  }

  group('1.2/1.3 unary minus and power precedence (decimal engine)', () {
    test('-2^2 == -4 (power binds tighter than unary minus)', () {
      expect(MathSolverNew.solve('-2^2'), equals('-4'));
    });

    test('-3^2 == -9', () {
      expect(MathSolverNew.solve('-3^2'), equals('-9'));
    });

    test('-2^3 == -8', () {
      expect(MathSolverNew.solve('-2^3'), equals('-8'));
    });

    test('(-2)^2 == 4 (explicit parentheses unchanged)', () {
      expect(MathSolverNew.solve('(-2)^2'), equals('4'));
    });

    test('2^3^2 == 512 (right-associative)', () {
      expect(MathSolverNew.solve('2^3^2'), equals('512'));
    });

    test('2^2^3 == 256 (right-associative, not 64)', () {
      expect(MathSolverNew.solve('2^2^3'), equals('256'));
    });

    test('2^-3 == 0.125 (signed exponent still parses)', () {
      expect(_dec('2^-3'), closeTo(0.125, 1e-12));
    });

    test('2^3 == 8 (single power unchanged)', () {
      expect(MathSolverNew.solve('2^3'), equals('8'));
    });
  });

  group('1.4 real odd roots of negative numbers', () {
    test('decimal: (-8)^(1/3) == -2', () {
      expect(_dec('(-8)^(1/3)'), closeTo(-2.0, 1e-9));
    });

    test('decimal: (-32)^(1/5) == -2', () {
      expect(_dec('(-32)^(1/5)'), closeTo(-2.0, 1e-9));
    });

    test('decimal: (-27)^(1/3) == -3', () {
      expect(_dec('(-27)^(1/3)'), closeTo(-3.0, 1e-9));
    });

    test('exact: cube root of -8 is -2', () {
      final result = ExactMathEngine.evaluate(<MathNode>[
        RootNode(
          index: <MathNode>[LiteralNode(text: '3')],
          radicand: <MathNode>[LiteralNode(text: '-8')],
        ),
      ]);
      expect(result.numerical, isNotNull);
      expect(result.numerical, closeTo(-2.0, 1e-9));
    });

    test('exact: cube root of -10 (non-integer) is real, not NaN', () {
      final result = ExactMathEngine.evaluate(<MathNode>[
        RootNode(
          index: <MathNode>[LiteralNode(text: '3')],
          radicand: <MathNode>[LiteralNode(text: '-10')],
        ),
      ]);
      expect(result.numerical, isNotNull);
      expect(result.numerical!.isNaN, isFalse);
      expect(result.numerical, closeTo(-math.pow(10, 1 / 3), 1e-9));
    });

    test('realPow helper handles odd roots and keeps complex cases NaN', () {
      expect(realPow(-8, 1 / 3), closeTo(-2.0, 1e-9));
      expect(realPow(-32, 1 / 5), closeTo(-2.0, 1e-9));
      expect(realPow(-8, 2 / 3), closeTo(4.0, 1e-9)); // even numerator
      expect(realPow(8, 1 / 3), closeTo(2.0, 1e-9)); // positive unaffected
      expect(realPow(2, 3), closeTo(8.0, 1e-12));
      expect(realPow(-4, 0.5).isNaN, isTrue); // genuinely complex
    });
  });

  group('1.5 factorial does not overflow', () {
    test('5! == 120', () {
      expect(MathSolverNew.solve('5!'), equals('120'));
    });

    test('0! == 1', () {
      expect(MathSolverNew.solve('0!'), equals('1'));
    });

    // Display goes through a double, so only the magnitude (not every digit)
    // survives; the point is that the value is correct and positive rather
    // than wrapping negative as the old int path did.
    test('21! is a large positive value (no int overflow to negative)', () {
      const expected = 51090942171709440000.0;
      final v = _dec('21!');
      expect(v, isNotNull);
      expect(v, greaterThan(0)); // old int path wrapped negative
      expect(v, closeTo(expected, expected * 1e-5));
    });

    test('25! is a large positive value', () {
      const expected = 15511210043330985984000000.0;
      final v = _dec('25!');
      expect(v, isNotNull);
      expect(v, greaterThan(0));
      expect(v, closeTo(expected, expected * 1e-5));
    });
  });

  group('1.6 lowercase-e scientific notation', () {
    test('2e3 == 2000', () {
      expect(_dec('2e3'), closeTo(2000, 1e-9));
    });

    test('1.5e3 == 1500', () {
      expect(_dec('1.5e3'), closeTo(1500, 1e-9));
    });

    test('2e-3 == 0.002', () {
      expect(_dec('2e-3'), closeTo(0.002, 1e-12));
    });

    test("Euler's e still works standalone", () {
      expect(_dec('e'), closeTo(math.e, 1e-6));
    });

    test('2e (digit then e, no exponent digits) is 2*e', () {
      expect(_dec('2e'), closeTo(2 * math.e, 1e-6));
    });
  });

  group('1.7 sin exact reduction for arguments outside [0, 2pi)', () {
    ExactResult _sin(String argument) {
      return ExactMathEngine.evaluate(<MathNode>[
        TrigNode(
          function: 'sin',
          argument: <MathNode>[LiteralNode(text: argument)],
        ),
      ]);
    }

    test('sin(390°) == 1/2 exactly (13π/6 reduced)', () {
      final result = _sin('390°');
      expect(result.hasError, isFalse);
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, FracExpr.from(1, 2));
    });

    test('sin(750°) == 1/2 exactly', () {
      final result = _sin('750°');
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, FracExpr.from(1, 2));
    });

    test('sin(-30°) == -1/2 exactly', () {
      final result = _sin('-30°');
      expect(result.expr, isNotNull);
      _expectExprEquals(result.expr!, FracExpr.from(-1, 2));
    });
  });
}
