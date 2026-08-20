import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/cell_persistence_service.dart';
import 'package:klotter/settings/settings_provider.dart';

/// When the app writes, and what survives being closed.
///
/// Every edit used to write immediately — a platform round trip per character.
/// Debouncing that is only safe if the ways *out* of the app flush first, and
/// if the changes worth never losing do not wait at all. Adding a row is one of
/// those: it is rare, and losing it is exactly what was reported.
void main() {
  Future<HomePageState> boot(WidgetTester tester) async {
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
    await tester.pump(const Duration(milliseconds: 800));
    return key.currentState!;
  }

  Future<int> savedRowCount() async {
    final List<CellData> cells = await CellPersistence.loadCells();
    if (cells.isEmpty) return 0;
    return cells.first.rowsJson.length;
  }

  testWidgets('adding a row is written without waiting', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    final HomePageState state = await boot(tester);
    state.rowsOf(0).first.controller.insertCharacter('2');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('\u2318'));
    // Deliberately shorter than the debounce: a structural change must not sit
    // in a timer waiting to be written.
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.rowsOf(0), hasLength(2));

    await tester.runAsync(() async {
      expect(
        await savedRowCount(),
        2,
        reason: 'the new row was still sitting in the debounce',
      );
    });
  });

  testWidgets('backgrounding flushes a pending edit', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    final HomePageState state = await boot(tester);
    state.rowsOf(0).first.controller.insertCharacter('7');
    // Not long enough for the timer; the app is about to be backgrounded.
    await tester.pump(const Duration(milliseconds: 50));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    await tester.runAsync(() async {
      final List<CellData> cells = await CellPersistence.loadCells();
      expect(cells, isNotEmpty, reason: 'nothing was written on pause');
      expect(
        cells.first.rowsJson.first,
        contains('7'),
        reason: 'the pending edit was lost when the app was backgrounded',
      );
    });
  });
}
