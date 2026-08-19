import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// How a parametric sweep is coloured before anyone asks.
///
/// The default was magnitude everywhere. In 3D that is right — a swept surface
/// left solid is a shape with nothing on it but the lighting. In 2D there is no
/// surface to shade: a sweep there is a curve traced across the plane, and
/// shading it filled the plot with a surface nobody asked for.
///
/// So the default now depends on the dimension. What it must never do is
/// override a choice: the whole point of tracking that the user picked
/// something is that re-parsing and switching dimension both leave it alone.
void main() {
  late SettingsProvider settings;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dark_theme': false,
      'walkthrough_completed_v2': true,
    });
  });

  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  /// `cos(u) x̂ + sin(u) ŷ` — one parameter, so a curve.
  List<MathNode> curve() => <MathNode>[
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  /// `u x̂ + v ŷ + u·v ẑ` — both parameters, so a surface.
  List<MathNode> patch() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+v'),
    UnitVectorNode('y'),
    LiteralNode(text: '+u*v'),
    UnitVectorNode('z'),
  ];

  final GlobalKey<InlinePlotPanelState> panelKey =
      GlobalKey<InlinePlotPanelState>();

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
              key: panelKey,
              expression: 'parametric',
              nodes: nodes,
              initialView: view,
            ),
          ),
        ),
      ),
    );
  }

  Future<InlinePlotPanelState> pump(
    WidgetTester tester,
    List<MathNode> nodes, {
    PlotViewState view = PlotViewState.initial,
  }) async {
    await tester.pumpWidget(host(nodes, view: view));
    await tester.pumpAndSettle();
    return panelKey.currentState!;
  }

  testWidgets('a curve in 2D arrives with no colouring', (tester) async {
    final InlinePlotPanelState panel = await pump(tester, curve());
    final (SurfaceMode mode, bool chosen) = panel.surfaceModeForTest;

    expect(
      mode,
      SurfaceMode.none,
      reason: 'a 2D sweep was shaded like a surface',
    );
    expect(
      chosen,
      isFalse,
      reason:
          'this is a default, not something the user asked for — if it '
          'were recorded as chosen it would then override the 3D default',
    );
  });

  testWidgets('the same curve in 3D still arrives coloured', (tester) async {
    final InlinePlotPanelState panel = await pump(
      tester,
      curve(),
      view: PlotViewState.initial.copyWith(show3D: true),
    );
    expect(panel.surfaceModeForTest.$1, SurfaceMode.magnitude);
  });

  testWidgets('a surface in u and v is unchanged in 3D', (tester) async {
    // The complaint was about 2D. The 3D default is what it was.
    final InlinePlotPanelState panel = await pump(
      tester,
      patch(),
      view: PlotViewState.initial.copyWith(show3D: true),
    );
    expect(panel.surfaceModeForTest.$1, SurfaceMode.magnitude);
  });

  testWidgets('switching to 3D picks the colouring up', (tester) async {
    // Starting in 2D leaves it off; going to 3D is where it becomes worth
    // having, and the user has said nothing either way.
    final InlinePlotPanelState panel = await pump(tester, curve());
    expect(panel.surfaceModeForTest.$1, SurfaceMode.none);

    panel.setShow3DForTest(true);
    await tester.pumpAndSettle();
    expect(
      panel.surfaceModeForTest.$1,
      SurfaceMode.magnitude,
      reason: 'the 2D default followed the plot into 3D',
    );

    panel.setShow3DForTest(false);
    await tester.pumpAndSettle();
    expect(panel.surfaceModeForTest.$1, SurfaceMode.none);
  });

  testWidgets('a saved choice survives the switch', (tester) async {
    // A view carrying a surface mode means the user picked it, so neither
    // dimension's default may touch it. Without this the new per-dimension
    // default would undo turning the colours on in 2D — the same bug the
    // chosen flag was added for, in a new place.
    final InlinePlotPanelState panel = await pump(
      tester,
      curve(),
      view: PlotViewState.initial.copyWith(
        surfaceMode: SurfaceMode.magnitude.index,
      ),
    );
    expect(panel.surfaceModeForTest, (SurfaceMode.magnitude, true));

    panel.setShow3DForTest(true);
    await tester.pumpAndSettle();
    expect(panel.surfaceModeForTest.$1, SurfaceMode.magnitude);

    panel.setShow3DForTest(false);
    await tester.pumpAndSettle();
    expect(
      panel.surfaceModeForTest.$1,
      SurfaceMode.magnitude,
      reason: 'the 2D default overrode a choice the user had made',
    );
  });

  testWidgets('choosing off in 3D is not undone by the 3D default', (
    tester,
  ) async {
    final InlinePlotPanelState panel = await pump(
      tester,
      patch(),
      view: PlotViewState.initial.copyWith(
        show3D: true,
        surfaceMode: SurfaceMode.none.index,
      ),
    );
    expect(panel.surfaceModeForTest, (SurfaceMode.none, true));
  });
}
