import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/settings/settings_provider.dart';

/// An app left alone stops drawing.
///
/// The caret blinked by an animation that ticked on every vsync, so with a
/// caret on screen — which is always — the app drew a full frame 120 times a
/// second doing nothing, the plot re-rasterised in every one. A Galaxy A54
/// drew 526 frames in six idle seconds. The caret is only ever on or off, so
/// it now repaints when it changes and not between.
void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    final SettingsProvider settings = await SettingsProvider.create();
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
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('nothing is drawn between blinks', (tester) async {
    await pump(tester);
    // Past the opening animations, frame by frame — they run on frames, and a
    // single long pump is only one. After that most of each half-period of
    // the blink has no frame due.
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    int idle = 0;
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (!tester.binding.hasScheduledFrame) idle++;
    }
    expect(idle, greaterThan(5), reason: 'frames kept coming with nothing on');
  });

  testWidgets('and the caret still blinks', (tester) async {
    await pump(tester);
    final RenderCursorOverlay caret = tester.renderObject<RenderCursorOverlay>(
      find.byType(CursorOverlay).first,
    );

    // Two samples half a period apart see it in different halves.
    final Set<bool> seen = <bool>{};
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 530));
      seen.add(caret.debugCaretShown);
    }
    expect(seen, <bool>{true, false});
  });
}
