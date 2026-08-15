import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/renderer.dart';

/// A relation is laid out the same whichever one it is.
///
/// Only `=` was listed as an operator that gets padding, so `x ≥ 2` was spaced
/// as though the ≥ were part of the term beside it while `x = 2` got air on
/// both sides. The two should be indistinguishable in layout.
void main() {
  Future<double> widthOf(WidgetTester tester, String text) async {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    controller.expression = <MathNode>[LiteralNode(text: text)];

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathRenderer(
              expression: controller.expression,
              rootKey: key,
              controller: controller,
              structureVersion: 0,
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(MathRenderer)).width;
  }

  testWidgets('every relation is spaced like equals', (tester) async {
    final double equals = await widthOf(tester, 'x=2');

    for (final String op in <String>['≥', '≤', '>', '<', '≠']) {
      final double w = await widthOf(tester, 'x${op}2');
      // The glyphs differ a little in width; the padding around them should
      // not. A missing pad is worth several pixels, a glyph a couple.
      expect(
        w,
        closeTo(equals, 4.0),
        reason: '"x${op}2" is $w wide against $equals for "x=2"',
      );
    }
  });
}
