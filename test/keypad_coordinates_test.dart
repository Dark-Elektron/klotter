import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/keypad/buttons.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/keypad/popup_menu_button.dart';
import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/coordinate_system.dart';

/// The scientific page: where the keys sit, and switching what they mean.
///
/// The row is ten keys wide on purpose — a typing keyboard's row — so this
/// pins positions rather than counting keys, and every key is checked against
/// the one above or below it.
void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
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
    await tester.pump(const Duration(milliseconds: 900));
  }

  /// Top-left of the key carrying [label] on the scientific page.
  Offset at(WidgetTester tester, String label) {
    final Finder text = find.text(label);
    expect(text, findsWidgets, reason: 'no key labelled "$label"');
    // Both kinds: a key with a long-press menu is a PopupMenuCalcButton, a
    // plain one is a MyButton. Falling back to the text's own origin would
    // measure the label's inset instead of the key, which is a whole different
    // number and made every row look misaligned.
    for (final Finder kind in <Finder>[
      find.ancestor(of: text.first, matching: find.byType(PopupMenuCalcButton)),
      find.ancestor(of: text.first, matching: find.byType(MyButton)),
    ]) {
      if (kind.evaluate().isNotEmpty) return tester.getTopLeft(kind.first);
    }
    return tester.getTopLeft(text.first);
  }

  /// The keypad on its own, with the coordinate systems set directly.
  Future<void> pumpKeypad(
    WidgetTester tester, {
    CoordinateSystem variables = CoordinateSystem.cartesian,
    CoordinateSystem unitVectors = CoordinateSystem.cartesian,
  }) async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    final walkthrough = WalkthroughService();
    addTearDown(walkthrough.dispose);

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
                    mathEditorControllers: <int, MathEditorController>{},
                    textDisplayControllers: <int, TextEditingController>{},
                    settingsProvider: settings,
                    onUpdateMathEditor: () {},
                    onAddDisplay: () {},
                    onRemoveDisplay: (_) {},
                    onClearAllDisplays: () {},
                    onSetState: () {},
                    walkthroughService: walkthrough,
                    scientificKeypadKey: GlobalKey(),
                    numberKeypadKey: GlobalKey(),
                    extrasKeypadKey: GlobalKey(),
                    commandButtonKey: GlobalKey(),
                    mainKeypadAreaKey: GlobalKey(),
                    settingsButtonKey: GlobalKey(),
                    variableSystem: variables,
                    unitVectorSystem: unitVectors,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the scientific page is laid out as specified', () {
    testWidgets('row one runs x y z sin cos tan = x² π log', (tester) async {
      await pump(tester);
      const List<String> row = <String>[
        'x',
        'y',
        'z',
        'sin',
        'cos',
        'tan',
        '=',
        'x²',
        'π',
        'log',
      ];
      final double y = at(tester, 'x').dy;
      double previous = double.negativeInfinity;
      for (final String key in row) {
        final Offset p = at(tester, key);
        expect(p.dy, closeTo(y, 1.0), reason: '$key is not on the first row');
        expect(p.dx, greaterThan(previous), reason: '$key is out of order');
        previous = p.dx;
      }
    });

    testWidgets('row two runs x̂ ŷ ẑ asin acos atan ≥ √ e °', (tester) async {
      await pump(tester);
      final List<String> row = <String>[
        ...CoordinateSystem.cartesian.unitVectorLabels,
        'asin',
        'acos',
        'atan',
        '≥',
        '√',
        'e',
        '°',
      ];
      final double y = at(tester, row.first).dy;
      double previous = double.negativeInfinity;
      for (final String key in row) {
        final Offset p = at(tester, key);
        expect(p.dy, closeTo(y, 1.0), reason: '$key is not on the second row');
        expect(p.dx, greaterThan(previous), reason: '$key is out of order');
        previous = p.dx;
      }
      expect(
        y,
        greaterThan(at(tester, 'x').dy),
        reason: 'the second row is below the first',
      );
    });

    testWidgets('each key sits under its relative', (tester) async {
      await pump(tester);
      final List<String> hats = CoordinateSystem.cartesian.unitVectorLabels;
      final Map<String, String> pairs = <String, String>{
        'x': hats[0],
        'y': hats[1],
        'z': hats[2],
        'sin': 'asin',
        'cos': 'acos',
        'tan': 'atan',
        '=': '≥',
        'x²': '√',
        'π': 'e',
        'log': '°',
      };
      pairs.forEach((String above, String below) {
        expect(
          at(tester, below).dx,
          closeTo(at(tester, above).dx, 1.0),
          reason: '$below should sit directly under $above',
        );
      });
    });

    testWidgets('the nth root moved inside the square root', (tester) async {
      await pump(tester);
      expect(
        find.text('ⁿ√'),
        findsNothing,
        reason: 'it is a long press on √ now, not a key of its own',
      );
    });
  });

  group('long press switches a whole group', () {
    /// Fixed pumps: the plot above the keypad animates continuously, so
    /// pumpAndSettle never returns.
    Future<void> settle(WidgetTester tester) async {
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    /// Hold a key, drag onto one of its menu entries, release.
    ///
    /// These menus are press-and-drag: the overlay appears on long-press and
    /// onLongPressEnd commits whatever is highlighted, so a press followed by
    /// a separate tap selects nothing and closes the menu.
    Future<void> pickFromMenu(
      WidgetTester tester,
      String key,
      Pattern entry,
    ) async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text(key).first),
      );
      await tester.pump(const Duration(milliseconds: 700));

      final Finder item = find.textContaining(entry);
      expect(item, findsWidgets, reason: 'no menu entry matching $entry');
      await gesture.moveTo(tester.getCenter(item.first));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await settle(tester);
    }

    /// Just open the menu and leave it up.
    Future<TestGesture> openMenu(WidgetTester tester, String key) async {
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text(key).first),
      );
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    testWidgets('a variable key offers the other systems', (tester) async {
      await pump(tester);
      final TestGesture gesture = await openMenu(tester, 'x');

      // The menu offers the symbol this key becomes, not the name of the
      // system it belongs to: hold x and you are offered r and ρ.
      expect(find.text('r'), findsOneWidget);
      expect(find.text('ρ'), findsOneWidget);
      expect(
        find.textContaining('Cartesian'),
        findsNothing,
        reason: 'system names are not what the keys are about',
      );
      expect(find.textContaining('Polar'), findsNothing);
      expect(find.textContaining('Spherical'), findsNothing);

      await gesture.up();
      await settle(tester);
    });

    testWidgets('choosing polar changes all three variables at once', (
      tester,
    ) async {
      await pump(tester);
      await pickFromMenu(tester, 'x', 'r');

      for (final String key in CoordinateSystem.cylindrical.variables) {
        expect(find.text(key), findsWidgets, reason: '$key is missing');
      }
      expect(
        find.text('y'),
        findsNothing,
        reason: 'a row must never mix two systems',
      );

      // The unit vectors follow. A row of x, y, z beside r̂, θ̂, ẑ would name a
      // point in one system and its directions in another.
      expect(
        find.text(CoordinateSystem.cylindrical.unitVectorLabels.first),
        findsWidgets,
        reason: 'the unit vectors should have moved with the variables',
      );
      expect(
        find.text(CoordinateSystem.cartesian.unitVectorLabels.first),
        findsNothing,
      );
    });

    testWidgets('spherical uses ρ and φ, keeping r for cylindrical', (
      tester,
    ) async {
      await pump(tester);
      await pickFromMenu(tester, 'x', 'ρ');

      expect(find.text('ρ'), findsWidgets);
      expect(find.text('θ'), findsWidgets);
      expect(find.text('φ'), findsWidgets);
      expect(
        find.text('r'),
        findsNothing,
        reason: 'ISO keeps r for the cylindrical radius',
      );
    });

    testWidgets('unit vectors switch on their own', (tester) async {
      // Driven through the widget's own state rather than the overlay. What
      // matters is that a group moves as one and leaves the other alone; the
      // menu itself is the same _sciMenu the variable keys use, which the
      // test above exercises end to end.
      await pumpKeypad(tester, unitVectors: CoordinateSystem.spherical);

      final List<String> spherical =
          CoordinateSystem.spherical.unitVectorLabels;
      for (final String hat in spherical) {
        expect(find.text(hat), findsWidgets, reason: '$hat is missing');
      }
      for (final String hat in CoordinateSystem.cartesian.unitVectorLabels) {
        expect(find.text(hat), findsNothing, reason: '$hat should be gone');
      }
      expect(
        find.text('x'),
        findsWidgets,
        reason: 'the variables were not asked to change',
      );
    });

    testWidgets('the two groups switch independently', (tester) async {
      await pumpKeypad(
        tester,
        variables: CoordinateSystem.spherical,
        unitVectors: CoordinateSystem.cylindrical,
      );

      // Variables spherical, unit vectors cylindrical, each internally
      // consistent and neither mixed.
      for (final String v in CoordinateSystem.spherical.variables) {
        expect(find.text(v), findsWidgets);
      }
      for (final String hat in CoordinateSystem.cylindrical.unitVectorLabels) {
        expect(find.text(hat), findsWidgets);
      }
      expect(
        find.text(CoordinateSystem.spherical.unitVectorLabels.first),
        findsNothing,
        reason: 'the unit vectors are cylindrical, not spherical',
      );
      expect(find.text('x'), findsNothing);
    });

    // One test per system: pumping the keypad repeatedly inside a single
    // test attaches its PageController to two scroll views at once.
    for (final CoordinateSystem system in CoordinateSystem.values) {
      testWidgets('${system.label} shows no symbol from another system', (
        tester,
      ) async {
        await pumpKeypad(tester, variables: system);
        for (final CoordinateSystem other in CoordinateSystem.values) {
          if (other == system) continue;
          for (final String v in other.variables) {
            // z is in both Cartesian and cylindrical, θ in both cylindrical
            // and spherical. A shared symbol is not a mixed row.
            if (system.variables.contains(v)) continue;
            expect(
              find.text(v),
              findsNothing,
              reason:
                  '$v belongs to ${other.label}, but the row is ${system.label}',
            );
          }
        }
      });
    }
  });

  group('the inequality key', () {
    testWidgets('shows ≥ and offers the rest', (tester) async {
      await pump(tester);
      expect(find.text('≥'), findsOneWidget);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('≥')),
      );
      await tester.pump(const Duration(milliseconds: 700));

      for (final String op in <String>['>', '≤', '<', '≠']) {
        expect(find.text(op), findsWidgets, reason: '$op is not offered');
      }

      await gesture.up();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    });
  });
}
