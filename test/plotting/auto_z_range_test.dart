import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The box has to be tall enough to hold the surface it is drawn around.
///
/// The height was measured on its own 7x7 grid, coarse enough to step over
/// whatever the surface actually does. sin(r)/r² over ±24 sampled at multiples
/// of 8 misses the spike at the origin entirely and reports 0.02, so the box
/// came out a hundred times too short and the surface was clipped flat.
void main() {
  Future<Plot3DScreenState> pump(
    WidgetTester tester,
    List<MathNode> nodes, {
    double range = 24,
  }) async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    final colors = AppColors.fromType(ThemeType.classic);
    final key = GlobalKey<Plot3DScreenState>();
    final curve = PlotExpression.compile(nodes);
    expect(curve.isValid, isTrue, reason: curve.error);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: Plot3DScreen(
                key: key,
                function: curve,
                functions: <PlotExpression>[curve],
                is3DFunction: true,
                toolMode: Tool3DMode.zoom,
                plotMode: PlotMode.function,
                fieldType: FieldType.scalar,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                zoomAxis: ZoomAxis.free,
                colors: colors,
                plotTheme: PlotThemeData.fromColors(colors),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final state = key.currentState!;
    state.restoreView(
      rotX: 0.6,
      rotZ: 0.8,
      pX: 0,
      pY: 0,
      rX: range,
      rY: range,
      rZ: state.zRange,
    );
    state.autoScaleForTest();
    await tester.pump(const Duration(milliseconds: 300));
    return state;
  }

  testWidgets('a peak between the old sample points is not missed', (
    tester,
  ) async {
    // sinc: sin(√(x²+y²)) / √(x²+y²), which peaks at 1 at the origin
    // and decays outward. The old 7x7 grid never sampled near the middle, so
    // over ±24 it saw only the ripples and built a box a fraction of the
    // height the surface needs.
    final state = await pump(tester, <MathNode>[
      LiteralNode(text: '('),
      TrigNode(
        function: 'sin',
        argument: <MathNode>[LiteralNode(text: '√(x^2+y^2)')],
      ),
      LiteralNode(text: ')/√(x^2+y^2)'),
    ]);

    expect(
      state.zRange,
      greaterThan(0.6),
      reason: 'the peak is 1; got ${state.zRange}',
    );
    expect(
      state.zRange,
      lessThan(2.5),
      reason: 'and the box should not balloon past it',
    );
  });

  testWidgets('an ordinary surface still gets a snug box', (tester) async {
    // sin(x) never exceeds 1, so the box should stay close to it rather than
    // ballooning.
    final state = await pump(tester, <MathNode>[
      TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'x')]),
    ], range: 6);

    expect(state.zRange, greaterThan(0.5));
    expect(state.zRange, lessThan(3), reason: 'got ${state.zRange}');
  });
}
