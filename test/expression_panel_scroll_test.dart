import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The expression panel shows three rows and scrolls the rest.
///
/// Every row it shows is height taken from the plot above it, so it stops
/// growing at three; the row being typed into is always brought into view.
void main() {
  Future<HomePageState> pump(WidgetTester tester, List<String> rows) async {
    String row(String t) => MathExpressionSerializer.serializeToJson(<MathNode>[
      LiteralNode(text: t),
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode(<String, dynamic>{
        'version': 2,
        'cells': <Map<String, dynamic>>[
          <String, dynamic>{
            'rows': <String>[for (final String t in rows) row(t)],
          },
        ],
        'activeIndex': 0,
      }),
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final GlobalKey<HomePageState> key = GlobalKey<HomePageState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(home: HomePage(key: key)),
      ),
    );
    await settle(tester);
    return key.currentState!;
  }

  Rect rowRect(WidgetTester tester, HomePageState state, int r) {
    final RenderBox box =
        state.rowsOf(0)[r].rowKey.currentContext!.findRenderObject()!
            as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The panel's viewport: the vertical scroller around the rows.
  Rect panelRect(WidgetTester tester) => tester.getRect(
    find.byWidgetPredicate(
      (Widget w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.vertical,
    ),
  );

  testWidgets('five rows show three, and the panel ends where the third does', (
    tester,
  ) async {
    final HomePageState state = await pump(tester, <String>[
      '1x',
      '2x',
      '3x',
      '4x',
      '5x',
    ]);
    final Rect panel = panelRect(tester);
    final Rect first = rowRect(tester, state, 0);
    final Rect third = rowRect(tester, state, 2);
    expect(panel.top, moreOrLessEquals(first.top, epsilon: 1));
    expect(panel.bottom, moreOrLessEquals(third.bottom, epsilon: 1));
    expect(
      rowRect(tester, state, 4).top,
      greaterThanOrEqualTo(panel.bottom),
      reason: 'the fifth row should start out of sight',
    );
  });

  testWidgets('the row typed into is scrolled into view', (tester) async {
    final HomePageState state = await pump(tester, <String>[
      '1x',
      '2x',
      '3x',
      '4x',
      '5x',
    ]);
    state.activeRow = 4;
    // ignore: invalid_use_of_protected_member
    state.setState(() {});
    await settle(tester);
    final Rect panel = panelRect(tester);
    final Rect fifth = rowRect(tester, state, 4);
    expect(fifth.top, greaterThanOrEqualTo(panel.top - 1));
    expect(fifth.bottom, lessThanOrEqualTo(panel.bottom + 1));
  });

  testWidgets(
    'a fourth row never stands the panel taller than three, and is shown',
    (tester) async {
      final HomePageState state = await pump(tester, <String>[
        '1x',
        '2x',
        '3x',
      ]);
      final double three =
          rowRect(tester, state, 2).bottom - rowRect(tester, state, 0).top;
      state.activeRow = 2;
      state.addRow();
      // Frame by frame, through the panel's size animation and the scroll.
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          panelRect(tester).height,
          lessThanOrEqualTo(three + 1),
          reason: 'frame $i: the panel grew past three rows',
        );
      }
      await settle(tester);
      expect(state.rowsOf(0).length, 4);
      final Rect panel = panelRect(tester);
      final Rect fourth = rowRect(tester, state, 3);
      expect(fourth.top, greaterThanOrEqualTo(panel.top - 1));
      expect(fourth.bottom, lessThanOrEqualTo(panel.bottom + 1));
    },
  );

  testWidgets('three rows or fewer take the room they need', (tester) async {
    final HomePageState state = await pump(tester, <String>['1x', '2x']);
    final Rect panel = panelRect(tester);
    expect(
      panel.bottom,
      moreOrLessEquals(rowRect(tester, state, 1).bottom, epsilon: 1),
    );
  });
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
