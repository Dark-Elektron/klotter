import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Phones are locked to portrait; tablets keep both orientations.
///
/// The lock originally lived in `main()` and read the view size before the
/// first frame, where it is zero — which reads as a phone and locked tablets
/// to portrait too. These tests pin the decision to a real laid-out size.
void main() {
  late SettingsProvider settings;
  late List<List<String>> requested;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    settings = await SettingsProvider.create();

    requested = <List<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            requested.add(List<String>.from(call.arguments as List));
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    settings.dispose();
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a phone is locked to portrait', (tester) async {
    await pumpAt(tester, const Size(360, 800));

    expect(requested, isNotEmpty, reason: 'the lock should have been applied');
    final last = requested.last;
    expect(last, contains('DeviceOrientation.portraitUp'));
    expect(last, isNot(contains('DeviceOrientation.landscapeLeft')));
    expect(last, isNot(contains('DeviceOrientation.landscapeRight')));
  });

  testWidgets('a tablet keeps landscape', (tester) async {
    await pumpAt(tester, const Size(800, 1280));

    expect(requested, isNotEmpty);
    final last = requested.last;
    expect(
      last,
      contains('DeviceOrientation.landscapeLeft'),
      reason: 'tablets must be free to rotate',
    );
    expect(last, contains('DeviceOrientation.landscapeRight'));
  });

  testWidgets('a tablet already in landscape keeps landscape', (tester) async {
    await pumpAt(tester, const Size(1280, 800));

    expect(requested, isNotEmpty);
    expect(requested.last, contains('DeviceOrientation.landscapeLeft'));
  });

  testWidgets('the decision is made once, not on every rebuild', (
    tester,
  ) async {
    await pumpAt(tester, const Size(800, 1280));
    final int afterFirst = requested.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(requested.length, equals(afterFirst));
  });
}
