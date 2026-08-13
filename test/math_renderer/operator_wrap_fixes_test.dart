// Regression tests for fraction-wrapping around a trailing multiply sign and a
// trailing factorial.

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/math_text_style.dart';

void main() {
  FractionNode? firstFraction(List<MathNode> nodes) {
    for (final n in nodes) {
      if (n is FractionNode) return n;
    }
    return null;
  }

  bool listIsEmpty(List<MathNode> list) =>
      list.every((n) => n is LiteralNode && n.text.isEmpty);

  group('division after a multiplication sign', () {
    test('"18·" then / gives 18· []/[] (empty numerator, sign kept)', () {
      final mult = MathTextStyle.multiplySign;
      final controller = MathEditorController();
      controller.expression = [LiteralNode(text: '18$mult')];
      controller.cursor = EditorCursor(index: 0, subIndex: 3);

      controller.insertCharacter('/');

      final frac = firstFraction(controller.expression);
      expect(frac, isNotNull);
      // Numerator is empty (the operand was NOT absorbed).
      expect(listIsEmpty(frac!.numerator), isTrue);
      // The "18" and the multiply sign are preserved outside the fraction.
      final joined =
          controller.expression
              .whereType<LiteralNode>()
              .map((n) => n.text)
              .join();
      expect(joined.contains('18$mult'), isTrue);
    });

    test('(18)· then / keeps the paren outside with an empty fraction', () {
      final mult = MathTextStyle.multiplySign;
      final controller = MathEditorController();
      controller.expression = [
        ParenthesisNode(content: [LiteralNode(text: '18')]),
        LiteralNode(text: mult),
      ];
      controller.cursor = EditorCursor(index: 1, subIndex: 1);

      controller.insertCharacter('/');

      // Parenthesis stays at top level, a fraction with empty numerator follows.
      expect(controller.expression.whereType<ParenthesisNode>().length, 1);
      final frac = firstFraction(controller.expression);
      expect(frac, isNotNull);
      expect(listIsEmpty(frac!.numerator), isTrue);
    });
  });

  group('fraction wrapping of a factorial operand', () {
    test('(19+2)! then / wraps the whole (19+2)! as the numerator', () {
      final controller = MathEditorController();
      controller.expression = [
        ParenthesisNode(content: [LiteralNode(text: '19+2')]),
        LiteralNode(text: '!'),
      ];
      controller.cursor = EditorCursor(index: 1, subIndex: 1);

      controller.insertCharacter('/');

      // The paren moved INTO the fraction numerator (not left outside).
      expect(controller.expression.whereType<ParenthesisNode>(), isEmpty);
      final frac = firstFraction(controller.expression);
      expect(frac, isNotNull);
      expect(frac!.numerator.whereType<ParenthesisNode>().length, 1);
      // The '!' is glued in the numerator, without a spurious multiply sign.
      final numText =
          frac.numerator.whereType<LiteralNode>().map((n) => n.text).join();
      expect(numText.contains('!'), isTrue);
      expect(numText.contains(MathTextStyle.multiplySign), isFalse);
    });
  });
}
