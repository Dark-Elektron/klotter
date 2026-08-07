import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';

/// Guards the phone keypad's touch-target geometry.
///
/// klotter runs a 10-column keypad so the plot and the keys can share the
/// screen. At 10 columns a 360dp phone gives 36dp-wide keys, which is below
/// Material's 48dp minimum — so the keys are deliberately taller than wide
/// (the same trick a phone QWERTY uses). Unlike a keyboard, a calculator has no
/// autocorrect, so a mis-tap is a wrong answer the user never notices.
void main() {
  group('Keypad touch targets', () {
    late WalkthroughService walkthroughService;
    late SettingsProvider settingsProvider;
    late Map<int, MathEditorController?> mathEditorControllers;
    late Map<int, TextEditingController?> textDisplayControllers;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({
        'dark_theme': false,
        'multiplication_sign': '×',
        'walkthrough_completed_v2': true,
      });
    });

    setUp(() async {
      walkthroughService = WalkthroughService();
      settingsProvider = await SettingsProvider.create();
      mathEditorControllers = {0: MathEditorController()};
      textDisplayControllers = {0: TextEditingController()};
    });

    tearDown(() {
      walkthroughService.dispose();
      settingsProvider.dispose();
      mathEditorControllers[0]?.dispose();
      textDisplayControllers[0]?.dispose();
    });

    Widget buildKeypad({required double screenWidth, bool isLandscape = false}) {
      return ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return CalculatorKeypad(
                  screenWidth: screenWidth,
                  isLandscape: isLandscape,
                  colors: AppColors.of(context),
                  activeIndex: 0,
                  mathEditorControllers: mathEditorControllers,
                  textDisplayControllers: textDisplayControllers,
                  settingsProvider: settingsProvider,
                  onUpdateMathEditor: () {},
                  onAddDisplay: () {},
                  onRemoveDisplay: (_) {},
                  onClearAllDisplays: () {},
                  onSetState: () {},
                  walkthroughService: walkthroughService,
                  scientificKeypadKey: GlobalKey(),
                  numberKeypadKey: GlobalKey(),
                  extrasKeypadKey: GlobalKey(),
                  commandButtonKey: GlobalKey(),
                  mainKeypadAreaKey: GlobalKey(),
                  settingsButtonKey: GlobalKey(),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets('phone main-keypad keys meet the 48dp minimum height', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      final buttons = find.byType(MyButton);
      expect(buttons, findsWidgets);

      // Main-grid keys are 36dp wide at 10 columns; anything that wide must be
      // at least 48dp tall. (The basic pull-up pad is measured separately.)
      var checked = 0;
      for (final element in buttons.evaluate()) {
        final size = element.size;
        if (size == null || size.width < 30 || size.width > 42) continue;
        checked++;
        expect(
          size.height,
          greaterThanOrEqualTo(48.0 - 0.5),
          reason:
              'main keypad key is ${size.width.toStringAsFixed(1)} x '
              '${size.height.toStringAsFixed(1)}dp — below the 48dp target',
        );
      }
      expect(checked, greaterThan(0), reason: 'no main-grid keys were measured');
    });

    testWidgets('the fixed number pad keeps digits left, operators right', (
      tester,
    ) async {
      // Mirrors the old pull-up pad: 5-9 over 0-4 in the left five columns,
      // operators and editing keys in the right five.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      final entries = <({Offset pos, String text})>[];
      for (final element in find.byType(MyButton).evaluate()) {
        final size = element.size;
        if (size == null || size.width < 30 || size.width > 42) continue;
        final box = element.renderObject as RenderBox?;
        if (box == null) continue;
        final widget = element.widget as MyButton;
        entries.add((
          pos: box.localToGlobal(Offset.zero),
          text: widget.buttonText,
        ));
      }
      expect(entries, isNotEmpty);

      List<String> rowOf(String anchor) {
        final a = entries.firstWhere((e) => e.text == anchor);
        final row =
            entries.where((e) => (e.pos.dy - a.pos.dy).abs() < 1.0).toList()
              ..sort((a, b) => a.pos.dx.compareTo(b.pos.dx));
        return row.map((e) => e.text).toList();
      }

      expect(
        rowOf('0').take(5).toList(),
        equals(<String>['0', '1', '2', '3', '4']),
        reason: 'digits 0-4 should fill the left half of their row',
      );
      expect(
        rowOf('5').take(5).toList(),
        equals(<String>['5', '6', '7', '8', '9']),
        reason: 'digits 5-9 should fill the left half of their row',
      );
      // Right half is operators, not digits.
      expect(
        rowOf('0').skip(5).any((t) => RegExp(r'^[0-9]$').hasMatch(t)),
        isFalse,
      );
    });

    testWidgets('the symbol key is scientific E, never percentage', (
      tester,
    ) async {
      // klotter is an advanced calculator: 1E6 earns the slot, % does not.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      expect(find.text('%'), findsNothing);
      expect(find.text('ᴇ'), findsOneWidget);
    });

    testWidgets('clear and backspace share the top row; action sits bottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      double yOf(String label) {
        final box =
            find.text(label).evaluate().first.renderObject as RenderBox;
        return box.localToGlobal(Offset.zero).dy;
      }

      // '5' anchors the upper number row, '0' the lower one.
      final upper = yOf('5');
      final lower = yOf('0');
      expect(lower, greaterThan(upper));

      // Compare which row each key is nearer to rather than exact pixels —
      // glyphs of different sizes have different text baselines within a key.
      bool onUpper(String label) {
        final y = yOf(label);
        return (y - upper).abs() < (y - lower).abs();
      }

      expect(onUpper('CE'), isTrue, reason: 'clear belongs on the top row');
      expect(onUpper('⌫'), isTrue, reason: 'backspace joins clear');
      expect(onUpper('⌘'), isFalse, reason: 'action sits bottom right');
      expect(onUpper('ᴇ'), isFalse, reason: 'E sits on the bottom row');
    });

    testWidgets('extras page pairs related keys in columns', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      // Swipe the top rows from scientific to extras. Drag from a
      // scientific-only key so the gesture lands in the swipeable half and
      // not on the fixed number pad below it.
      await tester.drag(find.text('ⁿ√'), const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Centres, not left edges: a 4-character label is wider than a
      // 1-character one, so their text origins differ even in the same column.
      Offset posOf(String label) => tester.getCenter(find.text(label).first);
      double x(String l) => posOf(l).dx;
      double y(String l) => posOf(l).dy;

      // Related keys share a column, read top-then-bottom.
      expect(x('sin'), closeTo(x('asin'), 2));
      expect(y('sin'), lessThan(y('asin')));
      expect(x('d/dx'), closeTo(x('∫'), 2));
      expect(y('d/dx'), lessThan(y('∫')));
      expect(x('i'), closeTo(x('π'), 2));

      // Values lead; history takes the last three of the top row.
      // Redo is a mirrored undo, so both carry U+238C: first is undo.
      final undoRedo = find.text('⎌');
      final double undoX = tester.getCenter(undoRedo.first).dx;
      final double redoX = tester.getCenter(undoRedo.last).dx;
      final double undoY = tester.getCenter(undoRedo.first).dy;

      expect(x('i'), lessThan(x('sin')));
      expect(x('sin'), lessThan(undoX));
      expect(undoX, lessThan(redoX));
      expect(redoX, lessThan(x('⌧')));
      expect(undoY, closeTo(y('i'), 2));

      // Utilities take the last two of the bottom row.
      expect(x('ⓘ'), lessThan(x('☰')));
      expect(y('ⓘ'), closeTo(y('π'), 2));
      expect(x('☰'), greaterThan(x('∫')));

      // ANS is gone: the cell index it referred to no longer has a display.
      expect(find.text('ans'), findsNothing);
    });

    testWidgets('phone keys are taller than wide, like a phone keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      var checked = 0;
      for (final element in find.byType(MyButton).evaluate()) {
        final size = element.size;
        if (size == null || size.width < 30 || size.width > 42) continue;
        checked++;
        expect(size.height, greaterThan(size.width));
      }
      expect(checked, greaterThan(0));
    });
  });
}
