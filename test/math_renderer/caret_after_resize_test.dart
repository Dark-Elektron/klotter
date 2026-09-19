import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// The caret follows the expression when the editor's box settles late.
///
/// Each node reports its rect relative to the container, once per structure
/// version. On opening the app a row is built before the panel around it has
/// its final width, and the content is centred — so when the real width
/// arrives every glyph shifts and the reported rects stay where they were.
///
/// The glyphs come from the live layout and look right. The caret comes from
/// the registry, so it alone sits out to the left, and tapping cannot fix it
/// because a tap is resolved against that same registry. Only an edit did,
/// because an edit changes the structure version and makes the nodes report.
void main() {
  Widget host(MathEditorController controller, double width) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: MathEditorInline(controller: controller),
        ),
      ),
    ),
  );

  testWidgets('a width that arrives late still puts the caret on the end', (
    tester,
  ) async {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    controller.expression.addAll(<MathNode>[LiteralNode(text: 'x+y')]);
    controller.moveCursorToEnd();

    // Narrow first, then the real width — a panel settling.
    await tester.pumpWidget(host(controller, 120));
    await tester.pump();
    await tester.pumpWidget(host(controller, 400));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      controller.getContentBounds(),
      isNotNull,
      reason: 'the registry is empty, so nothing can be tapped either',
    );

    // Measured against the glyphs actually on screen, not against the registry
    // the caret itself comes from. Comparing the caret with getContentBounds()
    // proves nothing: both are read from the same reports, so when those are
    // stale the two agree with each other and disagree with the display.
    final Rect editor = tester.getRect(find.byType(MathEditorInline));
    final Rect glyphs = tester.getRect(find.byType(RichText).first);
    final double glyphLeft = glyphs.left - editor.left;
    final double glyphRight = glyphs.right - editor.left;

    final Rect caret = controller.cursorPaintNotifier.rect;
    expect(
      caret.left,
      greaterThanOrEqualTo(glyphLeft - 2),
      reason:
          'caret at ${caret.left}, but the expression is drawn from '
          '$glyphLeft to $glyphRight — the caret is stranded to its left, '
          'placed against the width the row had before it settled',
    );
    expect(
      caret.left,
      lessThanOrEqualTo(glyphRight + 12),
      reason: 'caret at ${caret.left}, expression ends at $glyphRight',
    );
  });

  testWidgets('a box that does not change is left alone', (tester) async {
    // The epoch must move only when the box does. If it advanced on every
    // frame, every node would re-report for ever.
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    controller.expression.addAll(<MathNode>[LiteralNode(text: 'x+y')]);
    controller.moveCursorToEnd();

    await tester.pumpWidget(host(controller, 400));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final Rect settled = controller.cursorPaintNotifier.rect;

    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      controller.cursorPaintNotifier.rect,
      settled,
      reason: 'the caret is still moving with nothing on screen changing',
    );
    expect(controller.getContentBounds(), isNotNull);
  });
}
