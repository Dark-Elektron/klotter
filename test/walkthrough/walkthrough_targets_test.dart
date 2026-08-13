import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';

/// The tour, run against the real app rather than a stub host.
///
/// The step list and the map of things it points at live in different files,
/// so a step can be written with nothing to highlight and the overlay will
/// quietly show it floating — it returns null for a missing target rather than
/// failing. Walking the whole tour in the app is what catches that.
void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      // Deliberately not completed: the tour should start.
      'calculator_cells': jsonEncode({
        'cells': <Map<String, dynamic>>[
          {
            'expression': jsonEncode(<Map<String, dynamic>>[
              {'type': 'literal', 'text': '2x'},
            ]),
          },
        ],
        'activeIndex': 0,
      }),
    });
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

  testWidgets('the tour starts and every step it shows can be reached', (
    tester,
  ) async {
    await pump(tester);

    // The tour is running.
    expect(find.text('Skip'), findsWidgets, reason: 'the tour did not start');

    // Walk it. Steps that ask for a swipe cannot be advanced with the Next
    // button, so this stops at the first of those rather than forcing it —
    // reaching them at all is what matters here.
    final Set<String> seen = <String>{};
    for (int i = 0; i < walkthroughSteps.length + 2; i++) {
      for (final WalkthroughStep step in walkthroughSteps) {
        if (find.text(step.title).evaluate().isNotEmpty) seen.add(step.id);
      }
      final Finder next = find.text('Next');
      if (next.evaluate().isEmpty) break;
      await tester.tap(next.first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    expect(
      seen,
      contains('expression_area'),
      reason: 'the tour should open on the expression',
    );
    expect(
      seen,
      contains('plot_pages'),
      reason: 'the plots step was never shown; is its target wired up?',
    );
  });

  group('the copy describes klotter, not klator', () {
    String allText() =>
        walkthroughSteps
            .map((WalkthroughStep s) => '${s.title} ${s.description}')
            .join('\n')
            .toLowerCase();

    test('the command key is not described as making a new cell', () {
      // ⌘ inserts a line inside the current cell, and every line of a cell is
      // drawn as its own curve on that cell's plot. A new plot comes from the
      // swipe strip. The tour said it created a cell, which is klator.
      final WalkthroughStep command = walkthroughSteps.firstWhere(
        (WalkthroughStep s) => s.id == 'command_button',
      );
      final String text = command.description.toLowerCase();
      expect(text, contains('line'));
      expect(
        text,
        isNot(contains('new calculation cell')),
        reason: 'that is what the other app does',
      );
    });

    test('plotting is covered', () {
      final String text = allText();
      for (final String topic in <String>['plot', '2d', '3d', 'curve']) {
        expect(text, contains(topic), reason: 'the tour never mentions $topic');
      }
    });

    test('the export key is mentioned where it lives', () {
      final Iterable<WalkthroughStep> extras = walkthroughSteps.where(
        (WalkthroughStep s) => s.id.contains('extras'),
      );
      expect(extras, isNotEmpty);
      expect(
        extras.any((WalkthroughStep s) => s.description.contains('⇪')),
        isTrue,
        reason: 'the extras keypad gained an export key',
      );
    });
  });
}
