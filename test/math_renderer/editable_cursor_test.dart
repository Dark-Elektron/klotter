import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// The caret must always end up somewhere the keypad can type.
///
/// A cursor whose index lands on anything but a literal is inert: both
/// `_updateLiteralAtCursor` and `deleteChar` resolve a non-literal and return
/// having done nothing, and the right arrow — whose whole body is a literal
/// branch — cannot get out of it. The keypad looks dead while the app looks
/// fine, which is what made it read as random.
///
/// Several paths could produce one: tapping an atomic symbol, stepping past
/// one, deleting a selection, and restoring a saved row that ends in a
/// composite.
void main() {
  Future<MathEditorController> pumpWith(
    WidgetTester tester,
    List<MathNode> nodes,
  ) async {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    controller.expression
      ..clear()
      ..addAll(nodes);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: MathEditorInline(controller: controller),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return controller;
  }

  /// The node the caret is sitting in, or null when it is nowhere valid.
  MathNode? nodeUnderCursor(MathEditorController c) {
    final List<MathNode> list = c.expression;
    // Every case here keeps the caret at the root, which is what the tests
    // assert about; a nested caret would need the controller's own resolver.
    if (c.cursor.parentId != null) return null;
    if (c.cursor.index < 0 || c.cursor.index >= list.length) return null;
    return list[c.cursor.index];
  }

  group('tapping an atomic symbol', () {
    testWidgets('puts the caret beside it, not on it', (tester) async {
      final controller = await pumpWith(tester, <MathNode>[
        LiteralNode(text: '2'),
        ConstantNode('π'),
        LiteralNode(text: '+1'),
      ]);

      final atom = controller.layoutRegistry.values.firstWhere(
        (i) => i.isAtomic,
      );

      controller.tapAt(atom.rect.center);
      await tester.pump();

      expect(
        nodeUnderCursor(controller),
        isA<LiteralNode>(),
        reason:
            'the caret landed on the constant itself, where nothing can be '
            'typed or deleted',
      );
    });

    testWidgets('and typing then works', (tester) async {
      final controller = await pumpWith(tester, <MathNode>[
        LiteralNode(text: '2'),
        ConstantNode('π'),
        LiteralNode(text: ''),
      ]);

      final atom = controller.layoutRegistry.values.firstWhere(
        (i) => i.isAtomic,
      );

      // The right half, so the caret goes after the symbol.
      controller.tapAt(Offset(atom.rect.right - 1, atom.rect.center.dy));
      await tester.pump();
      controller.insertCharacter('5');
      await tester.pump();

      final text =
          controller.expression
              .whereType<LiteralNode>()
              .map((n) => n.text)
              .join();
      expect(text, contains('5'), reason: 'the key did nothing at all');
    });

    testWidgets('the left half puts it before the symbol', (tester) async {
      final controller = await pumpWith(tester, <MathNode>[
        LiteralNode(text: '2'),
        ConstantNode('π'),
        LiteralNode(text: ''),
      ]);

      final atom = controller.layoutRegistry.values.firstWhere(
        (i) => i.isAtomic,
      );
      final int atomIndex = controller.expression.indexWhere(
        (n) => n is ConstantNode,
      );

      controller.tapAt(Offset(atom.rect.left + 1, atom.rect.center.dy));
      await tester.pump();

      expect(controller.cursor.index, lessThan(atomIndex));
    });
  });

  group('stepping past an atomic symbol', () {
    test('bumps the structure version so the registry is rebuilt', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '2'), ConstantNode('π')]);
      controller.setCursor(const EditorCursor(index: 0, subIndex: 1));

      final int before = controller.structureVersion;
      controller.moveRight();

      expect(
        controller.expression.length,
        3,
        reason: 'an anchor literal should have been made after the constant',
      );
      expect(
        controller.structureVersion,
        greaterThan(before),
        reason:
            'the tree changed, so every node has to re-report its index — '
            'without this the registry stayed one index behind for good',
      );
    });

    test('leaves the caret in a literal', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '2'), ConstantNode('π')]);
      controller.setCursor(const EditorCursor(index: 0, subIndex: 1));

      controller.moveRight();

      expect(
        controller.expression[controller.cursor.index],
        isA<LiteralNode>(),
      );
    });
  });

  group('typing over a selection', () {
    test('replaces it instead of leaving it standing', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '123')]);
      controller.selectAll();

      expect(controller.hasSelection, isTrue);
      controller.insertCharacter('5');

      expect(
        controller.hasSelection,
        isFalse,
        reason:
            'the selection survived the keystroke, so the next backspace '
            'would have deleted it rather than the character just typed',
      );
      expect((controller.expression.first as LiteralNode).text, '5');
    });

    test('a constant key replaces it too', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '123')]);
      controller.selectAll();

      controller.insertConstant('ε₀');

      expect(controller.hasSelection, isFalse);
      final text =
          controller.expression
              .whereType<LiteralNode>()
              .map((n) => n.text)
              .join();
      expect(text, isNot(contains('123')));
    });

    test('one undo puts the replaced text back', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '123')]);
      controller.selectAll();

      controller.insertCharacter('5');
      controller.undo();

      expect((controller.expression.first as LiteralNode).text, '123');
    });
  });

  group('clearing', () {
    test('drops a selection that points at nodes that are gone', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.expression
        ..clear()
        ..addAll(<MathNode>[LiteralNode(text: '123')]);
      controller.selectAll();

      controller.clear();

      expect(controller.hasSelection, isFalse);
    });
  });

  group('restoring a saved row', () {
    test('that ends in a composite still leaves a usable caret', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);

      controller.setExpression(<MathNode>[
        LiteralNode(text: '2'),
        FractionNode(
          num: <MathNode>[LiteralNode(text: '1')],
          den: <MathNode>[LiteralNode(text: '2')],
        ),
      ]);

      expect(
        controller.expression[controller.cursor.index],
        isA<LiteralNode>(),
        reason:
            'the caret sat on the fraction, so the keypad was dead from '
            'launch until it was moved some other way',
      );

      controller.insertCharacter('7');
      final text =
          controller.expression
              .whereType<LiteralNode>()
              .map((n) => n.text)
              .join();
      expect(text, contains('7'));
    });

    test('that ends in a constant still leaves a usable caret', () {
      final controller = MathEditorController();
      addTearDown(controller.dispose);

      controller.setExpression(<MathNode>[
        LiteralNode(text: '2'),
        ConstantNode('π'),
      ]);

      controller.insertCharacter('7');
      final text =
          controller.expression
              .whereType<LiteralNode>()
              .map((n) => n.text)
              .join();
      expect(text, contains('7'));
    });
  });
}
