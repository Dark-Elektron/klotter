import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/settings/settings.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The crash report is not offered in a published build.
///
/// It exists so a stack trace can be read back off a device during
/// development. Shipping it puts an internal error and a copy button in front
/// of someone who installed a calculator, which is nobody's idea of a setting.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      // A crash on record, so the section has something to show and its
      // absence is the gate rather than an empty log.
      'last_uncaught_error':
          '2026-08-20T10:39:14\nwhile starting up\nBad state: no size',
    });
    settings = await SettingsProvider.create();
  });

  // Whatever the build actually ships with, so a test that flips the flag
  // cannot leave it flipped for the ones that follow.
  final bool shipped = SettingsScreen.showDiagnostics;

  tearDown(() {
    settings.dispose();
    SettingsScreen.showDiagnostics = shipped;
  });

  Future<void> pump(WidgetTester tester) async {
    // Tall enough for the whole page to be laid out. Settings is a ListView,
    // which only builds the rows in view, so at phone height the section sits
    // below the fold and is not found whether it is meant to be there or not
    // — which made the hidden case pass for entirely the wrong reason.
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a release build shows no diagnostics section', (tester) async {
    SettingsScreen.showDiagnostics = false;
    await pump(tester);

    expect(
      find.text('DIAGNOSTICS'),
      findsNothing,
      reason: 'the crash report is on screen in a published build',
    );
    // And nothing of the report leaks in under another heading.
    expect(find.textContaining('Bad state'), findsNothing);
  });

  testWidgets('and it can still be switched on', (tester) async {
    // The other half: hiding it must not amount to deleting it, or there is
    // nothing left to read a crash with when it is wanted.
    SettingsScreen.showDiagnostics = true;
    await pump(tester);

    expect(
      find.text('DIAGNOSTICS'),
      findsOneWidget,
      reason: 'the crash report is gone even where it is wanted',
    );
  });

  test('it is off unless deliberately switched on', () {
    // The default is what ships, and what runs during ordinary development
    // too. Tying it to kDebugMode looked right and meant the section sat on
    // screen through every hot restart.
    expect(
      SettingsScreen.showDiagnostics,
      isFalse,
      reason: 'the crash report is on by default, so it is on in the app',
    );
  });
}
