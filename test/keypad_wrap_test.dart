import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';

/// The function keys' pages come round again: a swipe past either end brings
/// in the page at the other end, from the side it was swiped from.
///
/// They used to stop at both ends, so reaching the scientific keys from the
/// extras took a swipe the other way rather than one more of the same.
void main() {
  late WalkthroughService tour;
  late SettingsProvider settings;
  late MathEditorController editor;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dark_theme': false,
      'multiplication_sign': '×',
      'walkthrough_completed_v2': true,
    });
    tour = WalkthroughService();
    settings = await SettingsProvider.create();
    editor = MathEditorController();
  });

  tearDown(() {
    tour.dispose();
    settings.dispose();
    editor.dispose();
  });

  Widget keypad() => ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(
        body: Builder(
          builder:
              (context) => CalculatorKeypad(
                screenWidth: 360,
                isLandscape: false,
                colors: AppColors.of(context),
                activeIndex: 0,
                activeController: editor,
                settingsProvider: settings,
                onUpdateMathEditor: () {},
                onAddDisplay: () {},
                onRemoveDisplay: (_) {},
                onClearAllDisplays: () {},
                onSetState: () {},
                walkthroughService: tour,
                scientificKeypadKey: GlobalKey(),
                numberKeypadKey: GlobalKey(),
                extrasKeypadKey: GlobalKey(),
                commandButtonKey: GlobalKey(),
                mainKeypadAreaKey: GlobalKey(),
                settingsButtonKey: GlobalKey(),
              ),
        ),
      ),
    ),
  );

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(keypad());
    await tester.pumpAndSettle();
  }

  // '≥' is only on the scientific keys and '☰' only on the extras.
  bool onScientific() =>
      find.text('≥').evaluate().isNotEmpty && find.text('☰').evaluate().isEmpty;
  bool onExtras() =>
      find.text('☰').evaluate().isNotEmpty && find.text('≥').evaluate().isEmpty;

  /// A swipe across the function keys, from whichever key of the page on
  /// show is given; left when [dx] is negative.
  Future<void> swipe(WidgetTester tester, String from, double dx) async {
    await tester.drag(find.text(from), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('the first page opens at full size, level with the numbers', (
    tester,
  ) async {
    // The pages are drawn smaller and fainter the further they are from the
    // one on show. Opening a thousand turns in, the first page was taken to be
    // that far away until something scrolled, and came up shrunk and faded.
    await show(tester);
    Rect key(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(MyButton))
          .first,
    );
    expect(key('=').top, closeTo(key('7').top, 0.5));
    expect(key('=').height, closeTo(key('7').height, 0.5));
    expect(key('e').top, closeTo(key('0').top, 0.5));
  });

  testWidgets('a swipe left past the extras comes round to the scientific '
      'keys', (tester) async {
    await show(tester);
    expect(onScientific(), isTrue);

    await swipe(tester, '≥', -300);
    expect(onExtras(), isTrue);

    await swipe(tester, '☰', -300);
    expect(onScientific(), isTrue, reason: 'past the last page, the first');
  });

  testWidgets('a swipe right before the scientific keys comes round to the '
      'extras', (tester) async {
    await show(tester);

    await swipe(tester, '≥', 300);
    expect(onExtras(), isTrue, reason: 'before the first page, the last');

    await swipe(tester, '☰', 300);
    expect(onScientific(), isTrue);
  });

  testWidgets('the page comes in from the side it was swiped from', (
    tester,
  ) async {
    // Coming round is not jumping back: swiped left off the extras, the
    // scientific keys arrive from the right, as the next page would — not
    // from the left, which is where the first page is in a row that stops.
    await show(tester);
    await swipe(tester, '≥', -300);
    final double settledX = tester.getCenter(find.text('∫')).dx;

    await tester.drag(find.text('☰'), const Offset(-300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final double arriving = tester.getCenter(find.text('≥')).dx;
    await tester.pumpAndSettle();
    final double arrived = tester.getCenter(find.text('≥')).dx;
    expect(arriving, greaterThan(arrived + 20));

    // And the other way: swiped right off the scientific keys, the extras
    // come in from the left.
    await tester.drag(find.text('≥'), const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(find.text('∫')).dx, lessThan(settledX - 20));
    await tester.pumpAndSettle();
    expect(onExtras(), isTrue);
  });

  testWidgets('it comes round many times over, either way', (tester) async {
    await show(tester);
    for (int i = 0; i < 5; i++) {
      await swipe(tester, onScientific() ? '≥' : '☰', -300);
    }
    expect(onExtras(), isTrue, reason: 'an odd number of turns from the start');
    for (int i = 0; i < 5; i++) {
      await swipe(tester, onScientific() ? '≥' : '☰', 300);
    }
    expect(onScientific(), isTrue);
  });

  testWidgets('a left-hander comes round too', (tester) async {
    await settings.setHandedness(Handedness.leftHanded);
    await show(tester);
    await swipe(tester, '≥', 300);
    expect(onExtras(), isTrue);
    await swipe(tester, '☰', 300);
    expect(onScientific(), isTrue);
  });

  group('the tour', () {
    // The tour asks for a swipe left on the scientific keys and a swipe right
    // back from the extras. The end of the row used to stop the other way; it
    // still does nothing while the tour is waiting.
    Future<void> toStep(WalkthroughAction action) async {
      tour.startWalkthrough();
      while (tour.currentStepData.requiredAction != action ||
          !tour.currentStepData.requiresAction) {
        tour.nextStep();
      }
    }

    testWidgets('asking for a swipe left, a swipe right does nothing', (
      tester,
    ) async {
      await show(tester);
      await toStep(WalkthroughAction.swipeLeft);
      await tester.pump();
      final String step = tour.currentStepData.id;

      await swipe(tester, '≥', 300);
      expect(onScientific(), isTrue);
      expect(tour.currentStepData.id, step);

      await swipe(tester, '≥', -300);
      expect(onExtras(), isTrue);
      expect(tour.currentStepData.id, isNot(step), reason: 'the step is done');
    });

    testWidgets('asking for a swipe right, a swipe left does nothing', (
      tester,
    ) async {
      // Reached as the tour reaches it: by doing the swipe-left step first,
      // which leaves the extras on show. (Starting the tour puts the keys back
      // on their first page.)
      await show(tester);
      await toStep(WalkthroughAction.swipeLeft);
      await tester.pumpAndSettle();
      await swipe(tester, '≥', -300);
      expect(onExtras(), isTrue);
      while (!tour.currentStepData.requiresAction ||
          tour.currentStepData.requiredAction != WalkthroughAction.swipeRight) {
        tour.nextStep();
      }
      await tester.pump();
      final String step = tour.currentStepData.id;

      await swipe(tester, '☰', -300);
      expect(onExtras(), isTrue);
      expect(tour.currentStepData.id, step);

      await swipe(tester, '☰', 300);
      expect(onScientific(), isTrue);
      expect(tour.currentStepData.id, isNot(step), reason: 'the step is done');
    });
  });
}
