import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a screen reader is told about the keypad.
///
/// The keys are glyphs, and TalkBack read them badly or not at all: ⌫ said
/// nothing, ⁿ√ came out letter by letter, and undo and redo, one glyph drawn
/// two ways, sounded the same. Each key now says what it does.
void main() {
  late SettingsProvider settings;
  late MathEditorController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    settings = await SettingsProvider.create();
    controller = MathEditorController();
  });

  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  /// A tablet keypad, which has every key on screen at once.
  Future<void> pumpKeypad(WidgetTester tester) async {
    const Size size = Size(1280, 800);
    tester.view.physicalSize = size;
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
                    screenWidth: size.width,
                    isLandscape: true,
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
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every key on the keypad, with what its face shows.
  List<(Widget, String)> keys(WidgetTester tester) => <(Widget, String)>[
    for (final MyButton b in tester.widgetList<MyButton>(find.byType(MyButton)))
      (b, b.buttonText),
    for (final PopupMenuCalcButton b in tester.widgetList<PopupMenuCalcButton>(
      find.byType(PopupMenuCalcButton),
    ))
      (b, b.buttonText),
  ];

  testWidgets('every key is read as words, not as its glyph', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpKeypad(tester);

    final List<(Widget, String)> all = keys(tester);
    expect(all.length, greaterThanOrEqualTo(60), reason: 'all three blocks');
    final RegExp words = RegExp(r"^[A-Za-z0-9 ,'-]+$");
    for (final (Widget key, String face) in all) {
      final SemanticsNode node = tester.getSemantics(find.byWidget(key));
      expect(
        node.label,
        matches(words),
        reason: 'the "$face" key is read as "${node.label}"',
      );
      expect(node, isSemantics(isButton: true), reason: face);
    }
    handle.dispose();
  });

  testWidgets('undo and redo say which they are, and when they cannot act', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpKeypad(tester);

    final Iterable<MyButton> pair = tester
        .widgetList<MyButton>(find.byType(MyButton))
        .where((MyButton b) => b.buttonText == '⎌');
    final List<String> labels = <String>[
      for (final MyButton b in pair)
        tester.getSemantics(find.byWidget(b)).label,
    ];
    expect(labels, unorderedEquals(<String>['undo', 'redo']));
    // Nothing has been done yet, so neither can act, and both say so.
    for (final MyButton b in pair) {
      final SemanticsNode node = tester.getSemantics(find.byWidget(b));
      expect(node, isSemantics(hasEnabledState: true, isEnabled: false));
    }
    handle.dispose();
  });

  testWidgets('a long-press menu is offered as named actions', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpKeypad(tester);

    final PopupMenuCalcButton sine = tester
        .widgetList<PopupMenuCalcButton>(find.byType(PopupMenuCalcButton))
        .firstWhere((PopupMenuCalcButton b) => b.buttonText == 'sin');
    final SemanticsData data =
        tester.getSemantics(find.byWidget(sine)).getSemanticsData();
    expect(data.label, 'sine');
    final List<String> actions = <String>[
      for (final int id in data.customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label!,
    ];
    expect(actions, contains('hyperbolic sine'));
    handle.dispose();
  });

  testWidgets('a screen reader double tap types the key', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpKeypad(tester);

    final MyButton seven = tester
        .widgetList<MyButton>(find.byType(MyButton))
        .firstWhere((MyButton b) => b.buttonText == '7');
    final SemanticsNode node = tester.getSemantics(find.byWidget(seven));
    // Through the node's own owner, which is the view's, not the root's.
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(MathExpressionSerializer.serialize(controller.expression), '7');
    handle.dispose();
  });

  test('glyphs are spelled out, and plain faces read as themselves', () {
    expect(spokenKeyLabel('⌫'), 'backspace');
    expect(spokenKeyLabel('ⁿ√'), 'root');
    expect(spokenKeyLabel('x̂'), 'unit vector x');
    expect(spokenKeyLabel('θ̂'), 'unit vector theta');
    expect(spokenKeyLabel('θ'), 'theta');
    expect(spokenKeyLabel('7'), '7');
    expect(spokenKeyLabel('x'), 'x');
  });
}
