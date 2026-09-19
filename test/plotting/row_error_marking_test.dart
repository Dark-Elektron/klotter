import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// A row that cannot be drawn says which row it is.
///
/// The banner over the plot names the first problem but not the line it
/// belongs to. With rows stacked that is the half you need — "unknown
/// variable" says nothing about which of three lines wrote it.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  Future<Map<int, String>> errorsFor(
    WidgetTester tester,
    List<MathNode> nodes,
  ) async {
    Map<int, String> seen = const <int, String>{};
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 360,
              child: InlinePlotPanel(
                expression: 'cell',
                nodes: nodes,
                onRowErrors: (Map<int, String> byRow) => seen = byRow,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('the row that is wrong is the row that is named', (tester) async {
    // Second line is nonsense, the others are fine.
    final Map<int, String> errors = await errorsFor(tester, <MathNode>[
      LiteralNode(text: 'x^2'),
      NewlineNode(),
      LiteralNode(text: 'qq+'),
      NewlineNode(),
      LiteralNode(text: '2x'),
    ]);

    expect(errors.keys, <int>[1], reason: 'errors reported for $errors');
    expect(errors[1], isNotEmpty, reason: 'no reason given for the bad row');
  });

  testWidgets('a cell where everything works marks nothing', (tester) async {
    final Map<int, String> errors = await errorsFor(tester, <MathNode>[
      LiteralNode(text: 'x^2'),
      NewlineNode(),
      LiteralNode(text: '2x'),
    ]);
    expect(errors, isEmpty, reason: 'good rows were marked: $errors');
  });
}
