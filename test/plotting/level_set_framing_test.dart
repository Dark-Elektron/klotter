import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/models/view_fit.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Home frames an implicit equation around its surface.
///
/// A level set is drawn where `F = 0`, and `F` says nothing about where that
/// is: for the unit sphere over ±5, max|F| is 49, so fitting by value asks for
/// a box fifty times too big. Level sets were therefore left out of the fit
/// altogether and home just went to ±5 — a unit circle sat as a speck in the
/// middle of an empty box.
void main() {
  late SettingsProvider settings;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });
  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  Future<Plot3DScreenState> pump(
    WidgetTester tester,
    List<String> lines, {
    double width = 400,
    double height = 500,
  }) async {
    final key = GlobalKey<Plot3DScreenState>();
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
              height: height,
              width: width,
              child: Plot3DScreen(
                key: key,
                plotTheme: PlotThemeData.fromColors(colors),
                function: curves.first,
                functions: curves,
                is3DFunction: true,
                toolMode: Tool3DMode.zoom,
                plotMode: PlotMode.function,
                fieldType: FieldType.scalar,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                zoomAxis: ZoomAxis.free,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final Plot3DScreenState state = key.currentState!;
    state.resetView();
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  testWidgets('a sphere is framed around itself, not left at the default', (
    tester,
  ) async {
    final state = await pump(tester, <String>['x^2+y^2+z^2=1']);
    // Every axis holds the sphere...
    for (final MapEntry<String, double> axis
        in <String, double>{
          'x': state.xRange,
          'y': state.yRange,
          'z': state.zRange,
        }.entries) {
      expect(
        axis.value,
        greaterThanOrEqualTo(1),
        reason: 'the sphere reaches 1 in ${axis.key}; a smaller box clips it',
      );
    }
    // ...and the axis the fit is snug against sits close around it. Only one
    // of them can: equal aspect leaves the roomier axis deliberately wide, so
    // asking both to be tight would be asking the sphere not to be round.
    expect(
      min(state.xRange, state.zRange),
      lessThan(3),
      reason:
          'x ${state.xRange}, z ${state.zRange}: neither is near the sphere, '
          'so it was not framed',
    );
  });

  testWidgets('a bigger circle gets a bigger box', (tester) async {
    // The measurement has to track the shape, not return a flattering constant.
    final small = await pump(tester, <String>['x^2+y^2=1']);
    final double smallX = small.xRange;
    final big = await pump(tester, <String>['x^2+y^2=9']);

    expect(
      big.xRange,
      greaterThan(smallX * 1.5),
      reason: '$smallX → ${big.xRange}',
    );
    expect(big.xRange, greaterThan(3), reason: 'radius 3 must fit');
  });

  testWidgets('a height surface in the same cell is not clipped', (
    tester,
  ) async {
    // A cell may hold both kinds. Framing the sphere alone would crush z down
    // to about 1 and cut the top off the paraboloid, which reaches 32.
    final state = await pump(tester, <String>['x^2+y^2+z^2=1', 'x^2+y^2']);
    expect(
      state.zRange,
      greaterThan(3),
      reason: 'z is ${state.zRange}: the surface beside the sphere was clipped',
    );
  });

  testWidgets('a small sphere is framed small', (tester) async {
    // Radius about 0.32. The fit floored every axis at 1, so a small shape
    // scaled no further than the floor and looked unscaled.
    //
    // Measured on whichever axis the fit is snug against — the one with the
    // smaller screen budget. Equal aspect leaves the other deliberately wide,
    // and which is which depends on the panel.
    final state = await pump(tester, <String>['x^2+y^2+z^2=0.1']);
    final double snug = min(state.xRange, state.zRange);
    expect(snug, greaterThanOrEqualTo(0.32), reason: 'snug axis $snug');
    expect(snug, lessThan(0.9), reason: 'snug axis $snug: too wide');
  });

  /// How round a sphere is drawn: pixels per unit of z over pixels per unit
  /// of x. One is round.
  double roundness(Plot3DScreenState state, Size panel) {
    final ViewFit fit = Plot3DPainter.viewExtentsFor(panel);
    return (fit.vertical / state.zRange) / (fit.planar / state.xRange);
  }

  testWidgets('a sphere is drawn round, not as an egg', (tester) async {
    // The floor and the z axis have separate screen budgets, so equal ranges
    // still stretch z. A unit of z has to cover the same pixels as a unit of
    // x for the sphere to look like one.
    const Size panel = Size(400, 500);
    final state = await pump(tester, <String>['x^2+y^2+z^2=1']);
    expect(
      roundness(state, panel),
      closeTo(1, 0.02),
      reason:
          'a unit of z covers ${roundness(state, panel)} times the pixels a '
          'unit of x does — the sphere is an egg',
    );
  });

  testWidgets('and stays round in landscape', (tester) async {
    // The budgets change shape with the panel, so the fit has to follow.
    const Size panel = Size(900, 400);
    // The window has to be big enough to give the panel the width it asks
    // for; at the default 800 the widget is squeezed and the fit is measured
    // against a size it never had.
    tester.view.physicalSize = panel;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await pump(
      tester,
      <String>['x^2+y^2+z^2=1'],
      width: panel.width,
      height: panel.height,
    );
    expect(roundness(state, panel), closeTo(1, 0.02));
    // And it is still framed around the sphere rather than opened out.
    expect(state.zRange, greaterThanOrEqualTo(1), reason: '${state.zRange}');
    expect(state.zRange, lessThan(4), reason: '${state.zRange}');
  });

  testWidgets('the tighter dimension is the one that binds', (tester) async {
    // Zooming to extent means the shape fits in *both* budgets, so whichever
    // is smaller decides it and the other is left with room over.
    const Size panel = Size(400, 800);
    tester.view.physicalSize = panel;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await pump(
      tester,
      <String>['x^2+y^2+z^2=1'],
      width: panel.width,
      height: panel.height,
    );
    final ViewFit fit = Plot3DPainter.viewExtentsFor(panel);
    final bool zHasRoom = fit.vertical / fit.planar > 1;
    expect(
      zHasRoom ? state.zRange : state.xRange,
      greaterThan(zHasRoom ? state.xRange : state.zRange),
      reason:
          'the spare budget is ${zHasRoom ? "z" : "the plan"}, so its range '
          'should be the wider one: x ${state.xRange}, z ${state.zRange}',
    );
    // Both hold the sphere either way, which is what zooming to extent means.
    expect(state.xRange, greaterThanOrEqualTo(1));
    expect(state.zRange, greaterThanOrEqualTo(1));
  });
}
