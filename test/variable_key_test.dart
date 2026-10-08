import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The k key, and the rows that give its letters a value.
///
/// It took the ° key's place: ° only ever multiplied by π/180, which π and a
/// fraction already write, and a plot had no way to name a value at all.
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
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return key.currentState!;
  }

  testWidgets('k is on the key, and a, b, p, m and n are behind it', (
    tester,
  ) async {
    final HomePageState state = await pump(tester, <String>['']);
    final Finder key = find.byWidgetPredicate(
      (Widget w) => w is PopupMenuCalcButton && w.buttonText == 'k',
    );
    expect(key, findsOneWidget);
    expect(find.text('°'), findsNothing, reason: 'the degree key is gone');

    final PopupMenuCalcButton k = tester.widget<PopupMenuCalcButton>(key);
    expect(k.menuItems.map((CalcMenuItem i) => i.label), <String>[
      'a',
      'b',
      'p',
      'm',
      'n',
    ]);

    k.onTap!();
    k.menuItems.first.onTap();
    await tester.pump();
    expect(state.rowsOf(0).first.controller.getExpression(), 'ka');
  });

  testWidgets('a row giving a value wears a tuning mark and has no eye', (
    tester,
  ) async {
    await pump(tester, <String>['k=2', 'kx']);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(
      find.byIcon(Icons.error_outline),
      findsNothing,
      reason: 'kx has a value for k, and k = 2 is not a broken curve',
    );
    // The eye is kept for its space but not shown on the value's row.
    final List<bool> eyes = <bool>[
      for (final Element e in find.byType(Visibility).evaluate())
        if (find
            .descendant(
              of: find.byWidget(e.widget),
              matching: find.byIcon(Icons.visibility),
            )
            .evaluate()
            .isNotEmpty)
          (e.widget as Visibility).visible,
    ];
    expect(eyes, <bool>[false, true]);
  });

  testWidgets('a letter with no value marks its row', (tester) async {
    await pump(tester, <String>['kx']);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final Tooltip tip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byIcon(Icons.error_outline),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tip.message, contains('Add a row such as k = 1'));
  });
}
