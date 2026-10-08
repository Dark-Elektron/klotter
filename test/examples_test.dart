import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/examples.dart';
import 'package:klotter/help.dart';
import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Every node list hanging off [nodes], [nodes] included.
Iterable<List<MathNode>> listsIn(List<MathNode> nodes) sync* {
  yield nodes;
  for (final MathNode n in nodes) {
    final List<List<MathNode>> children = switch (n) {
      ExponentNode(:final base, :final power) => <List<MathNode>>[base, power],
      TrigNode(:final argument) => <List<MathNode>>[argument],
      FractionNode(:final numerator, :final denominator) => <List<MathNode>>[
        numerator,
        denominator,
      ],
      _ => const <List<MathNode>>[],
    };
    for (final List<MathNode> child in children) {
      yield* listsIn(child);
    }
  }
}

/// Plots to start from: on the help page, and three on an empty plot.
void main() {
  group('every example', () {
    for (final PlotExample example in plotExamples) {
      test('${example.title} draws without an error', () {
        final List<List<MathNode>> rows = example.rows();
        expect(rows, hasLength(example.reads.length));
        final PlotDefinitions definitions = PlotDefinitions.read(rows);
        expect(definitions.errors, isEmpty);
        for (int r = 0; r < rows.length; r++) {
          if (definitions.rows.containsKey(r)) continue;
          final String? error =
              VectorFieldParser.isVectorFieldNodes(rows[r])
                  ? VectorFieldParser.fromNodes(
                    rows[r],
                    definitions: definitions,
                  )!.error
                  : PlotExpression.compile(
                    rows[r],
                    definitions: definitions,
                  ).error;
          expect(error, isNull, reason: '${example.reads[r]}: $error');
        }
      });

      test('${example.title} is laid out as the editor keeps a row', () {
        // Text at both ends of every list, so the caret can stand either
        // side of every structure in it.
        for (final List<MathNode> row in example.rows()) {
          for (final List<MathNode> list in listsIn(row)) {
            expect(list.first, isA<LiteralNode>());
            expect(list.last, isA<LiteralNode>());
            for (int i = 1; i < list.length; i++) {
              expect(
                list[i] is LiteralNode || list[i - 1] is LiteralNode,
                isTrue,
                reason: 'two structures side by side in ${example.title}',
              );
            }
          }
        }
      });
    }

    test('is built new each time it is opened', () {
      final PlotExample circle = plotExamples.first;
      expect(identical(circle.rows().first, circle.rows().first), isFalse);
    });

    test('the three on an empty plot are among them', () {
      expect(startingExamples, hasLength(3));
      expect(plotExamples, containsAll(startingExamples));
    });
  });

  testWidgets('the help page closes with the example tapped', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    PlotExample? chosen;
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    chosen = await Navigator.push<PlotExample>(
                      context,
                      MaterialPageRoute<PlotExample>(
                        builder: (_) => const HelpPage(),
                      ),
                    );
                  },
                  child: const Text('help'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();
    expect(find.text('Examples'), findsOneWidget);
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(chosen?.title, 'Circle');
    expect(find.byType(HelpPage), findsNothing);
  });

  group('on the page', () {
    Future<HomePageState> pump(WidgetTester tester, List<String> rows) async {
      String row(String t) => MathExpressionSerializer.serializeToJson(
        <MathNode>[LiteralNode(text: t)],
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
        'calculator_cells': jsonEncode(<String, dynamic>{
          'version': 2,
          'cells': <Map<String, dynamic>>[
            <String, dynamic>{
              'rows': <String>[for (final String t in rows) row(t)],
            },
          ],
          'activeIndex': 0,
        }),
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final GlobalKey<HomePageState> key = GlobalKey<HomePageState>();
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(home: HomePage(key: key)),
        ),
      );
      await settle(tester);
      return key.currentState!;
    }

    List<String> rowsOf(HomePageState state, int plot) => <String>[
      for (final r in state.rowsOf(plot)) r.controller.getExpression(),
    ];

    testWidgets('an empty plot offers three, and one fills it', (tester) async {
      final HomePageState state = await pump(tester, <String>['']);
      expect(find.text('Start from an example'), findsOneWidget);
      expect(find.text('sin(kx)'), findsOneWidget);
      expect(find.text('x² + y² = 1'), findsOneWidget);
      expect(find.text('x² − y²'), findsOneWidget);

      await tester.tap(find.text('sin(kx)'));
      await settle(tester);
      expect(state.count, 1, reason: 'an empty plot is filled, not added to');
      expect(rowsOf(state, 0), hasLength(2));
      expect(rowsOf(state, 0).first, 'k=2');
      expect(
        find.text('Start from an example'),
        findsNothing,
        reason: 'the offer goes once the plot has something on it',
      );

      // One step: undo empties it again rather than going row by row.
      state.undoAppState();
      await settle(tester);
      expect(rowsOf(state, 0).every((String r) => r.trim().isEmpty), isTrue);
      expect(find.text('Start from an example'), findsOneWidget);
    });

    testWidgets('a plot with something on it is left alone', (tester) async {
      final HomePageState state = await pump(tester, <String>['2x']);
      expect(find.text('Start from an example'), findsNothing);
      final List<String> before = rowsOf(state, 0);

      state.openExample(plotExamples.firstWhere((e) => e.title == 'Circle'));
      await settle(tester);
      expect(state.count, 2);
      expect(state.activeIndex, 1);
      expect(rowsOf(state, 0), before);
      expect(rowsOf(state, 1), hasLength(1));

      state.undoAppState();
      await settle(tester);
      expect(state.count, 1, reason: 'undo takes the new plot away too');
      expect(rowsOf(state, 0), before);
    });

    testWidgets('a surface opens in 3D', (tester) async {
      final HomePageState state = await pump(tester, <String>['']);
      await tester.tap(find.text('x² − y²'));
      await settle(tester);
      expect(state.notebook.activePlot.view.show3D, isTrue);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
