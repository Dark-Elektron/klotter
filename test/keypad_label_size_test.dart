import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';

/// How large the key labels are drawn.
///
/// Each keypad measures its labels against its keys: each length of label
/// gets the largest size at which every label of that length fits, so labels
/// of one length match and none is shrunk further than it must be. A phone
/// leaves its labels less room either side and stacks the inverse functions,
/// "arc" over the function, so sin, cos and tan can be drawn at full size on
/// keys a third narrower than a tablet's. d/dx is a fraction on both.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    settings = await SettingsProvider.create();
  });

  tearDown(() => settings.dispose());

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    required bool landscape,
  }) async {
    final MathEditorController controller = MathEditorController();
    addTearDown(controller.dispose);
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

  // The tablet the sizes were measured on: a Xiaomi Pad 5, 2560 × 1600 at
  // density 360, so 711 × 1138 dp standing up. And the phone: a Galaxy A54,
  // 384 × 832 dp.
  const Size portrait = Size(711, 1138);
  const Size landscape = Size(1138, 711);
  const Size phone = Size(384, 832);

  /// Every drawn line of text [label]: its font size, how wide it is laid
  /// out, and how much room its key leaves for it.
  List<({double size, double width, double room})> drawn(
    WidgetTester tester,
    String label,
  ) {
    return <({double size, double width, double room})>[
      for (final Element e in find.text(label).evaluate())
        () {
          final Text text = e.widget as Text;
          final RenderParagraph paragraph =
              e.findRenderObject()! as RenderParagraph;
          final Element key =
              find
                  .ancestor(
                    of: find.byElementPredicate((Element x) => x == e),
                    matching: find.byWidgetPredicate(
                      (Widget w) => w is MyButton || w is PopupMenuCalcButton,
                    ),
                  )
                  .evaluate()
                  .first;
          final double cell = (key.findRenderObject()! as RenderBox).size.width;
          final double padding =
              KeyLabelScale.maybeOf(e)?.labelPadding ?? keyLabelPadding;
          return (
            size: text.style!.fontSize!,
            width: paragraph.size.width,
            room: cell - settings.buttonSpacing - 2 * padding,
          );
        }(),
    ];
  }

  /// The key whose own label is [label], whatever its face shows.
  Finder keyFor(String label) => find.byWidgetPredicate(
    (Widget w) =>
        (w is PopupMenuCalcButton && w.buttonText == label) ||
        (w is MyButton && w.buttonText == label),
  );

  const List<String> fourLetters = <String>['asin', 'acos', 'atan'];
  const List<String> threeLetters = <String>['sin', 'cos', 'tan', 'log', '|x|'];

  for (final (String name, Size size, bool isLandscape)
      in <(String, Size, bool)>[
        ('portrait', portrait, false),
        ('landscape', landscape, true),
      ]) {
    group('a tablet in $name', () {
      testWidgets('labels of one length share one size', (tester) async {
        await pump(tester, size, landscape: isLandscape);
        for (final List<String> group in <List<String>>[
          fourLetters,
          threeLetters,
        ]) {
          final Set<double> sizes = <double>{
            for (final String label in group)
              for (final d in drawn(tester, label)) d.size,
          };
          expect(sizes, hasLength(1), reason: '$group: $sizes');
        }
      });

      testWidgets('every label fits its key at the size it is drawn', (
        tester,
      ) async {
        await pump(tester, size, landscape: isLandscape);
        for (final String label in <String>[...fourLetters, ...threeLetters]) {
          for (final d in drawn(tester, label)) {
            expect(
              d.width,
              lessThanOrEqualTo(d.room + 0.5),
              reason: '$label is ${d.width} wide in ${d.room}',
            );
          }
        }
      });

      testWidgets('no label is drawn smaller than it must be', (tester) async {
        // A length is either drawn whole, or its widest label fills its key.
        await pump(tester, size, landscape: isLandscape);
        for (final List<String> group in <List<String>>[
          fourLetters,
          threeLetters,
        ]) {
          final all = <({double size, double width, double room})>[
            for (final String label in group) ...drawn(tester, label),
          ];
          final bool whole = all.every((d) => d.size == 22);
          final double fullest = all
              .map((d) => d.width / d.room)
              .reduce((double a, double b) => a > b ? a : b);
          expect(
            whole || fullest > 0.97,
            isTrue,
            reason: '$group drawn at ${all.first.size}, fullest $fullest',
          );
        }
      });

      testWidgets('short labels are drawn whole', (tester) async {
        await pump(tester, size, landscape: isLandscape);
        for (final String label in <String>['7', 'x²', 'CE', '=']) {
          for (final d in drawn(tester, label)) {
            expect(d.size, 22, reason: label);
          }
        }
      });

      testWidgets('the inverse functions stay on one line', (tester) async {
        // There is room for them, and stacking is for a phone.
        await pump(tester, size, landscape: isLandscape);
        expect(find.text('arc'), findsNothing);
        expect(find.text('asin'), findsWidgets);
      });
    });
  }

  testWidgets('labels are no smaller in landscape than standing up', (
    tester,
  ) async {
    await pump(tester, portrait, landscape: false);
    final Map<String, double> standing = <String, double>{
      for (final String label in <String>[...fourLetters, ...threeLetters])
        label: drawn(tester, label).first.size,
    };
    await pump(tester, landscape, landscape: true);
    for (final String label in standing.keys) {
      expect(
        drawn(tester, label).first.size,
        greaterThanOrEqualTo(standing[label]!),
        reason: label,
      );
    }
  });

  group('a phone', () {
    testWidgets('draws the inverse functions as "arc" over the function', (
      tester,
    ) async {
      await pump(tester, phone, landscape: false);
      for (final String label in fourLetters) {
        final Finder key = keyFor(label);
        expect(key, findsOneWidget, reason: label);
        final Finder arc = find.descendant(of: key, matching: find.text('arc'));
        final Finder function = find.descendant(
          of: key,
          matching: find.text(label.substring(1)),
        );
        expect(arc, findsOneWidget, reason: label);
        expect(function, findsOneWidget, reason: label);
        expect(
          tester.getCenter(arc).dy,
          lessThan(tester.getCenter(function).dy),
          reason: '"arc" sits over ${label.substring(1)}',
        );
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets('sin, cos and tan are one size, stacked or not, and fit', (
      tester,
    ) async {
      // The lower line of "arc sin" is the same size as the sin key beside
      // it, and every one of them fits its key with the room a phone leaves.
      await pump(tester, phone, landscape: false);
      final List<({double size, double width, double room})> all =
          <({double size, double width, double room})>[
            for (final String label in <String>['sin', 'cos', 'tan'])
              ...drawn(tester, label),
          ];
      expect(all, hasLength(6), reason: 'three keys and three stacks');
      expect(<double>{for (final d in all) d.size}, hasLength(1));
      for (final d in all) {
        expect(d.width, lessThanOrEqualTo(d.room + 0.5));
      }
      final Set<double> arcs = <double>{
        for (final d in drawn(tester, 'arc')) d.size,
      };
      expect(arcs, <double>{22 * arcShare});
    });

    testWidgets('leaves its labels half a dp either side', (tester) async {
      await pump(tester, phone, landscape: false);
      final Element sin = find.text('sin').evaluate().first;
      expect(KeyLabelScale.maybeOf(sin)?.labelPadding, 0.5);
    });
  });

  for (final (String name, Size size, bool isLandscape)
      in <(String, Size, bool)>[
        ('phone', phone, false),
        ('tablet', portrait, false),
      ]) {
    testWidgets('d/dx is a fraction on a $name', (tester) async {
      await pump(tester, size, landscape: isLandscape);
      if (isLandscape == false && size == phone) {
        // On the extras page.
        await tester.drag(find.text('≥'), const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
      final Finder key = keyFor('d/dx');
      expect(key, findsOneWidget);
      expect(find.text('d/dx'), findsNothing);
      final Finder top = find.descendant(of: key, matching: find.text('d'));
      final Finder bottom = find.descendant(of: key, matching: find.text('dx'));
      expect(top, findsOneWidget);
      expect(bottom, findsOneWidget);
      expect(tester.getCenter(top).dy, lessThan(tester.getCenter(bottom).dy));
      expect(
        tester.getCenter(top).dx,
        closeTo(tester.getCenter(bottom).dx, 0.5),
        reason: 'centred over each other',
      );
      for (final Finder line in <Finder>[top, bottom]) {
        expect((tester.widget<Text>(line)).style!.fontSize, 22 * fractionShare);
      }
    });
  }
}
