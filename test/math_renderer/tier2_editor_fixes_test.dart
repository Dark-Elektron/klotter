// Regression tests for the Tier 2 editor fixes.
//
//   2.1 arrow keys can enter/cross all node types
//   2.2 backspace positions correctly past a composite sibling
//   2.3 deleteSelection keeps the trailing tail (composite selected right-edge)
//   2.4 deleting a single composite merges the surrounding literals
//   2.6 one undo entry per keystroke; ')' creates none
//   2.7 paste works when the cursor is on a composite node
//   2.8 undo snapshot clamps a stale cursor parent instead of dangling

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/expression_selection.dart';

void main() {
  group('2.1 arrow navigation across all node types', () {
    test('moveRight enters a TrigNode argument', () {
      final controller = MathEditorController();
      final trig = TrigNode(function: 'sin', argument: [LiteralNode(text: 'x')]);
      controller.expression = [LiteralNode(text: ''), trig, LiteralNode(text: '')];
      controller.cursor = const EditorCursor(index: 0, subIndex: 0);

      controller.moveRight();

      expect(controller.cursor.parentId, equals(trig.id));
    });

    test('moveLeft enters a RootNode radicand from the right', () {
      final controller = MathEditorController();
      final root = RootNode(
        isSquareRoot: true,
        radicand: [LiteralNode(text: '9')],
      );
      controller.expression = [root, LiteralNode(text: '')];
      controller.cursor = const EditorCursor(index: 1, subIndex: 0);

      controller.moveLeft();

      expect(controller.cursor.parentId, equals(root.id));
      expect(controller.cursor.path, equals('radicand'));
    });

    test('moveRight crosses a ConstantNode', () {
      final controller = MathEditorController();
      controller.expression = [
        LiteralNode(text: '2'),
        ConstantNode('π'),
        LiteralNode(text: 'x'),
      ];
      controller.cursor = const EditorCursor(index: 0, subIndex: 1);

      controller.moveRight();

      expect(controller.cursor.parentId, isNull);
      expect(controller.cursor.index, equals(2)); // landed on the trailing literal
    });

    test('moveLeft crosses a ConstantNode', () {
      final controller = MathEditorController();
      controller.expression = [
        LiteralNode(text: 'x'),
        ConstantNode('π'),
        LiteralNode(text: '2'),
      ];
      controller.cursor = const EditorCursor(index: 2, subIndex: 0);

      controller.moveLeft();

      expect(controller.cursor.index, equals(0));
      expect(controller.cursor.subIndex, equals(1)); // end of "x"
    });
  });

  group('2.3 deleteSelection preserves trailing text', () {
    test('selecting from the right edge of a composite keeps the tail', () {
      final controller = MathEditorController();
      final root = RootNode(
        isSquareRoot: true,
        radicand: [LiteralNode(text: '9')],
      );
      controller.expression = [root, LiteralNode(text: 'abcd')];
      // Selection starts at the right edge of the root (charIndex 1) and runs
      // to the middle of "abcd" (charIndex 2), so "cd" must survive.
      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 0, charIndex: 1),
          end: SelectionAnchor(nodeIndex: 1, charIndex: 2),
        ),
      );

      controller.deleteSelection();

      // Root kept, and the surviving "cd" tail is re-attached.
      expect(controller.expression.whereType<RootNode>().length, equals(1));
      final literals = controller.expression
          .whereType<LiteralNode>()
          .map((n) => n.text)
          .join();
      expect(literals, contains('cd'));
    });
  });

  group('2.4 deleting a single composite merges surrounding literals', () {
    test('literals around the deleted node are merged with caret at the join', () {
      final controller = MathEditorController();
      final fraction = FractionNode(
        num: [LiteralNode(text: '1')],
        den: [LiteralNode(text: '2')],
      );
      controller.expression = [
        LiteralNode(text: 'ab'),
        fraction,
        LiteralNode(text: 'cd'),
      ];
      controller.setSelection(
        SelectionRange(
          start: SelectionAnchor(nodeIndex: 1, charIndex: 0),
          end: SelectionAnchor(nodeIndex: 1, charIndex: 1),
        ),
      );

      controller.deleteSelection();

      expect(controller.expression, hasLength(1));
      expect(controller.expression.first, isA<LiteralNode>());
      expect((controller.expression.first as LiteralNode).text, equals('abcd'));
      expect(controller.cursor.index, equals(0));
      expect(controller.cursor.subIndex, equals(2)); // between "ab" and "cd"
    });
  });

  group('2.6 undo granularity', () {
    test('inserting ans creates exactly one undo entry', () {
      final controller = MathEditorController();
      controller.expression = [LiteralNode(text: '')];
      controller.cursor = const EditorCursor(index: 0, subIndex: 0);
      expect(controller.canUndo, isFalse);

      controller.insertCharacter('ans');
      expect(
        controller.expression.whereType<AnsNode>().length,
        greaterThan(0),
      );

      controller.undo();
      // A single keystroke must be a single undo; the stack is now empty.
      expect(controller.canUndo, isFalse);
      expect(controller.expression.whereType<AnsNode>(), isEmpty);
    });

    test("')' makes no structural change and no undo entry", () {
      final controller = MathEditorController();
      final paren = ParenthesisNode(content: [LiteralNode(text: 'x')]);
      controller.expression = [paren];
      controller.cursor = EditorCursor(
        parentId: paren.id,
        path: 'content',
        index: 0,
        subIndex: 1,
      );
      expect(controller.canUndo, isFalse);

      controller.insertCharacter(')');

      expect(controller.canUndo, isFalse); // pure cursor move, no snapshot
    });
  });

  group('2.7 paste on a composite node', () {
    tearDown(() => MathEditorController.setClipboard(null));

    test('pasting with the cursor on a composite inserts the content', () {
      final controller = MathEditorController();
      final fraction = FractionNode(
        num: [LiteralNode(text: '1')],
        den: [LiteralNode(text: '2')],
      );
      controller.expression = [fraction];
      controller.cursor = const EditorCursor(index: 0, subIndex: 0);

      MathEditorController.setClipboard(
        const MathClipboard(nodes: [], leadingText: '9'),
      );

      controller.pasteClipboard();

      final literals = controller.expression
          .whereType<LiteralNode>()
          .map((n) => n.text)
          .join();
      expect(literals, contains('9')); // previously pasted nothing
    });
  });

  group('2.8 undo snapshot clamps a stale cursor parent', () {
    test('a parentId absent from the tree resets to root', () {
      final state = EditorState.capture(
        [LiteralNode(text: 'x')],
        const EditorCursor(
          parentId: 'does-not-exist',
          path: 'num',
          index: 0,
          subIndex: 0,
        ),
      );

      expect(state.cursor.parentId, isNull);
      expect(state.cursor.index, equals(0));
    });

    test('a valid parentId is remapped to the copied node', () {
      final frac = FractionNode(
        num: [LiteralNode(text: '1')],
        den: [LiteralNode(text: '2')],
      );
      final state = EditorState.capture(
        [frac],
        EditorCursor(parentId: frac.id, path: 'num', index: 0, subIndex: 0),
      );

      // Remapped to the *copied* fraction, not the original id.
      expect(state.cursor.parentId, isNotNull);
      expect(state.cursor.parentId, isNot(equals(frac.id)));
      expect(state.cursor.path, equals('num'));
    });
  });
}
