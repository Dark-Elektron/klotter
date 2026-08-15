import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On a tablet every key is on screen at once: one grid of three 20-key blocks,
/// no swiping and no fixed/swipeable split.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    settings = await SettingsProvider.create();
  });

  tearDown(() => settings.dispose());

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
                  mathEditorControllers: {0: controller},
                  textDisplayControllers: const {},
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

  /// Distinct key rows, by y position, among the main grid buttons.
  int rowCount(WidgetTester tester) {
    final ys = <double>{};
    for (final finder in <Finder>[
      find.byType(MyButton),
      find.byType(PopupMenuCalcButton),
    ]) {
      for (final e in finder.evaluate()) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.hasSize) continue;
        ys.add(
          double.parse(box.localToGlobal(Offset.zero).dy.toStringAsFixed(1)),
        );
      }
    }
    return ys.length;
  }

  group('grid shape follows orientation, not a preference', () {
    testWidgets('landscape gives three rows', (tester) async {
      await pumpTablet(tester, landscape: true);
      expect(rowCount(tester), equals(3));
    });

    testWidgets('portrait gives four rows', (tester) async {
      await pumpTablet(tester, landscape: false);
      expect(rowCount(tester), equals(4));
    });

    testWidgets('keys are the same size across all three blocks', (
      tester,
    ) async {
      // The number pad used to be a fixed half at a different scale.
      await pumpTablet(tester, landscape: false);
      Size sizeOf(String label) =>
          tester.getSize(find.widgetWithText(MyButton, label).first);
      // Not a unit vector: those carry the coordinate-system menu now, so
      // they are PopupMenuCalcButtons rather than plain MyButtons.
      expect(sizeOf('7'), equals(sizeOf('°')));
      expect(sizeOf('7'), equals(sizeOf('=')));
    });
  });

  group('landscape geometry', () {
    testWidgets('columns across the whole keypad total 20', (tester) async {
      await pumpTablet(tester, landscape: true);
      final xs = <double>{};
      for (final finder in <Finder>[
        find.byType(MyButton),
        find.byType(PopupMenuCalcButton),
      ]) {
        for (final e in finder.evaluate()) {
          final box = e.renderObject as RenderBox?;
          if (box == null || !box.hasSize) continue;
          xs.add(
            double.parse(box.localToGlobal(Offset.zero).dx.toStringAsFixed(1)),
          );
        }
      }
      // A true 3x20 holding all 60 keys: the groups are not all rectangles,
      // so numbers stays a clean 7-wide block while the extras/scientific
      // boundary steps one column between the first row and the rest.
      expect(xs.length, equals(20));
    });

    testWidgets('every key is the same size across the three blocks', (
      tester,
    ) async {
      await pumpTablet(tester, landscape: true);
      Size sizeOf(String label) =>
          tester.getSize(find.widgetWithText(MyButton, label).first);
      // ° rather than a unit vector: those carry the coordinate-system menu
      // now, so they are PopupMenuCalcButtons rather than plain MyButtons.
      expect(sizeOf('⌧').width, closeTo(sizeOf('°').width, 0.5));
      expect(sizeOf('7').width, closeTo(sizeOf('°').width, 0.5));
    });

    testWidgets('the dropped extras key is still reachable elsewhere', (
      tester,
    ) async {
      // Extras sheds its duplicate `x`; scientific still provides it (with y
      // and z on long-press).
      await pumpTablet(tester, landscape: true);
      expect(find.text('x'), findsWidgets);
    });
  });

  group('settings and help sit on the outer edge', () {
    testWidgets('right-handed puts them at the far left', (tester) async {
      await pumpTablet(tester, landscape: true);
      final double settingsX = tester.getTopLeft(find.text('☰').first).dx;
      final double helpX = tester.getTopLeft(find.text('ⓘ').first).dx;
      final double sciX = tester.getTopLeft(find.text('x̂').first).dx;
      expect(settingsX, lessThan(sciX));
      expect(helpX, lessThan(sciX));
      // Settings leads the edge column; help sits beside it.
      expect(helpX, greaterThan(settingsX));
    });

    testWidgets('left-handed carries them to the far right', (tester) async {
      await pumpTablet(tester, landscape: true, hand: Handedness.leftHanded);
      final double settingsX = tester.getTopLeft(find.text('☰').first).dx;
      final double sciX = tester.getTopLeft(find.text('x̂').first).dx;
      expect(settingsX, greaterThan(sciX));
    });
  });

  group('both orientations show the same keys', () {
    Future<Set<String>> labelsFor(WidgetTester tester, bool landscape) async {
      await pumpTablet(tester, landscape: landscape);
      final out = <String>{};
      for (final e in find.byType(Text).evaluate()) {
        final t = (e.widget as Text).data;
        if (t != null && t.isNotEmpty) out.add(t);
      }
      return out;
    }

    testWidgets('all 60 keys are present in both orientations', (tester) async {
      // extras 19 + scientific 20 + numbers 20.
      for (final landscape in <bool>[true, false]) {
        await pumpTablet(tester, landscape: landscape);
        int keys = 0;
        for (final finder in <Finder>[
          find.byType(MyButton),
          find.byType(PopupMenuCalcButton),
        ]) {
          for (final e in finder.evaluate()) {
            final w = e.widget;
            final bool blank = w is MyButton && w.buttonText.isEmpty;
            if (!blank) keys++;
          }
        }
        // 60: the extras block gained the export key.
        expect(keys, equals(60), reason: landscape ? 'landscape' : 'portrait');
      }
    });

    testWidgets('landscape and portrait carry an identical key set', (
      tester,
    ) async {
      // The key count used to differ between orientations (58 vs 60), which
      // meant rotating the tablet silently took keys away.
      final portrait = await labelsFor(tester, false);
      final landscape = await labelsFor(tester, true);
      expect(landscape, equals(portrait));
    });
  });

  group('grouping survives the reflow', () {
    /// Top-left corner of the KEY carrying [label].
    ///
    /// Measuring the button rather than the glyph matters: text is centred, so
    /// a narrow glyph starts further right than a wide one in the same cell.
    /// Where a key sits, choosing the one nearest [near] when the label
    /// appears more than once.
    ///
    /// sin, asin, x, √, π and x² are on the extras block as well as the
    /// scientific one, and on a tablet both are on screen at once. Taking the
    /// last match just picked whichever the current ordering happened to put
    /// second, so this test passed or failed on the order rather than on the
    /// grouping it means to check.
    Offset at(WidgetTester tester, String label, {Offset? near}) {
      Offset originOf(Element e) {
        final Finder text = find.byElementPredicate((c) => c == e);
        for (final Finder type in <Finder>[
          find.ancestor(of: text, matching: find.byType(MyButton)),
          find.ancestor(of: text, matching: find.byType(PopupMenuCalcButton)),
        ]) {
          if (type.evaluate().isNotEmpty) return tester.getTopLeft(type.first);
        }
        return tester.getTopLeft(text);
      }

      final List<Element> matches = find.text(label).evaluate().toList();
      expect(matches, isNotEmpty, reason: 'no key labelled "$label"');
      final List<Offset> origins = matches.map(originOf).toList();
      if (near == null || origins.length == 1) return origins.first;
      origins.sort(
        (a, b) => (a - near).distance.compareTo((b - near).distance),
      );
      return origins.first;
    }

    for (final landscape in <bool>[true, false]) {
      final orient = landscape ? 'landscape' : 'portrait';

      testWidgets('the six trig keys form one block in $orient', (
        tester,
      ) async {
        // The six stay together whichever way the grid runs: as two rows in
        // portrait, as two columns in landscape. They used to scatter.
        await pumpTablet(tester, landscape: landscape);

        // tan and atan appear once each; the rest are anchored to them.
        final tan = at(tester, 'tan');
        final atan = at(tester, 'atan');
        final cos = at(tester, 'cos', near: tan);
        final sin = at(tester, 'sin', near: tan);
        final acos = at(tester, 'acos', near: atan);
        final asin = at(tester, 'asin', near: atan);

        if (landscape) {
          // Landscape runs each family down its own column, with the inverses
          // in the column beside them, so the six still touch.
          expect(cos.dx, closeTo(sin.dx, 0.5));
          expect(tan.dx, closeTo(sin.dx, 0.5));
          expect(acos.dx, closeTo(asin.dx, 0.5));
          expect(atan.dx, closeTo(asin.dx, 0.5));

          expect(asin.dx, greaterThan(sin.dx));
          expect(asin.dy, closeTo(sin.dy, 0.5));
          expect(acos.dy, closeTo(cos.dy, 0.5));
          expect(atan.dy, closeTo(tan.dy, 0.5));
        } else {
          // Portrait keeps them as rows, inverses directly beneath.
          expect(cos.dy, closeTo(sin.dy, 0.5));
          expect(tan.dy, closeTo(sin.dy, 0.5));
          expect(acos.dy, closeTo(asin.dy, 0.5));
          expect(atan.dy, closeTo(asin.dy, 0.5));

          expect(asin.dy, greaterThan(sin.dy));
          expect(asin.dx, closeTo(sin.dx, 0.5));
          expect(acos.dx, closeTo(cos.dx, 0.5));
          expect(atan.dx, closeTo(tan.dx, 0.5));
        }
      });

      testWidgets('digits 1-9 form a 3x3 block in $orient', (tester) async {
        await pumpTablet(tester, landscape: landscape);
        for (final row in <List<String>>[
          <String>['7', '8', '9'],
          <String>['4', '5', '6'],
          <String>['1', '2', '3'],
        ]) {
          final first = at(tester, row.first);
          for (final d in row.skip(1)) {
            expect(at(tester, d).dy, closeTo(first.dy, 0.5));
          }
        }
        expect(at(tester, '4').dy, greaterThan(at(tester, '7').dy));
        expect(at(tester, '1').dy, greaterThan(at(tester, '4').dy));
      });

      testWidgets('backspace tops the outer column and the action key ends '
          'it in $orient', (tester) async {
        await pumpTablet(tester, landscape: landscape);
        final Offset back = at(tester, '⌫');
        final Offset action = at(tester, '⌘');
        expect(action.dx, closeTo(back.dx, 0.5), reason: 'same column');
        expect(action.dy, greaterThan(back.dy), reason: 'action sits below');

        // Numbers is the rightmost block for a right-hander, so that column
        // is the screen edge: nothing sits further right.
        double maxX = 0;
        double maxY = 0;
        for (final finder in <Finder>[
          find.byType(MyButton),
          find.byType(PopupMenuCalcButton),
        ]) {
          for (final e in finder.evaluate()) {
            final box = e.renderObject as RenderBox?;
            if (box == null || !box.hasSize) continue;
            final o = box.localToGlobal(Offset.zero);
            maxX = o.dx > maxX ? o.dx : maxX;
            maxY = o.dy > maxY ? o.dy : maxY;
          }
        }
        expect(back.dx, closeTo(maxX, 1), reason: 'outermost column');
        expect(back.dy, lessThan(action.dy));
        expect(action.dy, closeTo(maxY, 1), reason: 'bottom row');
      });

      testWidgets('the utility column runs clear to settings in $orient', (
        tester,
      ) async {
        await pumpTablet(tester, landscape: landscape);
        final Offset clear = at(tester, '⌧');
        // Redo is a mirrored undo, so both carry the same glyph — the first
        // in tree order is undo.
        final text = find.text('⎌').first;
        final Offset undo = tester.getTopLeft(
          find.ancestor(of: text, matching: find.byType(MyButton)).last,
        );
        final Offset settings = at(tester, '☰');

        // One column, clear at the top and settings at the bottom.
        expect(undo.dx, closeTo(clear.dx, 0.5));
        expect(settings.dx, closeTo(clear.dx, 0.5));
        expect(undo.dy, greaterThan(clear.dy));
        expect(settings.dy, greaterThan(undo.dy));
      });
    }
  });

  group('empty cells are deliberate, not holes', () {
    // The grid is authored per orientation now, so there are no spare cells
    // against portrait's 1. They must read as a ragged bottom edge rather than
    // as missing keys, so every one belongs in the last row.
    for (final landscape in <bool>[true, false]) {
      final orient = landscape ? 'landscape' : 'portrait';

      testWidgets('every gap sits in the bottom row in $orient', (
        tester,
      ) async {
        await pumpTablet(tester, landscape: landscape);

        final rows = <double>{};
        final gapRows = <double>{};
        for (final e in find.byType(MyButton).evaluate()) {
          final box = e.renderObject as RenderBox?;
          if (box == null || !box.hasSize) continue;
          final double y = double.parse(
            box.localToGlobal(Offset.zero).dy.toStringAsFixed(1),
          );
          rows.add(y);
          if ((e.widget as MyButton).buttonText.isEmpty) gapRows.add(y);
        }

        final sorted = rows.toList()..sort();
        for (final y in gapRows) {
          expect(y, equals(sorted.last), reason: 'gap outside the bottom row');
        }
      });
    }

    testWidgets('the numbers outer column has no hole in landscape', (
      tester,
    ) async {
      // A gap between backspace and the action key is the most visible place
      // it could land, and reads as a key that failed to render.
      await pumpTablet(tester, landscape: true);
      Offset at(String label) {
        final text = find.text(label).last;
        final btn = find.ancestor(of: text, matching: find.byType(MyButton));
        return tester.getTopLeft(btn.evaluate().isNotEmpty ? btn.last : text);
      }

      final Offset back = at('⌫');
      final Offset action = at('⌘');

      int inColumn = 0;
      for (final e in find.byType(MyButton).evaluate()) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final o = box.localToGlobal(Offset.zero);
        if ((o.dx - back.dx).abs() < 0.5 &&
            o.dy >= back.dy - 0.5 &&
            o.dy <= action.dy + 0.5) {
          inColumn++;
          expect(
            (e.widget as MyButton).buttonText,
            isNotEmpty,
            reason: 'blank between backspace and the action key',
          );
        }
      }
      expect(inColumn, equals(3), reason: 'three rows in that column');
    });
  });

  group('handedness mirrors the keypad', () {
    for (final landscape in <bool>[true, false]) {
      final orient = landscape ? 'landscape' : 'portrait';

      testWidgets('right-handed keeps numbers on the right in $orient', (
        tester,
      ) async {
        await pumpTablet(tester, landscape: landscape);
        // Anchors unique to one block: settings is extras-only, x̂ is
        // scientific-only, 7 is numbers-only. ('sin' appears in both extras
        // and scientific, so it cannot anchor anything.)
        double xOf(String label) =>
            tester.getTopLeft(find.text(label).first).dx;
        expect(xOf('x̂'), greaterThan(xOf('☰')));
        expect(xOf('7'), greaterThan(xOf('x̂')));
      });

      testWidgets('left-handed puts numbers on the left in $orient', (
        tester,
      ) async {
        await pumpTablet(
          tester,
          landscape: landscape,
          hand: Handedness.leftHanded,
        );
        double xOf(String label) =>
            tester.getTopLeft(find.text(label).first).dx;
        expect(xOf('7'), lessThan(xOf('x̂')));
        expect(xOf('x̂'), lessThan(xOf('☰')));
      });
    }
  });

  group('the phone number pad mirrors too', () {
    Future<void> pumpPhone(WidgetTester tester, Handedness hand) async {
      await settings.setHandedness(hand);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: 360, landscape: false));
      await tester.pumpAndSettle();
    }

    double xOf(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label).first).dx;

    testWidgets('right-handed keeps digits on the left half', (tester) async {
      await pumpPhone(tester, Handedness.rightHanded);
      // 5 and 0 lead their rows; the operators follow.
      expect(xOf(tester, '5'), lessThan(xOf(tester, '+')));
      expect(xOf(tester, '0'), lessThan(xOf(tester, '.')));
    });

    testWidgets('left-handed moves digits to the right half', (tester) async {
      await pumpPhone(tester, Handedness.leftHanded);
      expect(xOf(tester, '5'), greaterThan(xOf(tester, '+')));
      expect(xOf(tester, '0'), greaterThan(xOf(tester, '.')));
    });

    testWidgets('mirroring preserves every key', (tester) async {
      await pumpPhone(tester, Handedness.leftHanded);
      for (final label in <String>['0', '5', '9', '+', '.', 'CE']) {
        expect(find.text(label), findsWidgets, reason: '$label went missing');
      }
    });
  });

  testWidgets('a phone keeps the split keypad, not the tablet grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: 360, landscape: false));
    await tester.pumpAndSettle();

    // Phone: 2 rows of functions + 2 rows of numbers.
    expect(rowCount(tester), equals(4));
    // And the scientific page is swipeable, so extras is not on screen at once.
    expect(find.text('sin'), findsOneWidget);
  });
}
