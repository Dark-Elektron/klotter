import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_result_display.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/settings/settings.dart';

/// How `z̲` is drawn.
///
/// It used to be the letter z followed by the combining low line U+0332, which
/// works only if the font composes it. OpenSans does; Rosemary does not, and the
/// mark slid off the glyph the moment the font setting started having an
/// effect — a bug in one feature that only appeared once another was fixed.
///
/// So the mark is drawn by the text engine as an underline instead, which lands
/// correctly in any family.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// Every Text the widget draws, whatever its nesting.
  List<Text> textsIn(WidgetTester tester) =>
      tester.widgetList<Text>(find.byType(Text)).toList();

  tearDown(() => MathTextStyle.setFontFamily('OpenSans'));

  group('in the editor', () {
    testWidgets('it is a plain z, underlined, not a combining mark', (
      tester,
    ) async {
      final controller = MathEditorController();
      addTearDown(controller.dispose);
      controller.setExpression(<MathNode>[ComplexVariableNode()]);

      await tester.pumpWidget(
        host(
          MathRenderer(
            expression: <MathNode>[ComplexVariableNode()],
            rootKey: GlobalKey(),
            controller: controller,
            structureVersion: 0,
            textScaler: TextScaler.noScaling,
          ),
        ),
      );

      final Iterable<Text> zs = textsIn(
        tester,
      ).where((Text t) => (t.data ?? '').contains('z'));
      expect(zs, isNotEmpty, reason: 'the complex variable was not drawn');

      for (final Text z in zs) {
        expect(
          z.data,
          isNot(contains('̲')),
          reason:
              'still using the combining low line, which needs the font to '
              'compose it',
        );
        expect(
          z.style?.decoration,
          TextDecoration.underline,
          reason: 'the mark is gone entirely — this would draw a bare z',
        );
      }
    });

    testWidgets('it is drawn the same way in every font', (tester) async {
      // The failure was font-dependent, so the check has to be too: whatever
      // family is chosen, the glyph must not go back to depending on the font
      // to place a combining mark.
      for (final String family in SettingsScreen.availableFonts) {
        MathTextStyle.setFontFamily(family);
        final controller = MathEditorController();
        addTearDown(controller.dispose);
        controller.setExpression(<MathNode>[ComplexVariableNode()]);

        await tester.pumpWidget(
          host(
            MathRenderer(
              expression: <MathNode>[ComplexVariableNode()],
              rootKey: GlobalKey(),
              controller: controller,
              structureVersion: 0,
              textScaler: TextScaler.noScaling,
            ),
          ),
        );

        final Iterable<Text> zs = textsIn(
          tester,
        ).where((Text t) => (t.data ?? '').contains('z'));
        expect(zs, isNotEmpty, reason: 'nothing drawn in $family');
        for (final Text z in zs) {
          expect(z.data, isNot(contains('̲')), reason: 'in $family');
          expect(
            z.style?.decoration,
            TextDecoration.underline,
            reason: 'in $family',
          );
          expect(
            z.style?.fontFamily,
            family,
            reason: 'the glyph ignored the chosen font',
          );
        }
      }
    });
  });

  group('in the result display', () {
    testWidgets('it is not drawn as a unit vector', (tester) async {
      // The read-only display has its own copy of every case and had none for
      // this node. Because the node extends UnitVectorNode — which is what
      // gives it the editor's rules for an indivisible glyph — it fell into
      // that branch and came out as ẑ: a different symbol meaning a different
      // thing, in the half of the screen that shows the answer.
      await tester.pumpWidget(
        host(
          MathResultDisplay(
            nodes: <MathNode>[ComplexVariableNode()],
            fontSize: 20,
          ),
        ),
      );

      final List<Text> texts = textsIn(tester);
      expect(texts, isNotEmpty, reason: 'nothing was drawn');
      for (final Text t in texts) {
        expect(
          t.data,
          isNot(contains('̂')),
          reason: 'the complex variable was drawn with a circumflex, as ẑ',
        );
      }
      expect(
        texts.any((Text t) => t.style?.decoration == TextDecoration.underline),
        isTrue,
        reason: 'the underline that makes it z̲ is missing',
      );
    });

    testWidgets('a real unit vector still keeps its circumflex', (
      tester,
    ) async {
      // The new case sits ahead of the unit-vector one, so it must not have
      // swallowed it.
      await tester.pumpWidget(
        host(
          MathResultDisplay(
            nodes: <MathNode>[UnitVectorNode('x')],
            fontSize: 20,
          ),
        ),
      );
      expect(
        textsIn(tester).any((Text t) => (t.data ?? '').contains('̂')),
        isTrue,
        reason: 'x̂ lost its hat',
      );
    });
  });
}
