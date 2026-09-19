import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';

/// z̲ can be reached by holding the i key.
///
/// It is the complex variable written as one symbol, and it is the only way to
/// write a complex function — so if the long press does not produce it, complex
/// plotting cannot be reached at all.
void main() {
  testWidgets('holding i offers z̲, and choosing it inserts one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          {'expression': jsonEncode(<Map<String, dynamic>>[])},
        ],
        'activeIndex': 0,
      }),
    });
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);

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

    // i lives on the extras page.
    await tester.drag(find.text('sin').first, const Offset(-350, 0));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('i'), findsWidgets, reason: 'no i key on the extras page');

    // Press, hold, slide onto the item, release — the menu is an overlay that
    // appears on long-press start and picks whatever the finger is over when
    // it lifts. A plain longPress never selects anything.
    final TestGesture hold = await tester.startGesture(
      tester.getCenter(find.text('i').first),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.text('z̲'),
      findsOneWidget,
      reason: 'holding i offered no z̲, so the complex variable is unreachable',
    );

    await hold.moveTo(tester.getCenter(find.text('z̲')));
    await tester.pump(const Duration(milliseconds: 60));
    await hold.up();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final state = tester.state<HomePageState>(find.byType(HomePage));
    expect(
      state.plotNodesForTest(0).whereType<ComplexVariableNode>(),
      isNotEmpty,
      reason: 'sliding onto z̲ and releasing inserted nothing',
    );
  });
}
