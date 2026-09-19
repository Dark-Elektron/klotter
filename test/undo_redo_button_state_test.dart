import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Undo and redo look dead when there is nothing to undo or redo.
///
/// They were always drawn live, so pressing one with an empty history did
/// nothing and gave no reason why.
void main() {
  Future<SettingsProvider> seed() async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          {'expression': jsonEncode(<Map<String, dynamic>>[])},
        ],
        'activeIndex': 0,
      }),
    });
    return SettingsProvider.create();
  }

  /// The opacity of the undo glyph, which is what "greyed out" means here.
  /// Both keys carry the same character, so they are told apart by position:
  /// redo is the mirrored one and sits to the right of undo.
  List<double> undoRedoAlpha(WidgetTester tester) {
    final Iterable<Text> glyphs =
        tester.widgetList<Text>(find.text('\u238C')).toList();
    expect(glyphs.length, 2, reason: 'expected an undo and a redo key');
    return <double>[for (final Text t in glyphs) t.style?.color?.a ?? 1.0];
  }

  testWidgets('both are dim with an empty history, and undo lights up', (
    tester,
  ) async {
    final settings = await seed();
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
    await tester.pump(const Duration(milliseconds: 800));

    // Reach the extras page, where undo and redo live.
    // Not pumpAndSettle: the caret blinks forever, so nothing ever settles.
    await tester.drag(find.text('sin').first, const Offset(-350, 0));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final List<double> before = undoRedoAlpha(tester);
    expect(
      before.every((double a) => a < 0.5),
      isTrue,
      reason: 'nothing has been typed yet, so neither key should look live',
    );

    await tester.tap(find.text('7').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('7').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));

    final List<double> after = undoRedoAlpha(tester);
    expect(
      after.any((double a) => a > 0.5),
      isTrue,
      reason: 'there is something to undo now, so undo should look live',
    );
  });
}
