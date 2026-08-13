import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// The action button inserts a [NewlineNode] instead of starting a new cell,
/// so one cell holds several expressions that share a plot.
void main() {
  List<MathNode> lit(String t) => <MathNode>[LiteralNode(text: t)];

  group('PlotExpression.compileAll splits a cell into curves', () {
    test('a cell with no newline yields exactly one curve', () {
      final curves = PlotExpression.compileAll(lit('2x'));
      expect(curves, hasLength(1));
      expect(curves.first.isValid, isTrue);
      expect(curves.first.evaluate(3), closeTo(6, 1e-9));
    });

    test('each line becomes its own curve', () {
      final nodes = <MathNode>[
        LiteralNode(text: '2x'),
        NewlineNode(),
        LiteralNode(text: 'xx'),
        NewlineNode(),
        LiteralNode(text: '5'),
      ];
      final curves = PlotExpression.compileAll(nodes);
      expect(curves, hasLength(3));
      expect(curves[0].evaluate(3), closeTo(6, 1e-9));
      expect(curves[1].evaluate(3), closeTo(9, 1e-9));
      expect(curves[2].evaluate(3), closeTo(5, 1e-9));
    });

    test('blank lines are dropped rather than becoming empty curves', () {
      final nodes = <MathNode>[
        LiteralNode(text: '2x'),
        NewlineNode(),
        NewlineNode(),
        LiteralNode(text: 'xx'),
      ];
      final curves = PlotExpression.compileAll(nodes);
      expect(curves, hasLength(2));
      expect(curves.every((c) => c.isValid), isTrue);
    });

    test('one bad line does not invalidate the others', () {
      final nodes = <MathNode>[
        LiteralNode(text: '2x'),
        NewlineNode(),
        LiteralNode(text: 'q'), // unknown variable
      ];
      final curves = PlotExpression.compileAll(nodes);
      expect(curves, hasLength(2));
      expect(curves[0].isValid, isTrue);
      expect(curves[1].isValid, isFalse);
      expect(curves[1].error, contains('unknown variable'));
    });

    test('a constant line is a plottable horizontal curve', () {
      final curves = PlotExpression.compileAll(lit('7'));
      expect(curves.single.isValid, isTrue);
      expect(curves.single.evaluate(-100), closeTo(7, 1e-9));
      expect(curves.single.evaluate(100), closeTo(7, 1e-9));
    });

    test('an empty cell still yields one (invalid) entry, never zero', () {
      // Callers index [0] for the primary curve, so the list is never empty.
      final curves = PlotExpression.compileAll(<MathNode>[]);
      expect(curves, hasLength(1));
      expect(curves.single.isValid, isFalse);
    });
  });
}
