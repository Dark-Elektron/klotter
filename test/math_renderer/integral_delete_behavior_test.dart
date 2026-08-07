import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Integral Delete Behavior', () {
    test(
      'backspace in integral variable deletes variable before jumping to body',
      () {
        final controller = MathEditorController();
        final integral = IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: '')],
        );

        controller.expression = [integral];
        controller.cursor = EditorCursor(
          parentId: integral.id,
          path: 'var',
          index: 0,
          subIndex: 0,
        );

        controller.deleteChar();
        expect((integral.variable.first as LiteralNode).text, equals(''));
        expect(controller.cursor.path, equals('var'));

        controller.deleteChar();
        expect(controller.cursor.path, equals('body'));
      },
    );

    test(
      'multi-character integral variable is deleted one character at a time',
      () {
        final controller = MathEditorController();
        final integral = IntegralNode(
          variable: [LiteralNode(text: 'xy')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: '')],
        );

        controller.expression = [integral];
        controller.cursor = EditorCursor(
          parentId: integral.id,
          path: 'var',
          index: 0,
          subIndex: 0,
        );

        controller.deleteChar();
        expect((integral.variable.first as LiteralNode).text, equals('x'));
        expect(controller.cursor.path, equals('var'));

        controller.deleteChar();
        expect((integral.variable.first as LiteralNode).text, equals(''));
        expect(controller.cursor.path, equals('var'));

        controller.deleteChar();
        expect(controller.cursor.path, equals('body'));
      },
    );

    test('backspace from after integral enters variable before body', () {
      final controller = MathEditorController();
      final integral = IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '')],
        upper: [LiteralNode(text: '')],
        body: [LiteralNode(text: 'x^2')],
      );

      controller.expression = [integral, LiteralNode(text: '')];
      controller.cursor = const EditorCursor(
        parentId: null,
        path: null,
        index: 1,
        subIndex: 0,
      );

      controller.deleteChar();

      expect(controller.cursor.parentId, equals(integral.id));
      expect(controller.cursor.path, equals('var'));
      expect(controller.cursor.subIndex, equals(1));
    });
  });
}
