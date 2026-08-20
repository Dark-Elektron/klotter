import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/utils/laid_out_subtree.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';

/// The keypad laid out the way main.dart lays it out.
///
/// Reproducing `'!_debugDoingThisLayout': is not true`, thrown at startup. The
/// stack has the keypad's own Column laying out a child that is already inside
/// its own layout, reached through AnimatedSize and LaidOutSubtree — so the
/// arrangement matters, not the keypad alone.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  final GlobalKey mainKeypadAreaKey = GlobalKey();
  final GlobalKey scientificKey = GlobalKey();
  final GlobalKey numberKey = GlobalKey();
  final GlobalKey extrasKey = GlobalKey();
  final GlobalKey commandKey = GlobalKey();
  final GlobalKey settingsKey = GlobalKey();
  final GlobalKey tabletNumberKey = GlobalKey();
  final GlobalKey tabletSciKey = GlobalKey();
  final GlobalKey tabletExtrasKey = GlobalKey();

  Widget host(double width, bool landscape) {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // As in main.dart: the keypad sits under an AnimatedSize, with
              // the guard between them.
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: LaidOutSubtree(
                  child: Builder(
                    builder: (context) {
                      return CalculatorKeypad(
                        screenWidth: width,
                        isLandscape: landscape,
                        colors: AppColors.of(context),
                        activeIndex: 0,
                        activeController: controller,
                        settingsProvider: settings,
                        onUpdateMathEditor: () {},
                        onAddDisplay: () {},
                        onRemoveDisplay: (_) {},
                        onClearAllDisplays: () {},
                        onSetState: () {},
                        walkthroughService: WalkthroughService(),
                        scientificKeypadKey: scientificKey,
                        numberKeypadKey: numberKey,
                        extrasKeypadKey: extrasKey,
                        commandButtonKey: commandKey,
                        mainKeypadAreaKey: mainKeypadAreaKey,
                        settingsButtonKey: settingsKey,
                        numberBlockKey: tabletNumberKey,
                        scientificBlockKey: tabletSciKey,
                        extrasBlockKey: tabletExtrasKey,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> resize(WidgetTester tester, Size size, bool landscape) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(host(size.width, landscape));
  }

  testWidgets('switching between the phone and tablet arrangements', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    // Phone first, then wide enough to be a tablet, on the same element — so
    // the keyed subtree moves between the two arrangements the way it does
    // when the screen metrics settle at startup.
    await resize(tester, const Size(400, 800), false);
    await tester.pump(const Duration(milliseconds: 50));
    await resize(tester, const Size(1000, 800), false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    await resize(tester, const Size(400, 800), false);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'laying the keypad out re-entered layout',
    );
  });

  testWidgets('laid out with no width offered, as on the warm-up frame', (
    tester,
  ) async {
    // The launch stack: the keypad reached layout inside an offstage overlay
    // with unbounded width. pageWidth became Infinity, the cell became
    // Infinity, and dividing it by an aspect ratio taken from the same
    // Infinity gave NaN — so SizedBox got `NaN<=h<=NaN` and every later
    // "was not laid out" and "!_debugDoingThisLayout" followed from it.
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    final controller = MathEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            // A Row gives its child unbounded width, which is the shape of the
            // constraints that caused this.
            body: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Builder(
                  builder: (context) {
                    return CalculatorKeypad(
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
                      walkthroughService: WalkthroughService(),
                      scientificKeypadKey: GlobalKey(),
                      numberKeypadKey: GlobalKey(),
                      extrasKeypadKey: GlobalKey(),
                      commandButtonKey: GlobalKey(),
                      mainKeypadAreaKey: GlobalKey(),
                      settingsButtonKey: GlobalKey(),
                      numberBlockKey: GlobalKey(),
                      scientificBlockKey: GlobalKey(),
                      extrasBlockKey: GlobalKey(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'an unbounded width still produces a NaN size',
    );
    // And it laid out at a real width rather than collapsing to nothing.
    final Size size = tester.getSize(find.byType(CalculatorKeypad));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(size.height.isFinite, isTrue);
  });
}
