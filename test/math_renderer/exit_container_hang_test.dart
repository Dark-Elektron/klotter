// Regression test for Tier 1 fix 1.1: typing an operator while the cursor is
// inside a container (e.g. an AnsNode) nested in a node type that the cursor
// helpers did not recurse into (root / trig / log / etc.) used to spin
// `_exitContainerIfNeeded` forever, freezing the app (ANR).
//
// Each test both asserts correct cursor exit AND acts as a liveness guard:
// if the infinite loop regresses, the test times out instead of passing.
// A trailing literal gives the caret a valid destination after the composite,
// which is the realistic editing scenario.

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('operator inside AnsNode nested in composite does not hang', () {
    test('ans inside square-root radicand', () {
      final controller = MathEditorController();
      final ans = AnsNode(index: [LiteralNode(text: '0')]);
      final root = RootNode(isSquareRoot: true, radicand: [ans]);
      controller.expression = [root, LiteralNode(text: '')];
      controller.cursor = EditorCursor(
        parentId: ans.id,
        path: 'index',
        index: 0,
        subIndex: 1,
      );

      controller.insertCharacter('+'); // must terminate, not hang

      // Cursor exited the AnsNode (and the whole root) to the top level.
      expect(controller.cursor.parentId, isNot(equals(ans.id)));
      expect(controller.cursor.parentId, isNull);
    });

    test('ans inside trig argument', () {
      final controller = MathEditorController();
      final ans = AnsNode(index: [LiteralNode(text: '0')]);
      final trig = TrigNode(function: 'sin', argument: [ans]);
      controller.expression = [trig, LiteralNode(text: '')];
      controller.cursor = EditorCursor(
        parentId: ans.id,
        path: 'index',
        index: 0,
        subIndex: 1,
      );

      controller.insertCharacter('+');

      expect(controller.cursor.parentId, isNot(equals(ans.id)));
      expect(controller.cursor.parentId, isNull);
    });

    test('ans inside natural-log argument', () {
      final controller = MathEditorController();
      final ans = AnsNode(index: [LiteralNode(text: '0')]);
      final log = LogNode(isNaturalLog: true, argument: [ans]);
      controller.expression = [log, LiteralNode(text: '')];
      controller.cursor = EditorCursor(
        parentId: ans.id,
        path: 'arg',
        index: 0,
        subIndex: 1,
      );

      controller.insertCharacter('+');

      expect(controller.cursor.parentId, isNot(equals(ans.id)));
      expect(controller.cursor.parentId, isNull);
    });

    test('ans at top level exits cleanly (control)', () {
      final controller = MathEditorController();
      final ans = AnsNode(index: [LiteralNode(text: '0')]);
      controller.expression = [ans, LiteralNode(text: '')];
      controller.cursor = EditorCursor(
        parentId: ans.id,
        path: 'index',
        index: 0,
        subIndex: 1,
      );

      controller.insertCharacter('+');

      expect(controller.cursor.parentId, isNull);
    });
  });
}
