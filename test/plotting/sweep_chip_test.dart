import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The chips in the corner, and what they are seeded from.
///
/// This is the end of the path the swipe bug ran along: the panel is rebuilt
/// from a saved view, so if it does not read the sweep out of that view, the
/// sweep is gone.
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

  /// `cos(u) x̂ + sin(u) ŷ` — one parameter, so one chip.
  List<MathNode> curve() => <MathNode>[
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  /// Both parameters, so two chips.
  List<MathNode> patch() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+v'),
    UnitVectorNode('y'),
  ];

  Widget host(
    List<MathNode> nodes, {
    PlotViewState view = PlotViewState.initial,
  }) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            width: 360,
            child: InlinePlotPanel(
              expression: 'parametric',
              nodes: nodes,
              initialView: view,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a curve in u shows one chip, at the default range', (
    tester,
  ) async {
    await tester.pumpWidget(host(curve()));
    await tester.pumpAndSettle();

    expect(find.text('u ∈ [0, 1]'), findsOneWidget);
    expect(find.textContaining('v ∈'), findsNothing);
  });

  testWidgets('a surface in u and v shows both', (tester) async {
    await tester.pumpWidget(host(patch()));
    await tester.pumpAndSettle();

    expect(find.text('u ∈ [0, 1]'), findsOneWidget);
    expect(find.text('v ∈ [0, 1]'), findsOneWidget);
  });

  testWidgets('a plain function shows no chips at all', (tester) async {
    await tester.pumpWidget(host(<MathNode>[LiteralNode(text: 'sin(x)')]));
    await tester.pumpAndSettle();

    expect(find.textContaining('∈'), findsNothing);
  });

  testWidgets('a restored view brings its sweep back with it', (tester) async {
    // The swipe case: the panel is rebuilt from what was saved, and the chip
    // has to show what was dialled in rather than the default.
    await tester.pumpWidget(
      host(curve(), view: const PlotViewState(uMin: 0, uMax: 2 * math.pi)),
    );
    await tester.pumpAndSettle();

    expect(find.text('u ∈ [0, 2π]'), findsOneWidget);
    expect(find.text('u ∈ [0, 1]'), findsNothing);
  });

  testWidgets('and the sweep it brings back is the one that gets plotted', (
    tester,
  ) async {
    // Not just the label: the panel has to hand the restored range down to
    // the screens that build the painters, or the chip would be telling the
    // truth about nothing.
    await tester.pumpWidget(
      host(curve(), view: const PlotViewState(uMin: 1, uMax: 4)),
    );
    await tester.pumpAndSettle();

    expect(find.text('u ∈ [1, 4]'), findsOneWidget);

    // Both screens are built — they live in a stack, only one visible — so
    // switching to 3D must not lose the sweep either.
    final Plot2DScreen flat = tester.widget(find.byType(Plot2DScreen));
    expect(flat.uRange.min, 1);
    expect(flat.uRange.max, 4);

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.uRange.min, 1);
    expect(solid.uRange.max, 4);
  });
}
