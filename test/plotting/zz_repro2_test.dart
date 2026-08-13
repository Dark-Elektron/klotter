import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  testWidgets('minimise and restore with several plot cells', (tester) async {
    final texts = <String>['x^2+y^2', '2x', 'sin(x)'];
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': [
          for (final t in texts)
            {
              'expression': jsonEncode([
                {'type': 'literal', 'text': t},
              ]),
            },
        ],
        'activeIndex': 2,
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

    final binding = tester.binding;
    for (int cycle = 0; cycle < 4; cycle++) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 60));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 200));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 60));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 400));

      // Toggle 2D/3D, which flips which layer is offstage.
      final toggles = find.byIcon(Icons.threed_rotation);
      if (toggles.evaluate().isNotEmpty) {
        await tester.tap(toggles.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });
}
