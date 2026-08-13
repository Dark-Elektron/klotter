import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Flicking forward past the last plot creates a new one — but only when the
/// last one is actually used, or a few flicks leave a row of blank plots.
void main() {
  Future<SettingsProvider> seed(List<String> texts) async {
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
        'activeIndex': texts.length - 1,
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

  /// Flick the strip between the expression and the keypad.
  Future<void> flickForward(WidgetTester tester) async {
    final Finder strip = find.byIcon(Icons.chevron_right);
    expect(strip, findsWidgets, reason: 'the swipe strip should be on screen');
    await tester.fling(strip.first, const Offset(-200, 0), 800);
    // Fixed pumps rather than pumpAndSettle: the plot animates continuously,
    // so the tree never reaches a settled state.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a blank last plot does not spawn another', (tester) async {
    final settings = await seed(<String>['x^2', '']);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    expect(state.count, 2);
    await flickForward(tester);

    expect(
      state.count,
      2,
      reason: 'the last plot is empty, so there is nothing to move on from',
    );
  });

  testWidgets('flicking repeatedly on a blank plot still adds nothing', (
    tester,
  ) async {
    final settings = await seed(<String>['']);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    for (int i = 0; i < 3; i++) {
      await flickForward(tester);
    }
    expect(state.count, 1);
  });

  testWidgets('a used last plot does spawn another', (tester) async {
    final settings = await seed(<String>['x^2']);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    await flickForward(tester);
    expect(
      state.count,
      2,
      reason: 'the last plot has an expression, so forward makes a new one',
    );
  });
}
