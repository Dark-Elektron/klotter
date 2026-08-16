import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// ⌧ wipes every cell in one press, sits beside undo and redo, and looks like
/// any other glyph key. It asks first now — and says the press can be undone,
/// which was always true and never mentioned.
void main() {
  Future<SettingsProvider> seed({bool confirm = true}) async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'confirmClearAll': confirm,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          for (final String t in <String>['x^2', '2x', 'sin'])
            {
              'expression': jsonEncode(<Map<String, dynamic>>[
                {'type': 'literal', 'text': t},
              ]),
            },
        ],
        'activeIndex': 0,
      }),
    });
    return SettingsProvider.create();
  }

  Future<HomePageState> pump(
    WidgetTester tester,
    SettingsProvider settings,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    return tester.state<HomePageState>(find.byType(HomePage));
  }

  /// Press ⌧. It lives on the extras page of the keypad, so the keypad has to
  /// be swiped over to it first — the same way export_button_test reaches it.
  Future<void> pressClearAll(WidgetTester tester) async {
    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1000);
    await tester.pump(const Duration(milliseconds: 600));
    final Finder key = find.text('⌧');
    expect(key, findsOneWidget, reason: 'the clear-all key is not on screen');
    await tester.tap(key);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Tap one of the dialog's buttons.
  ///
  /// By its text inside the dialog rather than by button type: the two are a
  /// TextButton and a FilledButton, and matching on a shared supertype found
  /// nothing at all.
  Future<void> tapDialog(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('with the warning on', () {
    testWidgets('pressing it asks rather than clearing', (tester) async {
      final settings = await seed();
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);
      expect(state.count, 3);

      await pressClearAll(tester);

      expect(find.text('Clear all plots?'), findsOneWidget);
      // Nothing gone yet. This is the assertion the whole feature rests on.
      expect(state.count, 3, reason: 'cleared before answering');
    });

    testWidgets('it says the press can be undone', (tester) async {
      // The point of the dialog. The key was always undoable; nobody was told,
      // so the loss felt permanent whether or not it was.
      final settings = await seed();
      addTearDown(settings.dispose);
      await pump(tester, settings);

      await pressClearAll(tester);
      expect(find.textContaining('undo'), findsOneWidget);
    });

    testWidgets('cancelling leaves the cells alone', (tester) async {
      final settings = await seed();
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);

      await pressClearAll(tester);
      await tapDialog(tester, 'Cancel');

      expect(state.count, 3);
      expect(find.text('Clear all plots?'), findsNothing);
    });

    testWidgets('confirming clears them, and undo really can bring them back', (
      tester,
    ) async {
      final settings = await seed();
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);

      await pressClearAll(tester);
      await tapDialog(tester, 'Clear all');

      expect(state.count, 1);
      // The dialog made a promise; this is the promise being true. If the
      // clearing ever stopped saving an undo point, this fails rather than the
      // app quietly lying to the user.
      expect(state.canUndoAppState, isTrue);
    });
  });

  group('the "don\'t ask again" box', () {
    testWidgets('turns the warning off when the clear goes ahead', (
      tester,
    ) async {
      final settings = await seed();
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);

      await pressClearAll(tester);
      await tester.tap(find.text("Don't ask again"));
      await tester.pump();
      await tapDialog(tester, 'Clear all');

      expect(state.count, 1);
      expect(settings.confirmClearAll, isFalse);
    });

    testWidgets('but not when the clear is cancelled', (tester) async {
      // Ticking a box and then backing out is not an instruction to stop
      // warning you.
      final settings = await seed();
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);

      await pressClearAll(tester);
      await tester.tap(find.text("Don't ask again"));
      await tester.pump();
      await tapDialog(tester, 'Cancel');

      expect(state.count, 3);
      expect(settings.confirmClearAll, isTrue);
    });
  });

  group('with the warning off', () {
    testWidgets('pressing it clears straight away', (tester) async {
      final settings = await seed(confirm: false);
      addTearDown(settings.dispose);
      final state = await pump(tester, settings);
      expect(settings.confirmClearAll, isFalse);

      await pressClearAll(tester);

      expect(find.text('Clear all plots?'), findsNothing);
      expect(state.count, 1);
    });

    testWidgets('and the setting can be turned back on', (tester) async {
      // The escape hatch. Without it the tick is a one-way door.
      final settings = await seed(confirm: false);
      addTearDown(settings.dispose);
      await settings.toggleConfirmClearAll(true);
      expect(settings.confirmClearAll, isTrue);
    });
  });
}
