import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A parametric plot opens around the figure it traces.
///
/// A sweep has no natural range — u and v decide where the points go and the
/// axes have no say — so at the default ±5 a small figure sat in the middle of
/// an empty box and a large one ran out of it.
void main() {
  late SettingsProvider settings;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });
  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  /// `r·cos(u) x̂ + r·sin(u) ŷ` — a circle of radius r in the plane.
  List<MathNode> circle(String r) => <MathNode>[
    LiteralNode(text: r),
    TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('x'),
    LiteralNode(text: '+$r'),
    TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
    UnitVectorNode('y'),
  ];

  Future<Plot3DScreenState> pump(
    WidgetTester tester,
    List<MathNode> nodes,
  ) async {
    final key = GlobalKey<Plot3DScreenState>();
    final expr = PlotExpression.compile(nodes);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              width: 400,
              child: Plot3DScreen(
                key: key,
                plotTheme: PlotThemeData.fromColors(colors),
                function: expr,
                functions: <PlotExpression>[expr],
                vectorParser: VectorFieldParser.fromNodes(nodes),
                is3DFunction: true,
                toolMode: Tool3DMode.zoom,
                plotMode: PlotMode.function,
                fieldType: FieldType.vector,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                zoomAxis: ZoomAxis.free,
                colors: colors,
                uRange: fullTurn,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return key.currentState!;
  }

  testWidgets('a small figure gets a small box', (tester) async {
    // Radius 0.4. At the old fixed ±5 this was a speck in the middle.
    final state = await pump(tester, circle('0.4'));
    expect(state.xRange, lessThan(1), reason: 'x is ${state.xRange}');
    expect(state.yRange, lessThan(1), reason: 'y is ${state.yRange}');
  });

  testWidgets('and a large one gets a large box', (tester) async {
    // Radius 40, which used to run clean out of the box.
    final state = await pump(tester, circle('40'));
    expect(state.xRange, greaterThan(35), reason: 'x is ${state.xRange}');
    expect(state.xRange, lessThan(60), reason: 'and not far more than needed');
  });

  testWidgets('the figure is inside, with a little room', (tester) async {
    final state = await pump(tester, circle('3'));
    // A margin, but not a wasteful one.
    expect(state.xRange, greaterThan(3));
    expect(state.xRange, lessThan(4));
  });

  testWidgets('a flat figure still gets a box with depth', (tester) async {
    // The circle lies in z = 0, so its z extent is nothing. Framed literally
    // that gives a slot with no thickness and nothing renders.
    final state = await pump(tester, circle('3'));
    expect(state.zRange, greaterThan(0.4), reason: 'z is ${state.zRange}');
  });

  testWidgets('home puts it back around the figure, not back to five', (
    tester,
  ) async {
    final state = await pump(tester, circle('0.4'));
    // Somewhere else entirely, as a pinch would leave it.
    state.restoreView(
      rotX: 1.0,
      rotZ: 1.0,
      pX: 0,
      pY: 0,
      rX: 20,
      rY: 20,
      rZ: 20,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.xRange, 20.0, reason: 'the setup did not take');
    state.resetView();
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.xRange, lessThan(1), reason: 'x is ${state.xRange}');
  });

  testWidgets('an ordinary surface is left to its own fitting', (tester) async {
    // Nothing parametric here, so the height-surface path must still run.
    final state = await pump(tester, <MathNode>[LiteralNode(text: 'x^2+y^2')]);
    expect(state.xRange, 5.0);
    expect(state.yRange, 5.0);
  });
}
