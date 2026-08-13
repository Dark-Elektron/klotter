import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Backspace on an already-empty cell removes it, plot and all — unless it is
/// the only one left, which must always survive so the app never shows nothing.
void main() {
  Future<SettingsProvider> seed(List<String> texts, int activeIndex) async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          for (final String t in texts)
            {
              'expression': jsonEncode(<Map<String, dynamic>>[
                {'type': 'literal', 'text': t},
              ]),
            },
        ],
        'activeIndex': activeIndex,
      }),
    });
    return SettingsProvider.create();
  }

  Future<HomePageState> pump(
    WidgetTester tester,
    SettingsProvider settings,
  ) async {
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
    return tester.state<HomePageState>(find.byType(HomePage));
  }

  Future<void> backspace(WidgetTester tester) async {
    await tester.tap(find.text('⌫').first);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an empty cell is removed, taking its plot with it', (
    tester,
  ) async {
    final settings = await seed(<String>['x^2', '2x', ''], 2);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    expect(state.count, 3);
    await backspace(tester);

    expect(state.count, 2, reason: 'the empty cell is gone');
    expect(
      state.mathEditorControllers.length,
      2,
      reason: 'its controllers went with it',
    );
  });

  testWidgets('a cell with content is not removed', (tester) async {
    final settings = await seed(<String>['x^2', '2x'], 1);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    await backspace(tester);
    expect(
      state.count,
      2,
      reason: 'backspace edits the cell, it does not drop',
    );
  });

  testWidgets('the last cell survives backspace on an empty expression', (
    tester,
  ) async {
    final settings = await seed(<String>[''], 0);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    await backspace(tester);
    await backspace(tester);

    expect(state.count, 1, reason: 'there must always be one cell');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the surviving cells keep their own plot panels', (tester) async {
    // The per-cell maps are renumbered when a cell goes. The plot panel keys
    // and saved views were not in that renumbering, so after a removal a cell
    // could be handed the panel key belonging to a different cell — which for
    // a GlobalKey means two panels claiming one key.
    final settings = await seed(<String>['x^2', '', '3x'], 1);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    await backspace(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(state.count, 2);
    expect(tester.takeException(), isNull);
    expect(
      find.byType(InlinePlotPanel),
      findsWidgets,
      reason: 'the remaining cells still have plots',
    );
  });
}
