import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';

/// u and v as parameters.
///
/// A parametric line is *swept* by its parameters and returns a position, so
/// it cannot also be a function of where it already is. That is the difference
/// between `y x̂ − x ŷ`, an arrow at every point of the plane, and
/// `cos(u) x̂ + sin(u) ŷ`, one point whose position depends on u — sweep u and
/// it traces a circle.
void main() {
  PlotExpression fn(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  group('the parameters compile', () {
    test('u alone is a curve parameter', () {
      final e = fn('2u');
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isParametric, isTrue);
      expect(e.isParametricSurface, isFalse);
      expect(e.evaluateAt(u: 3), closeTo(6, 1e-9));
    });

    test('u and v together sweep a surface', () {
      final e = fn('u*v');
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isParametricSurface, isTrue);
      expect(e.evaluateAt(u: 3, v: 4), closeTo(12, 1e-9));
    });

    test('an ordinary expression is not parametric', () {
      expect(fn('x^2').isParametric, isFalse);
    });
  });

  group('parameters are not coordinates', () {
    test('mixing u with x is refused', () {
      final e = fn('u+x');
      expect(e.isValid, isFalse);
      expect(e.error, contains('parameters'));
    });

    test('mixing v with r is refused too', () {
      final e = fn('v+r');
      expect(e.isValid, isFalse);
      expect(e.error, contains('parameters'));
    });

    test('an unknown name beside u is still named', () {
      final e = fn('u+q');
      expect(e.isValid, isFalse);
      expect(e.error, contains('q'));
    });
  });

  group('a position written with unit vectors', () {
    test('cos(u)x̂ + sin(u)ŷ is a parametric curve, not a field', () {
      final f = VectorFieldParser.fromNodes(<MathNode>[
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
        UnitVectorNode('y'),
      ]);
      expect(f, isNotNull);
      expect(f!.error, isNull, reason: f.error);
      expect(f.isParametric, isTrue);
      expect(f.isParametricSurface, isFalse);

      // Sweeping u traces the unit circle.
      expect(f.xComponent!.evaluateAt(u: 0), closeTo(1, 1e-9));
      expect(f.yComponent!.evaluateAt(u: 0), closeTo(0, 1e-9));
      expect(f.xComponent!.evaluateAt(u: 1.5707963268), closeTo(0, 1e-9));
      expect(f.yComponent!.evaluateAt(u: 1.5707963268), closeTo(1, 1e-9));
    });

    test('a genuine vector field is not mistaken for one', () {
      final f = VectorFieldParser.fromNodes(<MathNode>[
        LiteralNode(text: 'y'),
        UnitVectorNode('x'),
      ]);
      expect(f!.error, isNull, reason: f.error);
      expect(f.isParametric, isFalse);
    });
  });
}
