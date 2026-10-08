import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/cursor.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// The layout registry says where each node is drawn.
///
/// Taps, the caret and selection are all resolved against it, so a node that
/// is drawn in one place and registered in another is tapped in the wrong
/// place. Nodes used to measure themselves after the frame, and only when
/// their own widget changed — so a node pushed along by a neighbour growing
/// kept its old box.
void main() {
  Widget host(MathEditorController controller) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: MathEditorInline(controller: controller),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Where [text] is drawn, relative to the editor's content box, which is
  /// what the registry measures against.
  Rect drawnRect(WidgetTester tester, MathEditorController c, String text) {
    final RenderBox root =
        c.containerKey!.currentContext!.findRenderObject()! as RenderBox;
    final RenderBox glyph = tester.renderObject<RenderBox>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is RichText &&
            // Spacing aside: an operator after a fraction is padded.
            w.text.toPlainText().replaceAll(' ', '') == text,
      ),
    );
    final Offset topLeft = root.globalToLocal(
      glyph.localToGlobal(Offset.zero),
    );
    return topLeft & glyph.size;
  }

  testWidgets('a node pushed along by its neighbour is found where it is '
      'drawn', (tester) async {
    final MathEditorController c = MathEditorController();
    addTearDown(c.dispose);
    final FractionNode fraction = FractionNode(
      num: <MathNode>[LiteralNode(text: '1')],
      den: <MathNode>[LiteralNode(text: '2')],
    );
    final LiteralNode after = LiteralNode(text: '+5');
    c.setExpression(<MathNode>[fraction, after]);

    await tester.pumpWidget(host(c));
    await settle(tester);
    final Rect before = c.layoutRegistry[after.id]!.rect;

    // Type into the numerator: the fraction widens and pushes "+5" along,
    // while "+5" itself is unchanged — same text, same place in the tree.
    c.cursor = EditorCursor(
      parentId: fraction.id,
      path: 'num',
      index: 0,
      subIndex: 1,
    );
    for (final String digit in '23456789'.split('')) {
      c.insertCharacter(digit);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester);

    final Rect drawn = drawnRect(tester, c, '+5');
    final Rect registered = c.layoutRegistry[after.id]!.rect;
    expect(
      (drawn.left - before.left).abs(),
      greaterThan(5),
      reason: 'the test needs "+5" to have moved',
    );
    expect(
      (registered.left - drawn.left).abs(),
      lessThan(0.5),
      reason:
          '"+5" is drawn at ${drawn.left} but registered at '
          '${registered.left}, so a tap on it lands somewhere else',
    );
  });
}
