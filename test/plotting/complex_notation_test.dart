import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// The ways a complex number gets written, all of which have to plot.
///
/// `x + iy` is the definition, and it did not plot: `i` reaches the compiler
/// as a variable when it sits against another symbol, and was rejected as
/// unknown before the complex path could run.
void main() {
  PlotExpression compile(String source) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: source)]);

  group('the identity, written every ordinary way', () {
    for (final String source in <String>['x+iy', 'x+yi', 'z+0i']) {
      test('$source plots', () {
        final e = compile(source);
        expect(e.isValid, isTrue, reason: e.error);
        expect(e.isComplex, isTrue, reason: '$source is not seen as complex');
      });

      test('$source is the identity', () {
        // f(1 + 2i) = 1 + 2i, whichever way it was typed.
        final w = compile(source).evaluateComplex(1, 2);
        expect(w.real, closeTo(1, 1e-9), reason: source);
        expect(w.imag, closeTo(2, 1e-9), reason: source);
      });
    }
  });

  group('i is the unit, not a variable', () {
    test('on its own it is i', () {
      final w = compile('i').evaluateComplex(0, 0);
      expect(w.real, closeTo(0, 1e-9));
      expect(w.imag, closeTo(1, 1e-9));
    });

    test('and squares to -1 wherever it is sampled', () {
      final w = compile('i^2').evaluateComplex(3, -7);
      expect(w.real, closeTo(-1, 1e-9));
      expect(w.imag, closeTo(0, 1e-9));
    });

    test('so it is never reported as an unknown variable', () {
      for (final String source in <String>['x+iy', 'i', '2i+x', 'yi']) {
        expect(
          compile(source).error,
          isNull,
          reason: '$source was rejected: ${compile(source).error}',
        );
      }
    });
  });

  group('a genuinely unknown name is still rejected', () {
    test('even in a complex line', () {
      // The guard has to keep working, or a typo becomes a silent zero.
      final e = compile('x+iy+q');
      expect(e.isValid, isFalse);
      expect(e.error, contains('q'));
    });
  });

  group('this z is not the coordinate', () {
    test('a complex line may use z with x and y at once', () {
      // An ordinary line is refused z alongside x or y, because there the
      // third coordinate is the answer rather than an input. A complex line
      // has no third coordinate — the plane is its whole domain — so the same
      // rule would reject the definition of a complex number.
      final e = compile('z+x+iy');
      expect(e.isValid, isTrue, reason: e.error);
    });

    test('while an ordinary line is still refused it', () {
      final e = compile('x+z');
      expect(e.isValid, isFalse);
      expect(e.error, contains('add an ='));
    });
  });
}
