import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/utils/render_box.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';

/// The phone tour opens on the scientific keys, not the extras.
///
/// Its third step asks you to swipe the top rows LEFT to reach the extras. That
/// only works from the first page. The keypad was reset to page 1 instead —
/// correct when the number pad was a page of its own, wrong now that the pages
/// are [scientific, extras] — so the tour opened *on* the extras and the step
/// asked for a swipe with nothing to its left. You had to swipe right and then
/// left again to satisfy the first swipe the tour ever asks for.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  final GlobalKey keypadAreaKey = GlobalKey();

  Future<void> pumpPhone(WidgetTester tester) async {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    final service = WalkthroughService();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => CalculatorKeypad(
                    screenWidth: 400,
                    isLandscape: false,
                    colors: AppColors.of(context),
                    activeIndex: 0,
                    activeController: controller,
                    settingsProvider: settings,
                    onUpdateMathEditor: () {},
                    onAddDisplay: () {},
                    onRemoveDisplay: (_) {},
                    onClearAllDisplays: () {},
                    onSetState: () {},
                    walkthroughService: service,
                    scientificKeypadKey: GlobalKey(),
                    numberKeypadKey: GlobalKey(),
                    extrasKeypadKey: GlobalKey(),
                    commandButtonKey: GlobalKey(),
                    mainKeypadAreaKey: keypadAreaKey,
                    settingsButtonKey: GlobalKey(),
                    numberBlockKey: GlobalKey(),
                    scientificBlockKey: GlobalKey(),
                    extrasBlockKey: GlobalKey(),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // What the tour does when it opens.
    service.onResetKeypad?.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Whether [label]'s key is the one on screen in the swipeable rows.
  ///
  /// Both pages are built at once, so finding the widget proves nothing —
  /// what matters is which of them is inside the viewport.
  bool onScreen(WidgetTester tester, String label) {
    final Finder key = find.text(label);
    if (key.evaluate().isEmpty) return false;
    final Rect area = tester.getRect(find.byKey(keypadAreaKey));
    return area.inflate(1).contains(tester.getRect(key.first).center);
  }

  testWidgets('the tour resets the phone keypad to the first page', (
    tester,
  ) async {
    await pumpPhone(tester);
    expect(
      onScreen(tester, 'sin'),
      isTrue,
      reason:
          'the tour did not open on the scientific keys, so its "swipe LEFT" '
          'step has nothing to the left to reach',
    );
    expect(
      onScreen(tester, '∫'),
      isFalse,
      reason: 'the tour opened on the extras, which is where it should end up',
    );
  });

  testWidgets('so there is a page to the left to swipe to', (tester) async {
    // The point of the reset, stated as the user meets it: one leftward swipe
    // from the opening position lands on the extras.
    await pumpPhone(tester);

    await tester.drag(find.text('sin').first, const Offset(-350, 0));
    await tester.pumpAndSettle();

    expect(
      onScreen(tester, '∫'),
      isTrue,
      reason: 'one swipe left did not reach the extras',
    );
  });

  testWidgets('the spotlight can measure the keypad area', (tester) async {
    // The overlay resolves its highlight with laidOutBox, which refuses a
    // render object that is pending layout. Putting this key on a wrapper
    // around the LayoutBuilder made it resolve to the _RenderLayoutBuilder,
    // which routinely is pending — so the spotlight got no rect at all. With
    // no cut-out the overlay covered the screen, nothing was highlighted, and
    // the swipe the step was asking for never reached the keypad.
    //
    // tester.getRect does not check that flag, so it saw nothing wrong. This
    // asks the same question the overlay asks.
    await pumpPhone(tester);

    final RenderBox? box = laidOutBox(keypadAreaKey.currentContext);
    expect(
      box,
      isNotNull,
      reason: 'the spotlight cannot measure the keypad, so it lights nothing',
    );
    expect(box!.size.height, greaterThan(0));
    expect(box.size.width, greaterThan(0));
  });
}
