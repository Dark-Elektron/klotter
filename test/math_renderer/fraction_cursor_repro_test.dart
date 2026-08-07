import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/renderer.dart';

void main() {
  group('Fraction Cursor Reproduction', () {
    late MathEditorController controller;

    setUp(() {
      controller = MathEditorController();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: MathEditorInline(
                controller: controller,
                showCursor: false,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Verify buffers are added when wrapping parenthesis into fraction',
      (tester) async {
        // 1. Create a parenthesis node at root followed by an empty literal
        final paren = ParenthesisNode(content: [LiteralNode(text: '23')]);
        controller.expression = [paren, LiteralNode(text: '')];
        // Position cursor at the very beginning of the empty literal
        controller.cursor = EditorCursor(
          parentId: null,
          path: null,
          index: 1, // At the second node (the empty literal)
          subIndex: 0,
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        // 2. Press '/' to wrap it into a fraction
        controller.insertCharacter('/');
        await tester.pump();

        // Verify the fraction structure now has literals in the numerator
        expect(controller.expression[0], isA<FractionNode>());
        final frac = controller.expression[0] as FractionNode;
        expect(
          frac.numerator.length,
          3,
          reason: 'Numerator should have Literal, Parenthesis, Literal',
        );
        expect(
          frac.numerator[0],
          isA<LiteralNode>(),
          reason: 'First node should be LiteralNode',
        );
        expect(
          frac.numerator[2],
          isA<LiteralNode>(),
          reason: 'Last node should be LiteralNode',
        );

        // 3. Verify hit testing works at the edges
        final text23 = find.text('23', findRichText: true);
        final Offset textCenter = tester.getCenter(text23);

        // Tap Left
        final Offset tapLeft = textCenter - const Offset(50, 0);
        await tester.tapAt(tapLeft);
        await tester.pump(const Duration(milliseconds: 500));

        expect(controller.cursor.parentId, frac.id);
        expect(controller.cursor.path, 'num');
        expect(controller.cursor.index, 0);

        // Tap Right
        final Offset tapRight = textCenter + const Offset(50, 0);
        await tester.tapAt(tapRight);
        await tester.pump(const Duration(milliseconds: 500));

        expect(controller.cursor.parentId, frac.id);
        expect(controller.cursor.path, 'num');
        expect(controller.cursor.index, 2);
      },
    );
  });
}
