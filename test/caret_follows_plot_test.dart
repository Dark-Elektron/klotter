import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';

/// A plot shows its caret when it is swiped to.
///
/// The row the caret was in was one number for the whole app, so after typing
/// in the third row of one plot and swiping to a plot with one row, it pointed
/// past that plot's last row: no caret anywhere, while the keys typed into its
/// first row. Each plot keeps its own now.
void main() {
  testWidgets(
    'swiping to a plot with fewer rows shows its caret, and swiping back finds the row left',
    (tester) async {
      String row(String t) =>
          MathExpressionSerializer.serializeToJson([LiteralNode(text: t)]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
        'calculator_cells': jsonEncode({
          'version': 2,
          'cells': [
            {
              'rows': [row('2x'), row('3x'), row('4x')],
            },
            {
              'rows': [row('5x')],
            },
          ],
          'activeIndex': 0,
        }),
      });
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final key = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(home: HomePage(key: key)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final state = key.currentState!;
      // The caret into the third row, as a tap would put it.
      state.activeRow = 2;
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      await tester.pump(const Duration(milliseconds: 100));
      await tester.fling(
        find.byKey(const ValueKey<String>('plot-swipe-strip')),
        const Offset(-300, 0),
        1500,
      );
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.activeIndex, 1);
      final Iterable<MathEditorInline> second = tester
          .widgetList<MathEditorInline>(find.byType(MathEditorInline))
          .where((e) => e.controller == state.rowsOf(1).first.controller);
      expect(
        second.single.showCursor,
        isTrue,
        reason: 'no caret on the plot swiped to',
      );

      await tester.fling(
        find.byKey(const ValueKey<String>('plot-swipe-strip')),
        const Offset(300, 0),
        1500,
      );
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.activeIndex, 0);
      expect(
        state.activeRow,
        2,
        reason: 'the first plot keeps the row it was left on',
      );
    },
  );
}
