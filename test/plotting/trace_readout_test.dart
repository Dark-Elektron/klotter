import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The trace crosshair answers "what is f(2.3)?" — the most calculator-shaped
/// interaction a plot has. Long-press owns it so it never competes with the
/// single-finger pan.
void main() {
  late SettingsProvider settings;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'dark_theme': false,
      'multiplication_sign': '×',
      'walkthrough_completed_v2': true,
    });
  });

  setUp(() async {
    settings = await SettingsProvider.create();
  });

  tearDown(() => settings.dispose());

  Widget host(String expr, List<MathNode> nodes) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            width: 360,
            child: InlinePlotPanel(expression: expr, nodes: nodes),
          ),
        ),
      ),
    );
  }

  Plot2DScreenState stateOf(WidgetTester tester) =>
      tester.state<Plot2DScreenState>(find.byType(Plot2DScreen));

  testWidgets('no crosshair until asked for', (tester) async {
    await tester.pumpWidget(host('2x', [LiteralNode(text: '2x')]));
    await tester.pumpAndSettle();
    expect(stateOf(tester).traceXForTest, isNull);
  });

  testWidgets('long-press sets the crosshair inside the visible range', (
    tester,
  ) async {
    await tester.pumpWidget(host('2x', [LiteralNode(text: '2x')]));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(Plot2DScreen));
    await tester.pumpAndSettle();

    final s = stateOf(tester);
    expect(s.traceXForTest, isNotNull);
    expect(s.traceXForTest!, inInclusiveRange(s.xMin, s.xMax));
  });

  testWidgets('tapping dismisses the crosshair', (tester) async {
    await tester.pumpWidget(host('2x', [LiteralNode(text: '2x')]));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(Plot2DScreen));
    await tester.pumpAndSettle();
    expect(stateOf(tester).traceXForTest, isNotNull);

    await tester.tap(find.byType(Plot2DScreen));
    await tester.pumpAndSettle();
    expect(stateOf(tester).traceXForTest, isNull);
  });

  testWidgets('the crosshair snaps to a root', (tester) async {
    // xx-4 crosses zero at x = ±2. Long-pressing near one should land on it
    // exactly rather than wherever the finger happened to be.
    await tester.pumpWidget(host('xx-4', [LiteralNode(text: 'xx-4')]));
    await tester.pumpAndSettle();

    final s = stateOf(tester);
    final rect = tester.getRect(find.byType(Plot2DScreen));
    // Convert x = 1.9 (just short of the root at 2) to a screen position.
    final double frac = (1.9 - s.xMin) / (s.xMax - s.xMin);
    await tester.longPressAt(
      Offset(rect.left + rect.width * frac, rect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(
      stateOf(tester).traceXForTest,
      closeTo(2.0, 0.01),
      reason: 'should snap to the root rather than stay at 1.9',
    );
  });

  testWidgets('a point far from any feature does not snap', (tester) async {
    await tester.pumpWidget(host('xx-4', [LiteralNode(text: 'xx-4')]));
    await tester.pumpAndSettle();

    final s = stateOf(tester);
    final rect = tester.getRect(find.byType(Plot2DScreen));
    // x = 1.0 is well away from the roots (±2) and the vertex (0).
    final double frac = (1.0 - s.xMin) / (s.xMax - s.xMin);
    await tester.longPressAt(
      Offset(rect.left + rect.width * frac, rect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(stateOf(tester).traceXForTest, closeTo(1.0, 0.2));
  });

  testWidgets('resetting the view clears a stale crosshair', (tester) async {
    await tester.pumpWidget(host('2x', [LiteralNode(text: '2x')]));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(Plot2DScreen));
    await tester.pumpAndSettle();
    expect(stateOf(tester).traceXForTest, isNotNull);

    stateOf(tester).resetView();
    await tester.pumpAndSettle();
    expect(stateOf(tester).traceXForTest, isNull);
  });
}
