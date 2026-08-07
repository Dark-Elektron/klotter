import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/expression_selection.dart';
import 'package:klotter/math_renderer/selection_wrapper.dart';

void main() {
  group('Selection Wrapping Regression Tests', () {
    late MathEditorController controller;

    setUp(() {
      controller = MathEditorController();
    });

    test('Wrap single fraction selection in parenthesis', () {
      // Setup: [FractionNode]
      final fraction = FractionNode(
        num: [LiteralNode(text: "1")],
        den: [LiteralNode(text: "2")],
      );
      controller.expression = [fraction];

      // Select the fraction
      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 0, charIndex: 1),
        ),
      );

      controller.insertCharacter('(');

      // Verify structure: [Literal, Parenthesis([Literal, Fraction, Literal]), Literal]
      // Because we now unconditionally insert literals, there should be 3 nodes.

      expect(controller.expression.length, 3);
      expect(controller.expression[0], isA<LiteralNode>());
      expect((controller.expression[0] as LiteralNode).text, isEmpty);

      expect(controller.expression[1], isA<ParenthesisNode>());
      final paren = controller.expression[1] as ParenthesisNode;
      expect(paren.content.length, greaterThanOrEqualTo(1));

      expect(controller.expression[2], isA<LiteralNode>());
      expect((controller.expression[2] as LiteralNode).text, isEmpty);
    });

    test('Wrap Fraction followed by Literal', () {
      // Setup: [FractionNode, LiteralNode("abc")]
      final fraction = FractionNode(
        num: [LiteralNode(text: "1")],
        den: [LiteralNode(text: "2")],
      );
      controller.expression = [fraction, LiteralNode(text: "abc")];

      // Select Fraction (0) and Literal (1) fully
      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 1, charIndex: 3),
        ),
      );

      controller.insertCharacter('(');

      // Should be: [Literal, Paren([Fraction, Literal("abc")]), Literal]
      // Literal[0] empty (prefix of Fraction)
      // Literal[2] empty (suffix of "abc")

      expect(controller.expression, hasLength(3));

      expect(controller.expression[0], isA<LiteralNode>());
      expect((controller.expression[0] as LiteralNode).text, isEmpty);

      expect(controller.expression[1], isA<ParenthesisNode>());
      final paren = controller.expression[1] as ParenthesisNode;
      expect(paren.content.length, 3); // Literal(""), Fraction, Literal("abc")

      expect(controller.expression[2], isA<LiteralNode>());
      expect((controller.expression[2] as LiteralNode).text, isEmpty);
    });

    test('Wrap SummationNode in parenthesis', () {
      final sum = SummationNode(
        variable: [LiteralNode(text: "i")],
        lower: [LiteralNode(text: "1")],
        upper: [LiteralNode(text: "n")],
        body: [LiteralNode(text: "i^2")],
      );
      controller.expression = [sum];

      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 0, charIndex: 1),
        ),
      );

      controller.insertCharacter('(');

      expect(controller.expression[1], isA<ParenthesisNode>());
      final paren = controller.expression[1] as ParenthesisNode;
      expect(paren.content.any((n) => n is SummationNode), isTrue);
    });

    test('Wrap IntegralNode in RootNode', () {
      final integral = IntegralNode(
        variable: [LiteralNode(text: "x")],
        lower: [LiteralNode(text: "0")],
        upper: [LiteralNode(text: "1")],
        body: [LiteralNode(text: "x")],
      );
      controller.expression = [integral];

      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 0, charIndex: 1),
        ),
      );

      // RootNode is usually 'r' or via specific button, but SelectionWrapper has wrapInSquareRoot
      final wrapper = SelectionWrapper(controller);
      wrapper.wrapInSquareRoot();

      expect(controller.expression[1], isA<RootNode>());
      final root = controller.expression[1] as RootNode;
      expect(root.radicand.any((n) => n is IntegralNode), isTrue);
    });

    test('Wrap DerivativeNode in TrigNode', () {
      final derivative = DerivativeNode(
        variable: [LiteralNode(text: "x")],
        body: [LiteralNode(text: "x^2")],
      );
      controller.expression = [derivative];

      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 0, charIndex: 1),
        ),
      );

      final wrapper = SelectionWrapper(controller);
      wrapper.wrapInTrig('sin');

      expect(controller.expression[1], isA<TrigNode>());
      final trig = controller.expression[1] as TrigNode;
      expect(trig.function, 'sin');
      expect(trig.argument.any((n) => n is DerivativeNode), isTrue);
    });
  });
}
