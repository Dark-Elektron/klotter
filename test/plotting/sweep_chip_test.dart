import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/models/enums.dart';
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

  testWidgets('a parametric plot in 3D arrives coloured by magnitude', (
    tester,
  ) async {
    // Its default shading reads the shape but says nothing about the
    // numbers, and where the curve runs far from the origin is what a
    // parametric plot is nearly always being looked at for.
    //
    // In 3D specifically. Both screens are mounted at once, so this used to
    // read the 3D screen while the panel sat in 2D and was really asserting a
    // single default for both — which is what put a surface under a 2D sweep.
    await tester.pumpWidget(
      host(curve(), view: PlotViewState.initial.copyWith(show3D: true)),
    );
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.magnitude);
  });

  testWidgets('the same plot in 2D arrives with no colouring', (tester) async {
    // There is no surface to shade in 2D: a sweep is a curve across the plane.
    await tester.pumpWidget(host(curve()));
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.none);
  });

  testWidgets('a plain function is not forced into a colour mode', (
    tester,
  ) async {
    // The default only applies to sweeps; an ordinary curve is left alone.
    await tester.pumpWidget(host(<MathNode>[LiteralNode(text: 'sin(x)')]));
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.none);
  });

  testWidgets('but a colouring the user turned off stays off', (tester) async {
    // "Default" means on first plot only. Swiping away and back rebuilds the
    // panel from the saved view, and re-applying the default there is not a
    // default — it silently undoes having turned the colours off.
    await tester.pumpWidget(
      host(curve(), view: PlotViewState(surfaceMode: SurfaceMode.none.index)),
    );
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.none);
  });

  testWidgets('and one they picked comes back as they left it', (tester) async {
    await tester.pumpWidget(
      host(curve(), view: PlotViewState(surfaceMode: SurfaceMode.z.index)),
    );
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.z);
  });

  testWidgets('a view that was never touched still gets the default', (
    tester,
  ) async {
    // The other half: null means the user has not chosen, so the plot is new
    // and the default applies.
    expect(PlotViewState.initial.surfaceMode, isNull);
    await tester.pumpWidget(
      host(curve(), view: PlotViewState.initial.copyWith(show3D: true)),
    );
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.magnitude);
  });

  testWidgets('a complex plot arrives coloured by argument', (tester) async {
    // What the 2D view of the same function shows without being asked. Left
    // solid, a complex surface is a green shape with nothing on it but the
    // lighting — its height alone says almost nothing.
    await tester.pumpWidget(host(<MathNode>[LiteralNode(text: 'x+yi')]));
    await tester.pumpAndSettle();

    final Plot3DScreen solid = tester.widget(find.byType(Plot3DScreen));
    expect(solid.surfaceMode, SurfaceMode.z);
  });
}
