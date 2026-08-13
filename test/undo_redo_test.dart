import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/utils/app_state.dart';

/// Undo and redo across ordinary edits.
///
/// The buttons were wired up but nothing recorded a history point except
/// "Clear All", so the undo stack was empty for everything a user actually
/// does and the button did nothing.
void main() {
  Future<SettingsProvider> seed(String text) async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          {
            'expression': jsonEncode(<Map<String, dynamic>>[
              {'type': 'literal', 'text': text},
            ]),
          },
        ],
        'activeIndex': 0,
      }),
    });
    return SettingsProvider.create();
  }

  Future<void> pump(WidgetTester tester, SettingsProvider settings) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
  }

  /// Type [label] on the keypad.
  Future<void> tapKey(WidgetTester tester, String label) async {
    final Finder key = find.text(label);
    expect(key, findsWidgets, reason: 'no keypad button labelled "$label"');
    await tester.tap(key.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  String expressionOf(WidgetTester tester) {
    final state = tester.state<HomePageState>(find.byType(HomePage));
    final nodes = state.mathEditorControllers[0]!.expression;
    return MathExpressionSerializer.serialize(nodes);
  }

  group('history records ordinary edits', () {
    testWidgets('typing makes undo available', (tester) async {
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      expect(
        state.canUndoAppState,
        isFalse,
        reason: 'nothing has been edited yet',
      );

      await tapKey(tester, '7');
      expect(
        state.canUndoAppState,
        isTrue,
        reason: 'a keystroke is an undoable edit',
      );
    });

    testWidgets('undo puts the expression back, redo reapplies it', (
      tester,
    ) async {
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      final String before = expressionOf(tester);

      await tapKey(tester, '7');
      final String after = expressionOf(tester);
      expect(
        after,
        isNot(before),
        reason: 'the keystroke must change the cell',
      );

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      expect(expressionOf(tester), before, reason: 'undo restores the cell');
      expect(state.canRedoAppState, isTrue);

      state.redoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      expect(expressionOf(tester), after, reason: 'redo reapplies the edit');
    });

    testWidgets('several edits undo one at a time', (tester) async {
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      final String s0 = expressionOf(tester);
      await tapKey(tester, '7');
      final String s1 = expressionOf(tester);
      await tapKey(tester, '8');
      final String s2 = expressionOf(tester);

      expect(<String>{s0, s1, s2}, hasLength(3));

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      expect(expressionOf(tester), s1);

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      expect(expressionOf(tester), s0);
    });

    testWidgets('a new edit after undo drops the redo history', (tester) async {
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      await tapKey(tester, '7');
      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.canRedoAppState, isTrue);

      await tapKey(tester, '8');
      expect(
        state.canRedoAppState,
        isFalse,
        reason: 'the branch that was undone is gone once you type again',
      );
    });

    testWidgets('recalculating is not itself an edit', (tester) async {
      // updateMathEditor recomputes every answer and is where history is
      // taken. If the answers counted, every recalculation would look like a
      // change and undo would fill with steps that do nothing.
      final settings = await seed('1+1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      state.updateMathEditor();
      await tester.pump(const Duration(milliseconds: 300));
      state.updateMathEditor();
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.canUndoAppState, isFalse);
    });
  });

  group('the signature tracks expressions only', () {
    test('answers and the active cell do not count as edits', () {
      final AppState a = AppState(
        expressions: <List<MathNode>>[
          <MathNode>[LiteralNode(text: '2+2')],
        ],
        answers: <String>['4'],
        activeIndex: 0,
      );
      final AppState b = AppState(
        expressions: <List<MathNode>>[
          <MathNode>[LiteralNode(text: '2+2')],
        ],
        answers: <String>['pending'],
        activeIndex: 1,
      );
      final AppState c = AppState(
        expressions: <List<MathNode>>[
          <MathNode>[LiteralNode(text: '2+3')],
        ],
        answers: <String>['4'],
        activeIndex: 0,
      );

      expect(a.signature, b.signature);
      expect(a.signature, isNot(c.signature));
    });
  });
}
