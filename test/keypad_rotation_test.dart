import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The keypad survives a rotation.
///
/// Reported as intermittent on a real tablet: rotating portrait to landscape
/// sometimes leaves no keypad. This drives the resize directly and does not
/// reproduce it, so it stands as a regression guard rather than a fix — the
/// layout changes shape on rotation (4x15 to 3x20), which is the part that
/// could plausibly go wrong.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a tablet keeps its keys through a rotation and back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    addTearDown(tester.view.reset);

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1500);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    // A few keys from each block, so a whole block going missing is caught.
    void expectKeypad(String when) {
      for (final String key in <String>['7', '0', 'sin', 'log']) {
        expect(
          find.text(key),
          findsWidgets,
          reason: 'the $key key is missing $when',
        );
      }
      expect(tester.takeException(), isNull, reason: 'threw $when');
    }

    expectKeypad('in portrait');

    await pump(tester, const Size(1500, 1000));
    expectKeypad('after rotating to landscape');

    await pump(tester, const Size(1000, 1500));
    expectKeypad('after rotating back to portrait');
  });

  testWidgets('a phone is locked to portrait', (tester) async {
    // _applyOrientationLock allows every orientation only above a 600 shortest
    // side; a phone gets the two portrait ones.
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    addTearDown(tester.view.reset);

    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add(call);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(calls, isNotEmpty, reason: 'no orientation preference was set');
    final List<dynamic> allowed = calls.last.arguments as List<dynamic>;
    expect(allowed, hasLength(2));
    expect(allowed.join(','), contains('portraitUp'));
    expect(allowed.join(','), isNot(contains('landscape')));
  });
}
