// test/math_renderer/ans_index_update_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';

void main() {
  group('Ans Index Auto-Update on Insertion', () {
    test(
      'updates ans indices correctly using real controller implementation',
      () {
        // Setup
        final controller = MathEditorController();

        // expression: "ans0 + ans1"
        controller.expression = [
          AnsNode(index: [LiteralNode(text: '0')]),
          LiteralNode(text: '+'),
          AnsNode(index: [LiteralNode(text: '1')]),
        ];

        // Scenario 1: Insert cell at index 1
        // ans0 remains ans0 (refers to index 0)
        // ans1 becomes ans2 (refers to old index 1, which is now 2)
        controller.updateAnsReferences(1, 1);

        expect(
          MathExpressionSerializer.serialize(controller.expression),
          'ans0+ans2',
        );

        // Scenario 2: Remove cell at index 1 (the one we just "inserted")
        // ans0 remains ans0
        // ans2 becomes ans1
        controller.updateAnsReferences(
          2,
          -1,
        ); // References to cell 2 become references to cell 1

        expect(
          MathExpressionSerializer.serialize(controller.expression),
          'ans0+ans1',
        );
      },
    );

    test('updates nested ans indices', () {
      final controller = MathEditorController();

      // expression: "(ans1)/(ans2^2)"
      controller.expression = [
        ParenthesisNode(
          content: [
            AnsNode(index: [LiteralNode(text: '1')]),
          ],
        ),
        LiteralNode(text: '/'),
        ParenthesisNode(
          content: [
            ExponentNode(
              base: [
                AnsNode(index: [LiteralNode(text: '2')]),
              ],
              power: [LiteralNode(text: '2')],
            ),
          ],
        ),
      ];

      // Insert at index 0. All should increment.
      controller.updateAnsReferences(0, 1);

      expect(
        MathExpressionSerializer.serialize(controller.expression),
        '(ans2)/(ans3^(2))',
      );

      // Remove index 1 (old 0). All should decrement.
      controller.updateAnsReferences(1, -1);

      expect(
        MathExpressionSerializer.serialize(controller.expression),
        '(ans1)/(ans2^(2))',
      );
    });
    group('Removal logic check', () {
      test('decrementing indices above remove point', () {
        final controller = MathEditorController();
        controller.expression = [
          AnsNode(index: [LiteralNode(text: '0')]),
          LiteralNode(text: '+'),
          AnsNode(index: [LiteralNode(text: '2')]),
        ];

        // Remove cell 1.
        // ans0 stays 0.
        // ans2 becomes 1.
        controller.updateAnsReferences(2, -1);

        expect(
          MathExpressionSerializer.serialize(controller.expression),
          'ans0+ans1',
        );
      });
    });
  });
}
