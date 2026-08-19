import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';

/// The tablet tour points at one block of the keypad at a time.
///
/// A tablet shows every key at once, so the steps that told the user to swipe
/// left and right were describing a gesture that does nothing here. They are
/// replaced by a step per block — and a step is only worth having if the thing
/// it highlights is actually where that block is, which is what this measures.
///
/// The blocks are not separate widgets: the tablet keypad is one GridView of
/// uniform cells, so each marker is an invisible box laid over the columns its
/// block owns. Nothing about that is visible on screen, which is exactly why
/// it needs measuring rather than eyeballing.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    settings = await SettingsProvider.create();
  });

  tearDown(() => settings.dispose());

  final GlobalKey numberKey = GlobalKey();
  final GlobalKey scientificKey = GlobalKey();
  final GlobalKey extrasKey = GlobalKey();
  final GlobalKey keypadKey = GlobalKey();

  Widget host({required double width, required bool landscape}) {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => CalculatorKeypad(
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
                  scientificKeypadKey: GlobalKey(),
                  numberKeypadKey: GlobalKey(),
                  extrasKeypadKey: GlobalKey(),
                  commandButtonKey: GlobalKey(),
                  mainKeypadAreaKey: keypadKey,
                  settingsButtonKey: GlobalKey(),
                  numberBlockKey: numberKey,
                  scientificBlockKey: scientificKey,
                  extrasBlockKey: extrasKey,
                ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpTablet(
    WidgetTester tester, {
    required bool landscape,
    Handedness hand = Handedness.rightHanded,
  }) async {
    await settings.setHandedness(hand);
    final Size size = landscape ? const Size(1280, 800) : const Size(800, 1280);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: size.width, landscape: landscape));
    await tester.pumpAndSettle();
  }

  group('the step list', () {
    test('no tablet step asks for a swipe', () {
      final Iterable<WalkthroughStep> swipes = walkthroughSteps.where(
        (WalkthroughStep s) =>
            s.tabletOnly &&
            (s.requiredAction == WalkthroughAction.swipeLeft ||
                s.requiredAction == WalkthroughAction.swipeRight),
      );
      expect(
        swipes.map((WalkthroughStep s) => s.id),
        isEmpty,
        reason: 'a tablet shows every keypad at once; there is no swipe',
      );
    });

    test('there is a step for each block', () {
      final Set<String> ids =
          walkthroughSteps.map((WalkthroughStep s) => s.id).toSet();
      for (final String id in <String>[
        'tablet_number_block',
        'tablet_scientific_block',
        'tablet_extras_block',
      ]) {
        expect(ids, contains(id));
      }
    });

    test('the phone still learns the swipes', () {
      // The tablet steps changed; the mobile ones must not have. Both sets
      // live in one list, and a careless edit takes the swipes out entirely.
      final Iterable<WalkthroughStep> swipes = walkthroughSteps.where(
        (WalkthroughStep s) => s.mobileOnly && s.requiredAction != null,
      );
      expect(swipes, isNotEmpty, reason: 'the phone tour lost its swipes');
    });
  });

  for (final bool landscape in <bool>[false, true]) {
    final String shape = landscape ? 'landscape' : 'portrait';

    testWidgets('each block is highlighted where it is, $shape', (
      tester,
    ) async {
      await pumpTablet(tester, landscape: landscape);

      final Rect keypad = tester.getRect(find.byKey(keypadKey));
      final Rect number = tester.getRect(find.byKey(numberKey));
      final Rect scientific = tester.getRect(find.byKey(scientificKey));
      final Rect extras = tester.getRect(find.byKey(extrasKey));

      // Each is a real area inside the keypad, not a collapsed box left over
      // from a marker that found no columns.
      for (final MapEntry<String, Rect> block
          in <String, Rect>{
            'number': number,
            'scientific': scientific,
            'extras': extras,
          }.entries) {
        expect(
          block.value.width,
          greaterThan(keypad.width / 8),
          reason: '${block.key} is too narrow to be a block',
        );
        expect(
          block.value.height,
          closeTo(keypad.height, 1),
          reason: '${block.key} should be the full height of the keypad',
        );
        expect(
          keypad.inflate(1).contains(block.value.topLeft),
          isTrue,
          reason: '${block.key} starts outside the keypad',
        );
      }

      // They do not overlap. This is the assertion the naive version fails:
      // taking each block's span from its outermost key stretches extras
      // across the number keys, because landscape puts the export key there.
      final List<Rect> byLeft = <Rect>[number, scientific, extras]
        ..sort((Rect a, Rect b) => a.left.compareTo(b.left));
      for (int i = 1; i < byLeft.length; i++) {
        expect(
          byLeft[i].left,
          greaterThanOrEqualTo(byLeft[i - 1].right - 1),
          reason: 'two blocks are highlighted over the same keys',
        );
      }

      // And between them they cover the keypad, so no column is unexplained.
      expect(byLeft.first.left, closeTo(keypad.left, 1));
      expect(byLeft.last.right, closeTo(keypad.right, 1));
    });

    testWidgets('a key of each block falls inside its own highlight, $shape', (
      tester,
    ) async {
      await pumpTablet(tester, landscape: landscape);

      // One key that only its own block has. '7' is a digit, ∫ is an extras
      // key, and the scientific block is named by its own x̂ — the extras
      // block has no unit vectors.
      //
      // Not the export key, tempting though it is: landscape parks it at
      // column 18, among the digits, and it is genuinely outside the extras
      // highlight there. That is the stray this whole measurement works
      // around, not a key to measure with.
      const Map<String, String> sample = <String, String>{
        'number': '7',
        'scientific': 'x̂',
        'extras': '∫',
      };
      final Map<String, Rect> blocks = <String, Rect>{
        'number': tester.getRect(find.byKey(numberKey)),
        'scientific': tester.getRect(find.byKey(scientificKey)),
        'extras': tester.getRect(find.byKey(extrasKey)),
      };

      for (final MapEntry<String, String> e in sample.entries) {
        final Finder key = find.text(e.value);
        expect(
          key,
          findsWidgets,
          reason: '${e.value} is not on the tablet keypad any more',
        );
        final Rect at = tester.getRect(key.first);
        expect(
          blocks[e.key]!.inflate(1).contains(at.center),
          isTrue,
          reason:
              '${e.value} sits at ${at.center.dx} but the ${e.key} block is '
              'highlighted over ${blocks[e.key]}',
        );
      }
    });

    testWidgets('the highlights mirror with a left-handed layout, $shape', (
      tester,
    ) async {
      // The grid is reflected for a left-handed user, so a marker that did not
      // follow would point at the wrong block — worse than pointing nowhere.
      await pumpTablet(tester, landscape: landscape);
      final double rightHandedNumber =
          tester.getRect(find.byKey(numberKey)).center.dx;

      await pumpTablet(
        tester,
        landscape: landscape,
        hand: Handedness.leftHanded,
      );
      final Rect keypad = tester.getRect(find.byKey(keypadKey));
      final double leftHandedNumber =
          tester.getRect(find.byKey(numberKey)).center.dx;

      expect(
        leftHandedNumber,
        closeTo(keypad.left + keypad.right - rightHandedNumber, 1),
        reason: 'the number block moved but its highlight did not',
      );
      // And it still lands on the digits.
      expect(
        tester
            .getRect(find.byKey(numberKey))
            .inflate(1)
            .contains(tester.getRect(find.text('7').first).center),
        isTrue,
      );
    });
  }
}
