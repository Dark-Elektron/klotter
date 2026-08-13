import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

void main() {
  group('PlotExpression - scalar sampling', () {
    test('evaluates a linear function at many points', () {
      final p = PlotExpression.compile([LiteralNode(text: '2x')]);
      expect(p.error, isNull);
      expect(p.isValid, isTrue);
      expect(p.evaluate(0), closeTo(0, 1e-12));
      expect(p.evaluate(3), closeTo(6, 1e-12));
      expect(p.evaluate(-2.5), closeTo(-5, 1e-12));
    });

    test('compiles once and is stable across repeated sampling', () {
      final p = PlotExpression.compile([LiteralNode(text: 'xx')]);
      expect(p.error, isNull);
      for (int i = 0; i < 100; i++) {
        final x = i / 10;
        expect(p.evaluate(x), closeTo(x * x, 1e-9));
      }
    });

    test('detects dependence on y', () {
      final flat = PlotExpression.compile([LiteralNode(text: '2x')]);
      expect(flat.usesY, isFalse);

      final surface = PlotExpression.compile([LiteralNode(text: 'xy')]);
      expect(surface.error, isNull);
      expect(surface.usesY, isTrue);
      expect(surface.evaluate(3, 4), closeTo(12, 1e-12));
    });
  });

  group('PlotExpression - refuses to invent values', () {
    // The old MathParser returned 0 for every token it did not recognise, so
    // these expressions rendered as a confident flat line at y = 0.
    test('unknown variable is an error, not zero', () {
      final p = PlotExpression.compile([LiteralNode(text: 'a')]);
      expect(p.isValid, isFalse);
      expect(p.error, contains('unknown variable'));
      expect(p.evaluate(1), isNaN);
    });

    test(
      'indefinite integral depending on x is rejected, not plotted as 0',
      () {
        final nodes = <MathNode>[
          IntegralNode(
            variable: [LiteralNode(text: 'x')],
            lower: [LiteralNode(text: '')],
            upper: [LiteralNode(text: '')],
            body: [LiteralNode(text: 'x')],
            isDefinite: false,
          ),
        ];
        final p = PlotExpression.compile(nodes);
        expect(p.isValid, isFalse, reason: 'must not silently sample to zero');
        expect(p.error, isNotNull);
        expect(p.evaluate(1), isNaN);
        expect(p.evaluate(2), isNaN);
      },
    );

    test('empty expression reports a message', () {
      final p = PlotExpression.compile([]);
      expect(p.isValid, isFalse);
      expect(p.error, equals('Please enter a function'));
    });
  });

  group('PlotExpression - engine features the old parser lacked', () {
    test('a symbolic derivative resolves and plots as its derivative', () {
      // d/dx(x·x) simplifies to 2x, which is a perfectly plottable curve.
      // The old MathParser drew a flat line at zero for this.
      final nodes = <MathNode>[
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'xx')],
          isDefinite: false,
        ),
      ];
      final p = PlotExpression.compile(nodes);
      expect(p.error, isNull);
      expect(p.evaluate(3), closeTo(6, 1e-9));
      expect(p.evaluate(-1.5), closeTo(-3, 1e-9));
    });

    test('a constant-valued definite integral samples as a flat line', () {
      final nodes = <MathNode>[
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final p = PlotExpression.compile(nodes);
      expect(p.error, isNull, reason: '∫₀¹ x dx = 1/2 is a plottable constant');
      expect(p.evaluate(0), closeTo(0.5, 1e-9));
      expect(p.evaluate(99), closeTo(0.5, 1e-9));
    });

    test('physical constants resolve', () {
      final p = PlotExpression.compile([ConstantNode('c₀')]);
      expect(p.error, isNull);
      expect(p.evaluate(0), closeTo(299792458.0, 1.0));
    });

    test('x plus a physical constant stays x-dependent', () {
      final p = PlotExpression.compile([
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        ConstantNode('π'),
      ]);
      expect(p.error, isNull);
      expect(p.evaluate(1) - p.evaluate(0), closeTo(1.0, 1e-9));
    });
  });

  group('Expr.evalWith', () {
    test('mirrors toDouble for variable-free expressions', () {
      final expr = MathNodeToExpr.convert([LiteralNode(text: '2+3')]);
      expect(expr.evalWith(const {}), closeTo(expr.toDouble(), 1e-12));
    });

    test('reports free variables, excluding bound integration variables', () {
      final free =
          MathNodeToExpr.convert([LiteralNode(text: 'xy')]).freeVariables;
      expect(free, containsAll(<String>['x', 'y']));
    });

    test('throws UnboundVariableError rather than guessing', () {
      final expr = MathNodeToExpr.convert([LiteralNode(text: 'x')]);
      expect(
        () => expr.evalWith(const {}),
        throwsA(isA<UnboundVariableError>()),
      );
    });
  });
}
