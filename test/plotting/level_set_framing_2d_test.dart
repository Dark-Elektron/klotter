import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Home frames an implicit curve in 2D, as it does a surface in 3D.
///
/// The flat view fits its window by sampling `evaluate(x, 0, 0)` — the height
/// of the curve above the axis. An implicit curve has no such height: for
/// x²+y²=1 that expression is x²-1, so the fit asked for y from -1 to 24 over
/// ±5 and pushed the unit circle into the bottom corner of an empty window.
void main() {
  late SettingsProvider settings;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });
  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  Future<Plot2DScreenState> pump(
    WidgetTester tester,
    List<String> lines,
  ) async {
    final key = GlobalKey<Plot2DScreenState>();
    final List<PlotExpression> curves = <PlotExpression>[];
    for (int i = 0; i < lines.length; i++) {
      final PlotExpression e = PlotExpression.compile(<MathNode>[
        LiteralNode(text: lines[i]),
      ]);
      expect(e.isValid, isTrue, reason: '${lines[i]}: ${e.error}');
      curves.add(e..seriesIndex = i);
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: Plot2DScreen(
                key: key,
                function: curves.first,
                functions: curves,
                // Exactly as the panel decides it: any line mentioning y
                // makes the cell 3D, implicit curves included. Hard-coding
                // false here drove a path the app never takes, and the fix
                // these tests were written for was skipped in the real one.
                is3DFunction: curves.any(
                  (PlotExpression e) => e.usesY || e.isImplicitSurface,
                ),
                plotMode: PlotMode.function,
                fieldType: FieldType.scalar,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                colors: colors,
                plotTheme: PlotThemeData.fromColors(colors),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final Plot2DScreenState state = key.currentState!;
    state.resetView();
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  testWidgets('a unit circle is framed around itself', (tester) async {
    final state = await pump(tester, <String>['x^2+y^2=1']);

    // The circle reaches 1 in each direction, so the window must hold it...
    expect(state.xMax, greaterThanOrEqualTo(1), reason: 'xMax ${state.xMax}');
    expect(state.yMax, greaterThanOrEqualTo(1), reason: 'yMax ${state.yMax}');
    expect(state.xMin, lessThanOrEqualTo(-1), reason: 'xMin ${state.xMin}');
    expect(state.yMin, lessThanOrEqualTo(-1), reason: 'yMin ${state.yMin}');
    // ...without being the ±5 default it used to keep.
    expect(state.xMax, lessThan(3), reason: 'xMax ${state.xMax}: not framed');
    expect(state.yMax, lessThan(3), reason: 'yMax ${state.yMax}: not framed');

    // And centred, which the old value-based fit was not: it put the circle
    // at the bottom of a window running to 24.
    expect(state.yMin + state.yMax, closeTo(0, 0.5));
  });

  testWidgets('a bigger circle gets a bigger window', (tester) async {
    final small = await pump(tester, <String>['x^2+y^2=1']);
    final double smallX = small.xMax;
    final big = await pump(tester, <String>['x^2+y^2=16']);

    expect(big.xMax, greaterThan(smallX * 2), reason: '$smallX → ${big.xMax}');
    expect(big.xMax, greaterThanOrEqualTo(4), reason: 'radius 4 must fit');
  });

  testWidgets('a plain curve in the same cell is not clipped', (tester) async {
    // Both kinds at once. Framing the circle alone would crop y to about 1.4
    // and cut off the parabola, which reaches 25 across the default width.
    final state = await pump(tester, <String>['x^2+y^2=1', 'x^2']);
    expect(
      state.yMax,
      greaterThan(3),
      reason: 'yMax ${state.yMax}: the curve beside the circle was clipped',
    );
    expect(
      state.xMin,
      lessThanOrEqualTo(-1),
      reason: 'xMin ${state.xMin}: the circle fell outside the window',
    );
  });

  testWidgets('a surface in the flat view is left alone', (tester) async {
    // f(x,y) has no curve to frame in 2D — it is drawn as a field — and the
    // sampled fit reads one slice of it, so the window must stay at default.
    final state = await pump(tester, <String>['x^2+y']);
    expect(state.yMin, -5);
    expect(state.yMax, 5);
  });

  testWidgets('an ordinary plot is framed exactly as before', (tester) async {
    // The value fit is the right answer for a curve with a height, and this
    // change must not have disturbed it.
    final state = await pump(tester, <String>['x^2']);
    expect(state.xMin, -5);
    expect(state.xMax, 5);
    expect(state.yMax, closeTo(27.5, 0.01));
  });

  testWidgets('a small circle is framed small', (tester) async {
    // Radius about 0.32. A fixed floor of 1 in the fit meant this asked for
    // 0.56 and got 1, so it looked like no scaling at all — and anything
    // smaller than it genuinely got none.
    final state = await pump(tester, <String>['x^2+y^2=0.1']);
    expect(
      state.xMax,
      greaterThanOrEqualTo(0.32),
      reason: 'xMax ${state.xMax}',
    );
    expect(state.xMax, lessThan(0.8), reason: 'xMax ${state.xMax}: too wide');
    expect(state.yMin + state.yMax, closeTo(0, 0.2), reason: 'not centred');
  });

  testWidgets('a very small circle scales too', (tester) async {
    // Radius 0.1. This is the one the floor stopped dead.
    final state = await pump(tester, <String>['x^2+y^2=0.01']);
    expect(state.xMax, greaterThanOrEqualTo(0.1), reason: 'xMax ${state.xMax}');
    expect(state.xMax, lessThan(0.4), reason: 'xMax ${state.xMax}: too wide');
  });
}
