import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/renderer.dart';

void main() {
  group('Auto-Scroll Logic Tests', () {
    late MathEditorController controller;

    setUp(() {
      controller = MathEditorController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Cursor at end of empty expression should be detected correctly', () {
      // Default expression is [LiteralNode(text: '')]
      final cursor = controller.cursor;
      final expression = controller.expression;

      // Check if cursor is at end
      bool isAtEnd =
          cursor.parentId == null && cursor.index == expression.length - 1;

      if (isAtEnd && expression.isNotEmpty) {
        final lastNode = expression.last;
        if (lastNode is LiteralNode) {
          isAtEnd = cursor.subIndex >= lastNode.text.length;
        }
      }

      expect(
        isAtEnd,
        isTrue,
        reason: 'Cursor should be at end of empty expression',
      );
    });

    test('Cursor at end of expression after typing should be detected', () {
      // Type some characters
      controller.insertCharacter('1');
      controller.insertCharacter('2');
      controller.insertCharacter('3');

      final cursor = controller.cursor;
      final expression = controller.expression;

      // Check if cursor is at end
      bool isAtEnd =
          cursor.parentId == null && cursor.index == expression.length - 1;

      if (isAtEnd && expression.isNotEmpty) {
        final lastNode = expression.last;
        if (lastNode is LiteralNode) {
          isAtEnd = cursor.subIndex >= lastNode.text.length;
        }
      }

      expect(
        isAtEnd,
        isTrue,
        reason: 'Cursor should be at end after typing at end',
      );
    });

    test('Cursor in middle of expression should not be at end', () {
      // Type some characters
      controller.insertCharacter('1');
      controller.insertCharacter('2');
      controller.insertCharacter('3');

      // Move cursor left (to middle)
      // Move cursor left (to middle)
      controller.cursor = controller.cursor.copyWith(
        subIndex: controller.cursor.subIndex - 1,
      );

      final cursor = controller.cursor;
      final expression = controller.expression;

      // Check if cursor is at end
      bool isAtEnd =
          cursor.parentId == null && cursor.index == expression.length - 1;

      if (isAtEnd && expression.isNotEmpty) {
        final lastNode = expression.last;
        if (lastNode is LiteralNode) {
          isAtEnd = cursor.subIndex >= lastNode.text.length;
        }
      }

      expect(
        isAtEnd,
        isFalse,
        reason: 'Cursor should NOT be at end when in middle of text',
      );
    });

    test('Cursor inside nested node should not be at end', () {
      // Create a fraction
      controller.insertCharacter('1');
      controller.insertCharacter('/'); // Creates fraction

      final cursor = controller.cursor;

      // When inside fraction, parentId is set
      bool isAtEnd = cursor.parentId == null;

      expect(
        isAtEnd,
        isFalse,
        reason: 'Cursor inside fraction should NOT trigger auto-scroll to end',
      );
    });

    test('Long expression should allow cursor at end detection', () {
      // Type a long number
      const longNumber = '2349999999922223233';
      for (int i = 0; i < longNumber.length; i++) {
        controller.insertCharacter(longNumber[i]);
      }

      final cursor = controller.cursor;
      final expression = controller.expression;

      // Cursor should be at end
      bool isAtEnd =
          cursor.parentId == null && cursor.index == expression.length - 1;

      if (isAtEnd && expression.isNotEmpty) {
        final lastNode = expression.last;
        if (lastNode is LiteralNode) {
          isAtEnd = cursor.subIndex >= lastNode.text.length;
        }
      }

      expect(
        isAtEnd,
        isTrue,
        reason: 'Cursor should be at end of long expression',
      );

      // Verify expression content
      expect(expression.length, equals(1));
      expect((expression.first as LiteralNode).text, equals(longNumber));
    });

    test('After moving cursor to start, should not be at end', () {
      // Type some characters
      controller.insertCharacter('1');
      controller.insertCharacter('2');
      controller.insertCharacter('3');

      // Move cursor to start
      // Move cursor to start
      controller.cursor = controller.cursor.copyWith(subIndex: 0);

      final cursor = controller.cursor;
      final expression = controller.expression;

      // Check if cursor is at end
      bool isAtEnd =
          cursor.parentId == null && cursor.index == expression.length - 1;

      if (isAtEnd && expression.isNotEmpty) {
        final lastNode = expression.last;
        if (lastNode is LiteralNode) {
          isAtEnd = cursor.subIndex >= lastNode.text.length;
        }
      }

      expect(
        isAtEnd,
        isFalse,
        reason: 'Cursor at start should NOT be detected as at end',
      );
    });
  });
}
