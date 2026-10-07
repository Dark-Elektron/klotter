import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/parameter_range_panel.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The θ chip: what a polar curve or spherical surface is swept over.
///
/// θ is compiled into the lines rather than handed to the painters, so the
/// checks here are on the lines the screens are given, not only on the label.
void main() {
  Future<SettingsProvider> settingsFor({required bool leftHanded}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dark_theme': false,
      'multiplication_sign': '×',
      'walkthrough_completed_v2': true,
      if (leftHanded) 'handedness': 'leftHanded',
    });
    return SettingsProvider.create();
  }

  /// `r = θ`, which is traced, so it has a θ range.
  List<MathNode> spiral() => <MathNode>[LiteralNode(text: 'r=θ')];

  Widget host(
    SettingsProvider settings,
    List<MathNode> nodes, {
    PlotViewState view = PlotViewState.initial,
    String expression = 'polar',
  }) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            width: 360,
            child: InlinePlotPanel(
              // The panel parses again when this changes, not when the
              // nodes do.
              expression: expression,
              nodes: nodes,
              initialView: view,
            ),
          ),
        ),
      ),
    );
  }

  ({double min, double max}) rangeDrawn(WidgetTester tester) {
    final Plot2DScreen flat = tester.widget(find.byType(Plot2DScreen));
    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.functions.single.thetaRange, flat.functions.single.thetaRange);
    return flat.functions.single.thetaRange;
  }

  testWidgets('a polar curve shows its θ range, two turns by default', (
    tester,
  ) async {
    final SettingsProvider settings = await settingsFor(leftHanded: false);
    addTearDown(settings.dispose);
    await tester.pumpWidget(host(settings, spiral()));
    await tester.pumpAndSettle();

    expect(find.text('θ ∈ [-2π, 2π]'), findsOneWidget);
    expect(rangeDrawn(tester), PlotExpression.defaultThetaRange);
  });

  testWidgets('a sampled polar line follows θ too; others have none to set', (
    tester,
  ) async {
    final SettingsProvider settings = await settingsFor(leftHanded: false);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      host(settings, <MathNode>[LiteralNode(text: 'r<θ')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('θ ∈ [-2π, 2π]'), findsOneWidget);

    // A Cartesian line, and a height, which has one value at each point of
    // the plane and so reads θ in its first turn only.
    for (final String line in <String>['x^2+y^2=1', 'rθ']) {
      await tester.pumpWidget(
        host(settings, <MathNode>[LiteralNode(text: line)], expression: line),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('θ ∈'), findsNothing, reason: line);
    }
  });

  testWidgets('a restored view brings its θ range back, and draws with it', (
    tester,
  ) async {
    final SettingsProvider settings = await settingsFor(leftHanded: false);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      host(
        settings,
        spiral(),
        view: const PlotViewState(thetaMin: 0, thetaMax: 2 * math.pi),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('θ ∈ [0, 2π]'), findsOneWidget);
    expect(rangeDrawn(tester), (min: 0.0, max: 2 * math.pi));
  });

  testWidgets('setting it recompiles the lines, and Reset puts back θ\'s own '
      'default', (tester) async {
    final SettingsProvider settings = await settingsFor(leftHanded: false);
    addTearDown(settings.dispose);
    await tester.pumpWidget(host(settings, spiral()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ParameterRangeChip));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.enterText(find.byType(TextField).at(1), '6π');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('θ ∈ [0, 6π]'), findsOneWidget);
    expect(rangeDrawn(tester), (min: 0.0, max: 6 * math.pi));

    await tester.tap(find.byType(ParameterRangeChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    // Not u's unit interval.
    expect(find.text('θ ∈ [-2π, 2π]'), findsOneWidget);
    expect(rangeDrawn(tester), PlotExpression.defaultThetaRange);
  });

  testWidgets('the chip sits by the thumb, mirrored for left hands', (
    tester,
  ) async {
    Future<Rect> chipFor({required bool leftHanded}) async {
      final SettingsProvider settings = await settingsFor(
        leftHanded: leftHanded,
      );
      addTearDown(settings.dispose);
      await tester.pumpWidget(host(settings, spiral()));
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(ParameterRangeChip));
    }

    final Rect right = await chipFor(leftHanded: false);
    expect(right.left, lessThan(40));
    final Rect left = await chipFor(leftHanded: true);
    expect(left.right, greaterThan(360 - 40));
  });
}
