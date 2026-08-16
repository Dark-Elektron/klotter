import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// Evaluating a compiled expression over the complex numbers.
///
/// Everything drawn for a complex function rests on this, and it is pure
/// arithmetic, so it is checked against values that can be looked up rather
/// than against itself. A branch cut taken the wrong way round shows up here
/// or nowhere.
void main() {
  Expr compileNodes(List<MathNode> nodes) {
    final expr = MathNodeToExpr.convert(nodes);
    expect(expr, isNotNull, reason: 'did not compile');
    return expr;
  }

  Expr compile(String source) =>
      compileNodes(<MathNode>[LiteralNode(text: source)]);

  /// A trig call, built as the node the editor produces.
  ///
  /// Not as literal text: `sin(z)` written that way parses as a variable
  /// named `sin` multiplied by z, which evaluates to "unbound variable sin"
  /// rather than to a sine. Two tests earlier in this session were cleared by
  /// expressions that had failed to compile in exactly this way.
  Expr trig(String fn, List<MathNode> argument) =>
      compileNodes(<MathNode>[TrigNode(function: fn, argument: argument)]);

  Expr trigOfZ(String fn) => trig(fn, <MathNode>[LiteralNode(text: 'z')]);

  Complex evalAt(String source, {Complex? z}) => compile(
    source,
  ).evalComplexWith(<String, Complex>{'z': z ?? const Complex(0, 0)});

  void expectComplex(Complex got, double re, double im, {double eps = 1e-9}) {
    expect(got.real, closeTo(re, eps), reason: 'real part of $got');
    expect(got.imag, closeTo(im, eps), reason: 'imaginary part of $got');
  }

  group('the imaginary unit', () {
    test('is i', () => expectComplex(evalAt('i'), 0, 1));

    test('squares to -1', () => expectComplex(evalAt('i^2'), -1, 0));

    test('is recognised wherever it sits in the expression', () {
      expect(compile('i').usesImaginaryUnit, isTrue);
      expect(compile('z+i').usesImaginaryUnit, isTrue);
      expect(
        trig('sin', <MathNode>[LiteralNode(text: '2i')]).usesImaginaryUnit,
        isTrue,
      );
      expect(compile('1/(z-i)').usesImaginaryUnit, isTrue);
      // And not claimed where it is absent — this is what decides whether a
      // line is drawn as a complex function at all.
      expect(compile('z^2').usesImaginaryUnit, isFalse);
      expect(trigOfZ('sin').usesImaginaryUnit, isFalse);
    });
  });

  group('the exponential and its inverse', () {
    test("Euler's identity: e^(iπ) = -1", () {
      expectComplex(complexExp(Complex(0, math.pi)), -1, 0, eps: 1e-12);
    });

    test('e^(iπ/2) = i', () {
      expectComplex(complexExp(Complex(0, math.pi / 2)), 0, 1, eps: 1e-12);
    });

    test('log(-1) = iπ — the principal branch, not zero', () {
      // The whole point of a principal branch: a negative real has a
      // logarithm, and its imaginary part is π rather than -π.
      expectComplex(complexLog(const Complex(-1, 0)), 0, math.pi);
    });

    test('log(i) = iπ/2', () {
      expectComplex(complexLog(const Complex(0, 1)), 0, math.pi / 2);
    });

    test('log and exp undo each other away from the cut', () {
      for (final Complex z in <Complex>[
        const Complex(1, 1),
        const Complex(-0.5, 2),
        const Complex(3, -0.25),
      ]) {
        final Complex back = complexExp(complexLog(z));
        expectComplex(back, z.real, z.imag, eps: 1e-9);
      }
    });
  });

  group('roots and powers', () {
    test('√(-1) = i, where the real evaluator has no answer at all', () {
      expectComplex(complexSqrt(const Complex(-1, 0)), 0, 1);
    });

    test('√i is at half its argument', () {
      final Complex r = complexSqrt(const Complex(0, 1));
      expect(r.magnitude, closeTo(1, 1e-12));
      expect(r.phase, closeTo(math.pi / 4, 1e-12));
    });

    test('a square root squares back', () {
      for (final Complex z in <Complex>[
        const Complex(3, 4),
        const Complex(-2, 0.5),
        const Complex(0, -9),
      ]) {
        final Complex r = complexSqrt(z);
        expectComplex(r * r, z.real, z.imag, eps: 1e-9);
      }
    });

    test('0^2 is 0, not NaN', () {
      // The general formula goes through log, which is not finite at zero.
      expectComplex(complexPow(const Complex(0, 0), const Complex(2, 0)), 0, 0);
    });

    test('i^i is real, and is e^(-π/2)', () {
      // The classic. If the branch or the sign is wrong this is not real.
      final Complex r = complexPow(const Complex(0, 1), const Complex(0, 1));
      expectComplex(r, math.exp(-math.pi / 2), 0, eps: 1e-12);
    });
  });

  group('trigonometry off the real line', () {
    test('sin(i) = i·sinh(1)', () {
      final double sinh1 = (math.e - 1 / math.e) / 2;
      final Complex got = trig('sin', <MathNode>[
        LiteralNode(text: 'i'),
      ]).evalComplexWith(<String, Complex>{});
      expectComplex(got, 0, sinh1, eps: 1e-12);
    });

    test('cos(i) = cosh(1)', () {
      final double cosh1 = (math.e + 1 / math.e) / 2;
      final Complex got = trig('cos', <MathNode>[
        LiteralNode(text: 'i'),
      ]).evalComplexWith(<String, Complex>{});
      expectComplex(got, cosh1, 0, eps: 1e-12);
    });

    test('and agrees with the real functions on the real line', () {
      for (final double x in <double>[0, 0.7, -1.3, 2.5]) {
        final Complex s = trigOfZ(
          'sin',
        ).evalComplexWith(<String, Complex>{'z': Complex(x, 0)});
        expectComplex(s, math.sin(x), 0, eps: 1e-12);
      }
    });

    test('sin²+cos² is 1 off the real line too', () {
      const Complex z = Complex(1.2, -0.8);
      final Complex s = trigOfZ(
        'sin',
      ).evalComplexWith(<String, Complex>{'z': z});
      final Complex c = trigOfZ(
        'cos',
      ).evalComplexWith(<String, Complex>{'z': z});
      expectComplex(s * s + c * c, 1, 0, eps: 1e-9);
    });
  });

  group('the variable', () {
    test('carries its imaginary part through the arithmetic', () {
      // (1 + 2i)² = -3 + 4i
      expectComplex(evalAt('z^2', z: const Complex(1, 2)), -3, 4);
    });

    test('an unbound name is an error, not a silent zero', () {
      expect(
        () => compile('w+1').evalComplexWith(<String, Complex>{}),
        throwsA(isA<UnboundVariableError>()),
      );
    });
  });

  group('against the real evaluator', () {
    test('the two agree wherever the real one has an answer', () {
      // The complex path must not quietly change what an ordinary expression
      // means — it is the same arithmetic with a part that happens to be zero.
      final Map<String, Expr> cases = <String, Expr>{
        'z^3': compile('z^3'),
        'z+2': compile('z+2'),
        'z*z-1': compile('z*z-1'),
        'sin(z)': trigOfZ('sin'),
      };
      for (final MapEntry<String, Expr> entry in cases.entries) {
        final String src = entry.key;
        for (final double x in <double>[-1.5, 0.4, 2.0]) {
          final Expr e = entry.value;
          final double real = e.evalWith(<String, double>{'z': x});
          final Complex cx = e.evalComplexWith(<String, Complex>{
            'z': Complex(x, 0),
          });
          expect(cx.real, closeTo(real, 1e-9), reason: '$src at $x');
          expect(cx.imag, closeTo(0, 1e-9), reason: '$src at $x');
        }
      }
    });
  });
}
