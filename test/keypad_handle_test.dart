import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The handle between the plot strip and the keypad folds the keypad away,
/// giving its height to the plot, and brings it back.
///
/// Pumped by fixed durations rather than settled, as the other full-app tests
/// are: a plot can keep itself animating, so the tree is never quiet.
void main() {
  Future<SettingsProvider> seed() async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          {
            'expression': jsonEncode(<Map<String, dynamic>>[
              {'type': 'literal', 'text': '2x'},
            ]),
          },
        ],
        'activeIndex': 0,
      }),
    });
    return SettingsProvider.create();
  }

  Future<HomePageState> pump(WidgetTester tester) async {
    final SettingsProvider settings = await seed();
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
    return tester.state<HomePageState>(find.byType(HomePage));
  }

  final Finder handle = find.byKey(const ValueKey<String>('keypad-handle'));
  final Finder strip = find.byKey(const ValueKey<String>('plot-swipe-strip'));

  /// Long enough for either direction of the slide to finish.
  ///
  /// Two pumps: a ticker counts from the first frame after it starts, so a
  /// single long pump only reaches the slide's opening frame.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double plotHeight(WidgetTester tester) =>
      tester.getSize(find.byType(InlinePlotPanel)).height;

  /// How much of the keypad is on screen: the folding box's own height.
  double keypadShowing(WidgetTester tester) => tester
      .getSize(
        find.ancestor(
          of: find.byType(CalculatorKeypad),
          matching: find.byType(SizeTransition),
        ),
      )
      .height;

  testWidgets('the handle sits between the plot strip and the keypad', (
    tester,
  ) async {
    await pump(tester);
    expect(handle, findsOneWidget);

    final Rect stripRect = tester.getRect(strip);
    final Rect handleRect = tester.getRect(handle);
    final Rect keypadRect = tester.getRect(find.byType(CalculatorKeypad));

    expect(handleRect.top, moreOrLessEquals(stripRect.bottom, epsilon: 0.5));
    expect(keypadRect.top, moreOrLessEquals(handleRect.bottom, epsilon: 0.5));
    // Full width, so it is the same reach for either hand.
    expect(handleRect.width, tester.view.physicalSize.width);
  });

  testWidgets('tapping the handle folds the keypad and the plot takes the room', (
    tester,
  ) async {
    final HomePageState state = await pump(tester);
    final double keypad = keypadShowing(tester);
    final double before = plotHeight(tester);
    expect(keypad, greaterThan(0));

    await tester.tap(handle);
    await settle(tester);

    expect(state.keypadHiddenForTest, isTrue);
    expect(keypadShowing(tester), 0);
    expect(
      plotHeight(tester),
      moreOrLessEquals(before + keypad, epsilon: 0.5),
      reason: 'the plot should grow by exactly the keypad it replaced',
    );
    // The handle stays, at the foot of the screen, to bring it back.
    expect(handle.hitTestable(), findsOneWidget);
  });

  testWidgets('tapping it again brings the keypad back', (tester) async {
    final HomePageState state = await pump(tester);
    final double keypad = keypadShowing(tester);
    final double before = plotHeight(tester);

    await tester.tap(handle);
    await settle(tester);
    await tester.tap(handle);
    await settle(tester);

    expect(state.keypadHiddenForTest, isFalse);
    expect(keypadShowing(tester), moreOrLessEquals(keypad, epsilon: 0.5));
    expect(plotHeight(tester), moreOrLessEquals(before, epsilon: 0.5));
  });

  testWidgets('a flick down folds it and a flick up opens it', (tester) async {
    final HomePageState state = await pump(tester);

    await tester.fling(handle, const Offset(0, 60), 800);
    await settle(tester);
    expect(state.keypadHiddenForTest, isTrue, reason: 'a flick down folds');

    await tester.fling(handle, const Offset(0, -60), 800);
    await settle(tester);
    expect(state.keypadHiddenForTest, isFalse, reason: 'a flick up opens');
  });

  testWidgets('a slow pull works without a flick', (tester) async {
    final HomePageState state = await pump(tester);

    // 30 px over half a second, then held still before lifting, so there is
    // no speed left to read and only the distance can decide.
    final TestGesture g = await tester.startGesture(tester.getCenter(handle));
    Duration t = Duration.zero;
    for (int i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 80);
      await g.moveBy(const Offset(0, 5), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 80));
    }
    t += const Duration(milliseconds: 300);
    await g.moveBy(Offset.zero, timeStamp: t);
    await g.up(timeStamp: t);
    await settle(tester);

    expect(state.keypadHiddenForTest, isTrue);
  });

  testWidgets('a folded keypad does not take key presses', (tester) async {
    final HomePageState state = await pump(tester);
    final Finder seven = find.text('7');
    expect(seven.hitTestable(), findsOneWidget);

    await tester.tap(handle);
    await settle(tester);

    expect(seven.hitTestable(), findsNothing);
    expect(state.textOfCellForTest(0), '2x');
  });

  testWidgets('touching the expression brings a folded keypad back', (
    tester,
  ) async {
    // As a phone's keyboard rises when a text field is tapped. Left folded,
    // the caret would blink with nothing to type with.
    final HomePageState state = await pump(tester);
    await tester.tap(handle);
    await settle(tester);
    expect(state.keypadHiddenForTest, isTrue);

    await tester.tap(find.byType(MathEditorInline).first);
    await settle(tester);

    expect(state.keypadHiddenForTest, isFalse);
  });
}
