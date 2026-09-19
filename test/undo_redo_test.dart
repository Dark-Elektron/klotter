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
      AppState one(String text, String answer, int active) => AppState(
        cells: <List<RowState>>[
          <RowState>[
            RowState(nodes: <MathNode>[LiteralNode(text: text)], visible: true),
          ],
        ],
        answers: <String>[answer],
        activeIndex: active,
        activeRow: 0,
      );

      final AppState a = one('2+2', '4', 0);
      final AppState b = one('2+2', 'pending', 1);
      final AppState c = one('2+3', '4', 0);

      expect(a.signature, b.signature);
      expect(a.signature, isNot(c.signature));
    });
  });

  group('the signature notices rows', () {
    AppState withRows(List<String> texts, {List<bool>? visible}) => AppState(
      cells: <List<RowState>>[
        <RowState>[
          for (int i = 0; i < texts.length; i++)
            RowState(
              nodes: <MathNode>[LiteralNode(text: texts[i])],
              visible: visible == null || visible[i],
            ),
        ],
      ],
      answers: const <String>[''],
      activeIndex: 0,
      activeRow: 0,
    );

    test('a second row is a different state', () {
      // The whole bug: a cell was remembered by its active row alone, so a
      // second row was invisible to the history. Undo rebuilt the cell with
      // one row and the others were gone.
      expect(
        withRows(<String>['x']).signature,
        isNot(withRows(<String>['x', 'y']).signature),
      );
    });

    test('and so is hiding one', () {
      expect(
        withRows(<String>['x', 'y']).signature,
        isNot(
          withRows(<String>['x', 'y'], visible: <bool>[true, false]).signature,
        ),
      );
    });

    test('every row is carried, not just the first', () {
      final AppState s = withRows(<String>['x', 'y', 'z']);
      expect(s.cells.single.length, 3);
      expect(s.cellCount, 1);
    });
  });

  group('undo keeps the rows of a cell', () {
    testWidgets('undoing an edit does not throw the other rows away', (
      tester,
    ) async {
      // The reported fault: undo emptied the cell of everything but one row,
      // and redo brought back only the row the caret had been in. The history
      // was captured through a map holding each cell's *active* row, so a cell
      // with three rows was remembered as one.
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));

      state.addRowForTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(tester, '2');
      state.addRowForTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(tester, '3');
      expect(
        state.rowCountForTest(0),
        3,
        reason: 'the rows were not created, so this proves nothing',
      );

      await tapKey(tester, '4');
      expect(state.canUndoAppState, isTrue, reason: 'nothing to undo');

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.rowCountForTest(0),
        3,
        reason:
            'undo left ${state.rowCountForTest(0)} rows of 3 — it rebuilt the '
            'cell from a state that only remembered one',
      );
    });

    testWidgets('and redo brings all of them back', (tester) async {
      final settings = await seed('1');
      addTearDown(settings.dispose);
      await pump(tester, settings);

      final state = tester.state<HomePageState>(find.byType(HomePage));
      state.addRowForTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(tester, '2');
      await tapKey(tester, '5');

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));
      state.redoAppState();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.rowCountForTest(0),
        2,
        reason:
            'redo restored ${state.rowCountForTest(0)} rows of 2 — only the '
            'row the caret was in came back',
      );
    });
  });

  group('undo steps one edit at a time', () {
    testWidgets('a keystroke is a step, across cells', (tester) async {
      // The reported sequence: 28x in the first cell, then xy in a second.
      // One undo left a single cell holding "28" — because history was only
      // taken at the end of updateMathEditor, which most edits never call. Two
      // of those five keystrokes were recorded and everything typed after the
      // new cell was added left no trace at all.
      final settings = await seed('');
      addTearDown(settings.dispose);
      await pump(tester, settings);
      final state = tester.state<HomePageState>(find.byType(HomePage));

      await tapKey(tester, '2');
      await tapKey(tester, '8');
      state.addDisplayForTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(tester, 'x');
      await tapKey(tester, 'y');

      expect(state.countForTest, 2, reason: 'the second cell was not added');
      expect(state.textOfCellForTest(1), 'xy');

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.countForTest,
        2,
        reason: 'undo removed a cell instead of a character',
      );
      expect(
        state.textOfCellForTest(1),
        'x',
        reason:
            'undo left "${state.textOfCellForTest(1)}" — it went back further '
            'than the last keystroke',
      );
      expect(
        state.textOfCellForTest(0),
        '28',
        reason: 'the untouched cell was rewritten by an undo of another cell',
      );
    });

    testWidgets('and the caret returns to the cell that was edited', (
      tester,
    ) async {
      final settings = await seed('');
      addTearDown(settings.dispose);
      await pump(tester, settings);
      final state = tester.state<HomePageState>(find.byType(HomePage));

      await tapKey(tester, '2');
      state.addDisplayForTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(tester, 'x');
      await tapKey(tester, 'y');

      state.undoAppState();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.activeIndexForTest,
        1,
        reason: 'undo moved the caret away from the cell it changed',
      );
    });
  });
}
