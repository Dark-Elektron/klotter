import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';

/// Guards the phone keypad's geometry and arrangement.
///
/// klotter's phone keypad is two halves side by side, each five keys across
/// and four down: the number pad fixed on one side, the function pages
/// swiping on the other. Ten columns across a 360dp phone gives 36dp-wide
/// keys, which is below Material's 48dp minimum — so the keys are deliberately
/// taller than wide (the same trick a phone QWERTY uses). Unlike a keyboard, a
/// calculator has no autocorrect, so a mis-tap is a wrong answer the user
/// never notices.
void main() {
  group('Keypad touch targets', () {
    late WalkthroughService walkthroughService;
    late SettingsProvider settingsProvider;
    late Map<int, MathEditorController?> mathEditorControllers;
    late Map<int, TextEditingController?> textDisplayControllers;

    setUp(() async {
      // Fresh for every test, not once for the group: the left-hander tests
      // save their handedness, and every test after them ran left-handed.
      SharedPreferences.setMockInitialValues({
        'dark_theme': false,
        'multiplication_sign': '×',
        'walkthrough_completed_v2': true,
      });
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

    Widget buildKeypad({
      required double screenWidth,
      bool isLandscape = false,
    }) {
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
                  activeController: mathEditorControllers[0],
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
      expect(
        checked,
        greaterThan(0),
        reason: 'no main-grid keys were measured',
      );
    });

    /// Where each main-grid key landed, by its label.
    List<({Offset pos, String text})> keysOnScreen() {
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
      return entries;
    }

    /// The keys sharing a row with [anchor], left to right, within the half of
    /// the keypad [anchor] is in.
    List<String> rowOf(
      List<({Offset pos, String text})> entries,
      String anchor, {
      required double halfWidth,
    }) {
      final a = entries.firstWhere((e) => e.text == anchor);
      final bool leftHalf = a.pos.dx < halfWidth;
      final row =
          entries
              .where(
                (e) =>
                    (e.pos.dy - a.pos.dy).abs() < 1.0 &&
                    (e.pos.dx < halfWidth) == leftHalf,
              )
              .toList()
            ..sort((a, b) => a.pos.dx.compareTo(b.pos.dx));
      return row.map((e) => e.text).toList();
    }

    bool isDigit(String text) => RegExp(r'^[0-9]$').hasMatch(text);

    /// Where the trig row of the scientific page is across the screen, by the
    /// centre of each key. Its keys open a menu on a long press, so they are
    /// not [MyButton]s and [keysOnScreen] does not see them.
    List<double> trigRow(WidgetTester tester) => <double>[
      for (final String l in <String>['sin', 'cos', 'tan', 'log'])
        tester.getCenter(find.text(l).first).dx,
    ];

    testWidgets('the number pad is a calculator block under a right thumb', (
      tester,
    ) async {
      // 7 8 9 on top, 0 beside the point, the operators as klator pairs them,
      // the two keys that destroy work together on top and the action key in
      // the bottom corner.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      final entries = keysOnScreen();
      expect(entries, isNotEmpty);
      List<String> row(String anchor) => rowOf(entries, anchor, halfWidth: 180);

      expect(row('7'), <String>['7', '8', '9', '()', '⌫']);
      expect(row('4'), <String>['4', '5', '6', '+', '−']);
      expect(row('1'), <String>['1', '2', '3', '×', '÷']);
      expect(row('0'), <String>['0', '.', 'ᴇ', 'CE', '⌘']);

      // The whole block is the right half, under a right-hander's thumb...
      for (final e in entries.where((e) => isDigit(e.text))) {
        expect(
          e.pos.dx,
          greaterThanOrEqualTo(180),
          reason: '${e.text} left its half',
        );
      }
      // ...and the function keys are the left half, in reading order.
      final List<double> trig = trigRow(tester);
      expect(trig.last, lessThan(180));
      for (int i = 1; i < trig.length; i++) {
        expect(trig[i], greaterThan(trig[i - 1]), reason: 'trig row $trig');
      }
    });

    testWidgets('a left-hander gets the keypad in a mirror', (tester) async {
      await settingsProvider.setHandedness(Handedness.leftHanded);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      final entries = keysOnScreen();
      for (final e in entries.where((e) => isDigit(e.text))) {
        expect(
          e.pos.dx,
          lessThan(180),
          reason: '${e.text} stayed on the right',
        );
      }
      // Reflected, not moved: what sat under the dominant thumb still does,
      // and backspace and the action key are still on the outer edge.
      expect(rowOf(entries, '7', halfWidth: 180), <String>[
        '⌫',
        '()',
        '9',
        '8',
        '7',
      ]);
      expect(rowOf(entries, '0', halfWidth: 180), <String>[
        '⌘',
        'CE',
        'ᴇ',
        '.',
        '0',
      ]);
      // The function keys moved to the right half, and they are reflected
      // too — the whole keypad is the right-hander's in a mirror.
      final List<double> trig = trigRow(tester);
      expect(trig.last, greaterThan(180));
      for (int i = 1; i < trig.length; i++) {
        expect(trig[i], lessThan(trig[i - 1]), reason: 'trig row $trig');
      }
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

    testWidgets('clear is kept away from backspace', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      double yOf(String label) {
        final box = find.text(label).evaluate().first.renderObject as RenderBox;
        return box.localToGlobal(Offset.zero).dy;
      }

      // '8' anchors the top number row, '0' the bottom one.
      final upper = yOf('8');
      final lower = yOf('0');
      expect(lower, greaterThan(upper));

      // Compare which row each key is nearer to rather than exact pixels —
      // glyphs of different sizes have different text baselines within a key.
      bool onUpper(String label) {
        final y = yOf(label);
        return (y - upper).abs() < (y - lower).abs();
      }

      // A thumb going for backspace that lands one key short should cost a
      // character, not the expression, so clear sits at the foot beside the
      // action key and backspace keeps the top corner.
      expect(onUpper('⌫'), isTrue, reason: 'backspace takes the top corner');
      expect(onUpper('CE'), isFalse, reason: 'clear belongs at the foot');
      expect(onUpper('⌘'), isFalse, reason: 'action sits bottom right');
      expect(onUpper('ᴇ'), isFalse, reason: 'E sits on the bottom row');
      expect(onUpper('()'), isTrue, reason: 'brackets sit beside backspace');
    });

    testWidgets('extras page pairs related keys in columns', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      // Swipe the function keys from scientific to extras. Drag from a
      // scientific-only key so the gesture lands on the swiping half and not
      // on the fixed number pad beside it.
      await tester.drag(find.text('≥'), const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Centres, not left edges: a 4-character label is wider than a
      // 1-character one, so their text origins differ even in the same column.
      // Found by the key's own label where there is one: asin is drawn as
      // "arc" over "sin" and d/dx as a fraction, so neither is a text.
      Offset posOf(String label) {
        final Finder key = find.byWidgetPredicate(
          (Widget w) =>
              (w is PopupMenuCalcButton && w.buttonText == label) ||
              (w is MyButton && w.buttonText == label),
        );
        return tester.getCenter(
          key.evaluate().isNotEmpty ? key.first : find.text(label).first,
        );
      }
      double x(String l) => posOf(l).dx;
      double y(String l) => posOf(l).dy;

      // Related keys share a column, read top-then-bottom.
      expect(x('sin'), closeTo(x('asin'), 2));
      expect(y('sin'), lessThan(y('asin')));
      expect(x('d/dx'), closeTo(x('∫'), 2));
      expect(y('d/dx'), lessThan(y('∫')));
      expect(x('i'), closeTo(x('π'), 2));

      expect(x('ⁿPᵣ'), closeTo(x('∑'), 2));

      // The whole-document keys are one block on the outer edge: clear-all,
      // undo and redo over settings, export and help. Redo is a mirrored
      // undo, so both carry U+238C: the first is undo.
      final undoRedo = find.text('⎌');
      final double undoX = tester.getCenter(undoRedo.first).dx;
      final double redoX = tester.getCenter(undoRedo.last).dx;
      final double undoY = tester.getCenter(undoRedo.first).dy;
      expect(x('⌧'), lessThan(undoX));
      expect(undoX, lessThan(redoX));
      expect(undoY, closeTo(y('⌧'), 2));
      expect(undoX, closeTo(x('⇪'), 2));
      expect(x('ⓘ'), closeTo(redoX, 2));
      expect(x('☰'), closeTo(x('⌧'), 2));
      expect(y('☰'), greaterThan(undoY));

      // Values lead the top row; the document block sits below them.
      expect(y('i'), lessThan(undoY));
      expect(x('sin'), lessThan(x('i')));

      // Settings is in the far left corner, out of the way of the thumb on
      // the numbers — where a tablet has it too.
      expect(x('☰'), closeTo(x('sin'), 2));
      expect(tester.getTopLeft(find.text('☰')).dx, lessThan(36));
      expect(y('☰'), greaterThan(y('d/dx')));

      // ANS is gone: the cell index it referred to no longer has a display.
      expect(find.text('ans'), findsNothing);
    });

    testWidgets('a left-hander finds settings in the far right corner', (
      tester,
    ) async {
      await settingsProvider.setHandedness(Handedness.leftHanded);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildKeypad(screenWidth: 360));
      await tester.pumpAndSettle();

      await tester.drag(find.text('≥'), const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final Offset settings = tester.getCenter(find.text('☰'));
      // Rightmost of every key on screen, and on the bottom row.
      for (final e in keysOnScreen()) {
        expect(
          e.pos.dx,
          lessThan(settings.dx),
          reason: '${e.text} is further right than settings',
        );
      }
      expect(settings.dx, greaterThan(360 - 36));
      // d/dx is drawn as a fraction, so it is found by its key.
      final Finder deriv = find.byWidgetPredicate(
        (Widget w) => w is PopupMenuCalcButton && w.buttonText == 'd/dx',
      );
      expect(settings.dy, greaterThan(tester.getCenter(deriv).dy));
      // The page is the right-hander's reflected, pairs and all.
      expect(tester.getCenter(find.text('⌧')).dx, closeTo(settings.dx, 2));
      expect(
        tester.getCenter(deriv).dx,
        closeTo(tester.getCenter(find.text('∫')).dx, 2),
      );
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
