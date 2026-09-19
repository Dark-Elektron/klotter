import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The eye closes on a field or a sweep, not only on a surface.
///
/// Hiding is a flag on PlotExpression, and a vector field is not one — it is a
/// VectorFieldParser, with nowhere to carry the flag. The fields were gathered
/// by filtering the lines, which threw away the row numbers, so nothing could
/// say which field belonged to the row whose eye had been closed. Leaving it
/// out of the list is what hiding has to mean here.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  List<MathNode> field() => <MathNode>[
    LiteralNode(text: 'y'),
    UnitVectorNode('x'),
    LiteralNode(text: '-x'),
    UnitVectorNode('y'),
  ];

  List<MathNode> sweep() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+u^2'),
    UnitVectorNode('y'),
  ];

  /// How many fields the painter was actually given.
  Future<int> fieldsDrawn(
    WidgetTester tester,
    List<MathNode> nodes, {
    required bool hidden,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              width: 360,
              child: InlinePlotPanel(
                expression: 'field',
                nodes: nodes,
                hiddenRows: <bool>[hidden],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final CustomPaint paint in tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    )) {
      final CustomPainter? p = paint.painter;
      if (p is Plot2DPainter) return p.vectorFields.length;
      if (p is Plot3DPainter) return p.vectorFields.length;
    }
    fail('no plot painter was built at all');
  }

  testWidgets('a hidden arrow field is not drawn', (tester) async {
    expect(
      await fieldsDrawn(tester, field(), hidden: false),
      1,
      reason: 'the field was not drawn even with its eye open',
    );
    expect(
      await fieldsDrawn(tester, field(), hidden: true),
      0,
      reason: 'the eye is closed and the field is still on the plot',
    );
  });

  testWidgets('a hidden parametric sweep is not drawn', (tester) async {
    expect(
      await fieldsDrawn(tester, sweep(), hidden: false),
      1,
      reason: 'the sweep was not drawn even with its eye open',
    );
    expect(
      await fieldsDrawn(tester, sweep(), hidden: true),
      0,
      reason: 'the eye is closed and the sweep is still on the plot',
    );
  });

  testWidgets('hiding a sweep does not report it as a bad expression', (
    tester,
  ) async {
    // A line written with unit vectors is not an ordinary expression. Once the
    // sweep was left out of the field list, the same line was still handed to
    // the expression parser, which said "unknown variable e_x, e_y" — an error
    // banner about a row whose eye had just been closed.
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              width: 360,
              child: InlinePlotPanel(
                expression: 'sweep',
                nodes: sweep(),
                hiddenRows: const <bool>[true],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('unknown variable', findRichText: true),
      findsNothing,
      reason: 'a hidden row is being reported as a broken expression',
    );
    expect(
      find.textContaining('Cannot plot', findRichText: true),
      findsNothing,
      reason: 'a hidden row is being reported as a broken expression',
    );
  });
}
