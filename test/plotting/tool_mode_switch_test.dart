import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Getting back out of pan.
///
/// Pan is a toggle and zoom is a menu, so the two are not a pair of radio
/// buttons however much they look like one. Tapping zoom opened the axis menu
/// and left the mode in pan, and only *choosing* an axis switched back — so
/// tapping zoom and dismissing appeared to do nothing at all, which reads as a
/// broken control rather than as a mode that had not changed.
void main() {
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  final GlobalKey<InlinePlotPanelState> key = GlobalKey<InlinePlotPanelState>();

  Future<InlinePlotPanelState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              width: 400,
              child: InlinePlotPanel(
                key: key,
                expression: 'x^2+y^2',
                nodes: <MathNode>[LiteralNode(text: 'x^2+y^2')],
                initialView: PlotViewState.initial.copyWith(show3D: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  testWidgets('opening the zoom menu leaves pan', (tester) async {
    final InlinePlotPanelState panel = await pump(tester);
    expect(panel.toolModeForTest, Tool3DMode.zoom, reason: 'default is zoom');

    await tester.tap(find.byIcon(Icons.pan_tool));
    await tester.pumpAndSettle();
    expect(panel.toolModeForTest, Tool3DMode.pan);

    // A plain tap on zoom, with no menu involved.
    await tester.tap(find.byIcon(Icons.zoom_out_map).first);
    await tester.pumpAndSettle();

    expect(
      panel.toolModeForTest,
      Tool3DMode.zoom,
      reason:
          'the plot is still in pan after pressing zoom, so the control looks '
          'like it did nothing',
    );
  });

  testWidgets('pan is still a toggle', (tester) async {
    // The other way back must keep working.
    final InlinePlotPanelState panel = await pump(tester);
    await tester.tap(find.byIcon(Icons.pan_tool));
    await tester.pumpAndSettle();
    expect(panel.toolModeForTest, Tool3DMode.pan);

    await tester.tap(find.byIcon(Icons.pan_tool));
    await tester.pumpAndSettle();
    expect(panel.toolModeForTest, Tool3DMode.zoom);
  });

  testWidgets('the axis menu is still reachable, by long press', (
    tester,
  ) async {
    // The first attempt at this switched the mode in `onOpened`, which rebuilt
    // the button while its own menu route was being pushed and tore the menu
    // straight back down. The mode changed, so a test that only checked the
    // mode passed — while on screen the control still did nothing.
    final InlinePlotPanelState panel = await pump(tester);
    await tester.tap(find.byIcon(Icons.pan_tool));
    await tester.pumpAndSettle();
    expect(panel.toolModeForTest, Tool3DMode.pan);

    await tester.longPress(find.byIcon(Icons.zoom_out_map).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Free'),
      findsOneWidget,
      reason: 'long press no longer offers the axis menu',
    );

    // And choosing from it still sets the axis and the mode.
    await tester.tap(find.text('Free'));
    await tester.pumpAndSettle();
    expect(panel.toolModeForTest, Tool3DMode.zoom);
  });

  testWidgets('tapping zoom again opens the axis menu', (tester) async {
    // The gap the earlier tests left. Tap only ever switched mode, so once
    // zoom was already the mode the button did nothing you could see, and
    // Free/X/Y/Z was reachable only by a long press nobody would think to
    // try. Both existing tests tapped zoom *from pan*, where switching is the
    // right answer, so neither noticed.
    final InlinePlotPanelState panel = await pump(tester);
    expect(panel.toolModeForTest, Tool3DMode.zoom, reason: 'default is zoom');

    await tester.tap(find.byIcon(Icons.zoom_out_map).first);
    await tester.pumpAndSettle();

    expect(
      find.text('Free'),
      findsOneWidget,
      reason: 'tapping zoom while in zoom mode showed no axis menu',
    );
    for (final String axis in <String>['X', 'Y', 'Z']) {
      expect(find.text(axis), findsOneWidget, reason: '$axis is missing');
    }

    // And it is still a working menu, not just a visible one.
    await tester.tap(find.text('Y'));
    await tester.pumpAndSettle();
    expect(panel.zoomAxisForTest, ZoomAxis.y);
    expect(panel.toolModeForTest, Tool3DMode.zoom);
  });
}
