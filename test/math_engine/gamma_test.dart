import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_engine/real_functions.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

List<MathNode> lit(String t) => <MathNode>[LiteralNode(text: t)];

/// x! for every x: Γ(x + 1).
///
/// The factorial was known only for whole numbers from 0 up, so `x!` could
/// not be plotted at all: the parser threw, and the row said "Invalid
/// function syntax".
void main() {
  final double sqrtPi = math.sqrt(math.pi);

  group('the gamma function', () {
    test('at the halves and whole numbers', () {
      expect(gamma(0.5), closeTo(sqrtPi, 1e-14));
      expect(gamma(1.5), closeTo(sqrtPi / 2, 1e-14));
      expect(gamma(2.5), closeTo(1.329340388179137, 1e-14));
      expect(gamma(-0.5), closeTo(-2 * sqrtPi, 1e-13));
      expect(gamma(-1.5), closeTo(4 * sqrtPi / 3, 1e-13));
      // Looked up, not approximated.
      expect(gamma(5), 24);
      expect(gamma(21), 2432902008176640000);
    });

    test('between them', () {
      expect(gamma(0.1), closeTo(9.513507698668732, 1e-12));
      expect(gamma(3.7), closeTo(4.170651783796603, 1e-12));
      // Γ(x + 1) = x·Γ(x), through the reflection side too.
      for (final double x in <double>[-3.3, -0.7, 0.3, 1.9, 12.25, 40.6]) {
        expect(gamma(x + 1) / (x * gamma(x)), closeTo(1, 1e-12), reason: '$x');
      }
    });

    test('poles at zero and the negative whole numbers', () {
      for (final double x in <double>[0, -1, -2, -17]) {
        expect(gamma(x), isNaN, reason: '$x');
      }
    });

    test('keeps its whole range, and no more', () {
      expect(gamma(170.5).isFinite, isTrue);
      expect(gamma(171.5).isFinite, isTrue);
      expect(gamma(172.5), double.infinity);
      expect(gamma(-180.5), closeTo(0, 1e-300));
    });

    test('factorial is Γ(x + 1)', () {
      expect(factorial(0.5), closeTo(sqrtPi / 2, 1e-14));
      expect(factorial(3), 6);
      expect(factorial(0), 1);
      expect(factorial(-1), isNaN);
    });

    test('over the complex numbers', () {
      final Complex g = complexGamma(const Complex(0, 1));
      expect(g.real, closeTo(-0.15494982830181069, 1e-13));
      expect(g.imag, closeTo(-0.49801566811835604, 1e-13));
      final Complex h = complexGamma(const Complex(1, 1));
      expect(h.real, closeTo(0.49801566811835604, 1e-13));
      expect(h.imag, closeTo(-0.15494982830181069, 1e-13));
      // Γ(z + 1) = z·Γ(z) on both sides of the reflection.
      for (final Complex z in const <Complex>[
        Complex(-2.3, 0.7),
        Complex(0.2, -1.4),
        Complex(3.1, 2.2),
      ]) {
        final Complex lhs = complexGamma(z + const Complex(1, 0));
        final Complex rhs = z * complexGamma(z);
        expect((lhs - rhs).magnitude / rhs.magnitude, lessThan(1e-12));
      }
      // On the real line it is the real function.
      expect(complexGamma(const Complex(4.5, 0)).real, gamma(4.5));
    });
  });

  group('x! on a plot', () {
    test('plots, where it was an error', () {
      final PlotExpression f = PlotExpression.compile(lit('x!'));
      expect(f.error, isNull);
      expect(f.evaluate(0.5), closeTo(sqrtPi / 2, 1e-12));
      expect(f.evaluate(3), closeTo(6, 1e-12));
      expect(f.evaluate(-0.5), closeTo(sqrtPi, 1e-12));
      expect(f.evaluate(-1), isNaN, reason: 'a pole, drawn as a break');
    });

    test('binds as a factorial does', () {
      // 2·(x!), not (2x)!.
      expect(
        PlotExpression.compile(lit('2x!')).evaluate(3),
        closeTo(12, 1e-12),
      );
      expect(
        PlotExpression.compile(<MathNode>[
          LiteralNode(),
          ParenthesisNode(content: lit('x+1')),
          LiteralNode(text: '!'),
        ]).evaluate(2),
        closeTo(6, 1e-12),
      );
    });

    test('of a value given in another row', () {
      final List<List<MathNode>> rows = <List<MathNode>>[
        lit('k=2.5'),
        lit('k!x'),
      ];
      final PlotDefinitions d = PlotDefinitions.read(rows);
      final PlotExpression f = PlotExpression.compile(rows[1], definitions: d);
      expect(f.error, isNull);
      expect(f.evaluate(1), closeTo(3.323350970447843, 1e-12));
    });

    test('the compiled form agrees with the reference walk', () {
      final Expr e = MathNodeToExpr.convert(lit('x!+(x/2)!'));
      final PlotExpression f = PlotExpression.compile(lit('x!+(x/2)!'));
      for (final double x in <double>[-2.5, -0.3, 0.7, 4.2, 9.9]) {
        expect(
          f.evaluate(x),
          closeTo(e.evalWith(<String, double>{'x': x}), 1e-9),
          reason: '$x',
        );
      }
    });

    test('of the complex variable', () {
      final PlotExpression f = PlotExpression.compile(<MathNode>[
        LiteralNode(),
        ComplexVariableNode(),
        LiteralNode(text: '!'),
      ]);
      expect(f.error, isNull);
      expect(f.isComplex, isTrue);
      final Complex v = f.evaluateComplex(0, 1);
      expect(v.real, closeTo(0.49801566811835604, 1e-12));
      expect(v.imag, closeTo(-0.15494982830181069, 1e-12));
    });

    test('a derivative of it says it cannot be drawn, rather than 0', () {
      final PlotExpression f = PlotExpression.compile(<MathNode>[
        DerivativeNode(
          at: <MathNode>[LiteralNode()],
          body: lit('x!'),
          isDefinite: false,
        ),
      ]);
      expect(f.isValid, isFalse);
      expect(f.error, contains('unresolved'));
    });
  });

  group('exactly', () {
    test('whole numbers stay whole', () {
      final Expr e = MathNodeToExpr.convert(lit('5!'));
      expect(e, isA<IntExpr>());
      expect(e.toDouble(), 120);
    });

    test('a fraction has a value', () {
      final Expr e = MathNodeToExpr.convert(<MathNode>[
        LiteralNode(),
        FractionNode(num: lit('1'), den: lit('2')),
        LiteralNode(text: '!'),
      ]);
      expect(e.toDouble(), closeTo(sqrtPi / 2, 1e-14));
    });

    test('a factorial survives being written out and read back', () {
      // Which is how a derivative at a point substitutes its value.
      final Expr e = MathNodeToExpr.convert(lit('(x+1)!'));
      final Expr back = MathNodeToExpr.convert(e.toMathNode());
      expect(back.structurallyEquals(e), isTrue, reason: '$e came back $back');
    });
  });
}
