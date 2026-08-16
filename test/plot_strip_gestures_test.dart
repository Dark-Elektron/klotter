import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The strip below the expression carries two gestures now: a flick to step
/// one plot, and a hold-and-drag to run through them.
///
/// They share a detector, so the second can take the first's gesture out of
/// the arena — which is worth a test rather than an assumption.
///
/// Pumped by fixed durations rather than settled: the plot keeps a spin going
/// of its own accord, so there is no frame at which the tree is quiet.
void main() {
  Future<SettingsProvider> seed(int cells) async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          for (int i = 0; i < cells; i++)
            {
              'expression': jsonEncode(<Map<String, dynamic>>[
                {'type': 'literal', 'text': '${i + 1}x'},
              ]),
            },
        ],
        'activeIndex': 0,
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

  /// The middle of the swipe strip.
  Offset strip(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey<String>('plot-swipe-strip')));

  testWidgets('a flick still steps to the next plot', (tester) async {
    // The plain gesture, which the scrub sits on top of. Adding the long
    // press to the same detector must not cost the flick its place in the
    // arena.
    final settings = await seed(4);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);
    expect(state.activeIndex, 0);

    await tester.fling(
      find.byKey(const ValueKey<String>('plot-swipe-strip')),
      const Offset(-200, 0),
      1200,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.activeIndex, 1, reason: 'a flick left goes forward');
  });

  testWidgets('and a flick the other way steps back', (tester) async {
    final settings = await seed(4);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    await tester.fling(
      find.byKey(const ValueKey<String>('plot-swipe-strip')),
      const Offset(-200, 0),
      1200,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.activeIndex, 1);

    await tester.fling(
      find.byKey(const ValueKey<String>('plot-swipe-strip')),
      const Offset(200, 0),
      1200,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.activeIndex, 0);
  });

  testWidgets('a swipe that starts with a pause still swipes', (tester) async {
    // The case a fling cannot reach, and the one that was broken. A real
    // thumb rests on the strip for a moment before moving; a long press
    // recogniser sharing the detector would claim the gesture in that moment
    // and the swipe would do nothing. tester.fling moves the pointer at once,
    // so it never saw this.
    final settings = await seed(4);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    final TestGesture gesture = await tester.startGesture(strip(tester));
    await tester.pump(const Duration(milliseconds: 120)); // the hesitation
    // Timestamped, or every move carries the same instant and the velocity
    // tracker sees a gesture that took no time — which reads as no velocity
    // at all. moveBy defaults to Duration.zero, and a test written without
    // this reported a working swipe as broken.
    Duration t = const Duration(milliseconds: 120);
    for (int i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 12);
      await gesture.moveBy(const Offset(-24, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 12));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.activeIndex, 1, reason: 'landed on ${state.activeIndex}');
  });

  testWidgets('a slow drag with no flick does not change the plot', (
    tester,
  ) async {
    // Below the velocity threshold and never held long enough to scrub, so
    // it is neither gesture and must do nothing rather than guess.
    final settings = await seed(4);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    final TestGesture gesture = await tester.startGesture(strip(tester));
    await gesture.moveBy(
      const Offset(-20, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(
      const Offset(-20, 0),
      timeStamp: const Duration(milliseconds: 400),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.activeIndex, 0);
  });

  testWidgets('holding and dragging runs several plots at once', (
    tester,
  ) async {
    // The point of the scrub: one gesture crosses many plots. At the old
    // pitch this drag would have moved by one.
    final settings = await seed(8);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    final TestGesture gesture = await tester.startGesture(strip(tester));
    await tester.pump(const Duration(milliseconds: 500)); // the hold lands
    await gesture.moveBy(
      const Offset(90, 0),
      timeStamp: const Duration(milliseconds: 520),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      state.activeIndex,
      greaterThan(2),
      reason: 'landed on ${state.activeIndex}',
    );
  });

  testWidgets('the page does not move until the finger lifts', (tester) async {
    // Rendering each plot as it is passed over is not affordable, so the
    // scrub moves a readout and the plot is drawn once, on release.
    final settings = await seed(8);
    addTearDown(settings.dispose);
    final state = await pump(tester, settings);

    final TestGesture gesture = await tester.startGesture(strip(tester));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(
      const Offset(90, 0),
      timeStamp: const Duration(milliseconds: 520),
    );
    await tester.pump();

    expect(state.activeIndex, 0, reason: 'the page moved mid-scrub');
    // The readout says where it will land.
    expect(find.textContaining('/ 8'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.activeIndex, isNot(0));
  });
}
