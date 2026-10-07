import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_engine/real_functions.dart' as rf;
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// The hyperbolic functions over their whole range.
///
/// They were built from exp in every engine, so tanh came out as inf/inf, NaN,
/// once e^x overflowed near |x| = 710 — tanh(1000x) plotted as nothing past
/// x = 0.71 — and asinh of a large negative number cancelled to log 0.
void main() {
  /// Relative agreement, for values that span many orders of magnitude.
  void expectClose(double actual, double expected, {double rel = 1e-12}) {
    expect(
      (actual - expected).abs(),
      lessThanOrEqualTo(rel * expected.abs()),
      reason: 'got $actual, expected $expected',
    );
  }

  group('real functions', () {
    test('agree with known values in the ordinary range', () {
      expectClose(rf.sinh(1), 1.1752011936438014);
      expectClose(rf.cosh(1), 1.5430806348152437);
      expectClose(rf.tanh(1), 0.7615941559557649);
      expectClose(rf.asinh(1), 0.881373587019543);
      expectClose(rf.acosh(2), 1.3169578969248166);
      expectClose(rf.atanh(0.5), 0.5493061443340549);
      expectClose(rf.sinh(-3), -10.017874927409903);
      expectClose(rf.cosh(-3), 10.067661995777765);
    });

    test('tanh is ±1 far out, not NaN', () {
      expect(rf.tanh(800), 1);
      expect(rf.tanh(-800), -1);
      expect(rf.tanh(1e300), 1);
      expect(rf.tanh(double.infinity), 1);
      expect(rf.tanh(double.negativeInfinity), -1);
    });

    test('sinh and cosh reach the top of the double range', () {
      // e^710 overflows, but sinh(710) = e^710 / 2 does not.
      expect(rf.sinh(710).isFinite, isTrue);
      expect(rf.cosh(710).isFinite, isTrue);
      expectClose(rf.sinh(710), math.exp(710 - math.ln2));
      expect(rf.sinh(711), double.infinity);
      expect(rf.sinh(-711), double.negativeInfinity);
    });

    test('the inverses keep their value for large arguments', () {
      // ln(2e8) and ln(2e200), the asymptotes.
      expectClose(rf.asinh(-1e8), -19.113827924512311);
      expectClose(rf.asinh(1e200), 461.2101657793691);
      expectClose(rf.acosh(1e200), 461.2101657793691);
    });

    test('small arguments keep their digits', () {
      expectClose(rf.sinh(1e-10), 1e-10, rel: 1e-15);
      expectClose(rf.tanh(1e-10), 1e-10, rel: 1e-15);
      expectClose(rf.asinh(1e-10), 1e-10, rel: 1e-15);
      expectClose(rf.atanh(1e-10), 1e-10, rel: 1e-15);
      // Just above 1, where a² − 1 loses most of its digits.
      expectClose(rf.acosh(1 + 1e-10), math.sqrt(2e-10), rel: 1e-6);
      expect(rf.tanh(-0.0).isNegative, isTrue, reason: 'tanh is odd');
    });

    test('outside their domains they are undefined, at the edges infinite', () {
      expect(rf.acosh(0.5).isNaN, isTrue);
      expect(rf.atanh(2).isNaN, isTrue);
      expect(rf.atanh(1), double.infinity);
      expect(rf.atanh(-1), double.negativeInfinity);
      expect(rf.sinh(double.nan).isNaN, isTrue);
    });
  });

  /// A function applied to [argument], as the keypad builds it: a function
  /// node, not the letters of its name, which the plot reads as variables.
  MathNode call(String function, String argument) => TrigNode(
    function: function,
    argument: <MathNode>[LiteralNode(text: argument)],
  );

  group('through the plot', () {
    PlotExpression line(MathNode node) =>
        PlotExpression.compile(<MathNode>[node]);

    test('tanh(1000x) is drawn past x = 0.71', () {
      final PlotExpression f = line(call('tanh', '1000x'));
      expect(f.error, isNull);
      expect(f.evaluate(1), 1);
      expect(f.evaluate(-1), -1);
      expect(f.evaluate(0.8), 1);
    });

    test('asinh of a large negative x has a value', () {
      final PlotExpression f = line(call('asinh', 'x'));
      expect(f.error, isNull);
      expectClose(f.evaluate(-1e8), -19.113827924512311);
    });
  });

  group('complex tanh', () {
    test('agrees with the known value', () {
      final Complex t = complexTanh(const Complex(1, 1));
      expectClose(t.real, 1.0839233273386946);
      expectClose(t.imag, 0.27175258531951174);
    });

    test('is ±1 far from the imaginary axis, not NaN', () {
      final Complex right = complexTanh(const Complex(800, 1));
      expect(right.real, 1);
      expect(right.imag.abs(), lessThan(1e-300));
      final Complex left = complexTanh(const Complex(-800, 1));
      expect(left.real, -1);
    });

    test('reaches the plot as one value per point', () {
      final Expr e = MathNodeToExpr.convert(<MathNode>[
        call('tanh', 'z'),
      ]).simplify();
      final Complex v = e.evalComplexWith(<String, Complex>{
        'z': const Complex(400, 0.5),
      });
      expect(v.real, 1);
      expect(v.imag.isFinite, isTrue);
    });
  });

  group('the calculator engine', () {
    test('tanh of a large argument is 1', () {
      expect(MathSolverNew.solve('tanh(800)'), '1');
    });
  });
}
