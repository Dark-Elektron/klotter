import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The plot's controls, with two rows in the plot.
///
/// Reported repro: two surfaces in one plot — `x^2+y` and `x^2+y^2` — and the
/// controls stop acting on a tap. Every earlier test used a single row, where
/// the panel is short and settles at once, so none of them exercised this.
void main() {
  testWidgets('the controls still act with two rows present', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
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
    await tester.pump(const Duration(milliseconds: 800));

    final HomePageState state = key.currentState!;
    state.rowsOf(0).first.controller.setExpression(<MathNode>[
      LiteralNode(text: 'x^2+y'),
    ]);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 400));
    state.rowsOf(0).last.controller.setExpression(<MathNode>[
      LiteralNode(text: 'x^2+y^2'),
    ]);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(state.rowsOf(0), hasLength(2), reason: 'setup failed');

    // The tap has to do its job, not merely not throw.
    await tester.tap(find.text('3D'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(Plot3DScreen),
      findsWidgets,
      reason: 'tapping 3D did nothing with two rows in the plot',
    );

    // And the panel must have stopped moving: a tree still rebuilding every
    // frame drops taps, which is what a tooltip-without-action looks like.
    final double a =
        tester
            .widget<InlinePlotPanel>(find.byType(InlinePlotPanel).first)
            .bottomInset;
    await tester.pump(const Duration(milliseconds: 200));
    final double b =
        tester
            .widget<InlinePlotPanel>(find.byType(InlinePlotPanel).first)
            .bottomInset;
    expect(a, b, reason: 'the row panel is still resizing after settling');
  });
}
