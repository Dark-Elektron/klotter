import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/view_fit.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A 3D plot whose panel is resizing — the keypad folding away grows it on
/// every frame of the slide — fits its box once the size stops moving, not on
/// every frame.
///
/// Fitting a level surface means probing it for its extent and marching it
/// again at the new range, tens of milliseconds a time. Done per frame, a
/// quarter-second slide became a second or more of stutter.
void main() {
  late SettingsProvider settings;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });
  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  const double width = 400;
  const double startHeight = 500;

  Future<(Plot3DScreenState, ValueNotifier<double>)> pump(
    WidgetTester tester,
    String line,
  ) async {
    final GlobalKey<Plot3DScreenState> key = GlobalKey<Plot3DScreenState>();
    final ValueNotifier<double> height = ValueNotifier<double>(startHeight);
    addTearDown(height.dispose);
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: line),
    ]);
    expect(e.isValid, isTrue, reason: '$line: ${e.error}');
    // One list for every rebuild, as the panel hands over: a new list reads
    // to the screen as a new cell, and a new cell is framed afresh.
    final List<PlotExpression> functions = <PlotExpression>[e];

    tester.view.physicalSize = const Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<double>(
                valueListenable: height,
                builder:
                    (context, h, _) => SizedBox(
                      width: width,
                      height: h,
                      child: Plot3DScreen(
                        key: key,
                        plotTheme: PlotThemeData.fromColors(colors),
                        function: e,
                        functions: functions,
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
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    key.currentState!.resetView();
    await tester.pump(const Duration(milliseconds: 400));
    return (key.currentState!, height);
  }

  Plot3DPainter painterOf(WidgetTester tester) =>
      tester
              .renderObjectList<RenderCustomPaint>(find.byType(CustomPaint))
              .firstWhere((RenderCustomPaint r) => r.painter is Plot3DPainter)
              .painter!
          as Plot3DPainter;

  /// Pixels per unit of z over pixels per unit of x. One is round.
  double roundness(Plot3DScreenState state, Size panel) {
    final ViewFit fit = Plot3DPainter.viewExtentsFor(panel);
    return (fit.vertical / state.zRange) / (fit.planar / state.xRange);
  }

  /// The panel growing by 195 px over fifteen frames, as it does when the
  /// keypad slides away.
  Future<void> slide(WidgetTester tester, ValueNotifier<double> height) async {
    for (int i = 0; i < 15; i++) {
      height.value += 13;
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a sphere holds its box while the panel grows', (tester) async {
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2+z^2=1',
    );
    final double zBefore = state.zRange;
    expect(painterOf(tester).fitSize, isNull);

    await slide(tester, height);

    // Mid-slide: nothing refitted, the box held at the size it was fitted
    // to, and the surface on the cheap path.
    expect(state.zRange, zBefore, reason: 'refitted while still resizing');
    final Plot3DPainter during = painterOf(tester);
    expect(during.fitSize, const Size(width, startHeight));
    expect(during.interacting, isTrue);
  });

  testWidgets('and is refitted, still round, once the panel settles', (
    tester,
  ) async {
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2+z^2=1',
    );
    final double zBefore = state.zRange;

    await slide(tester, height);
    await tester.pump(const Duration(milliseconds: 300));

    final Plot3DPainter after = painterOf(tester);
    expect(after.fitSize, isNull);
    expect(after.interacting, isFalse, reason: 'it should sharpen again');
    expect(
      state.zRange,
      greaterThan(zBefore),
      reason: 'a taller panel shows more of z',
    );
    expect(
      roundness(state, Size(width, height.value)),
      closeTo(1, 0.02),
      reason: 'the sphere should still be a sphere in the taller panel',
    );
  });

  testWidgets('a height surface fills its box as it grows', (tester) async {
    // Nothing refits a height surface on a resize: its box is filled, not
    // proportioned. So it is not held, and stretches with the panel.
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2',
    );
    final double zBefore = state.zRange;

    await slide(tester, height);
    expect(painterOf(tester).fitSize, isNull);
    expect(painterOf(tester).interacting, isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    expect(state.zRange, zBefore);
    expect(painterOf(tester).interacting, isFalse);
  });

  /// Pixels per unit of x in a panel of [panel], at [xRange].
  double perUnitX(Size panel, double xRange) =>
      Plot3DPainter.viewExtentsFor(panel).planar / xRange;

  testWidgets('a restored sphere stays round when the panel grows', (
    tester,
  ) async {
    // A view brought back from storage is a chosen one, so nothing frames it
    // again — and the box used to be left to stretch with the panel, so the
    // sphere a cell was saved with came back an egg once the keypad folded.
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2+z^2=1',
    );
    state.restoreView(
      rotX: 0.6,
      rotZ: 0.8,
      pX: 0,
      pY: 0,
      rX: state.xRange,
      rY: state.yRange,
      rZ: state.zRange,
    );
    const Size start = Size(width, startHeight);
    expect(roundness(state, start), closeTo(1, 0.02));
    final double xBefore = state.xRange;

    await slide(tester, height);
    expect(painterOf(tester).fitSize, start, reason: 'not held mid-slide');
    await tester.pump(const Duration(milliseconds: 300));

    final Size end = Size(width, height.value);
    expect(
      roundness(state, end),
      closeTo(1, 0.02),
      reason: 'the restored sphere came out an egg',
    );
    // Rescaled rather than framed afresh: a unit is drawn the size it was.
    expect(
      perUnitX(end, state.xRange),
      closeTo(perUnitX(start, xBefore), 1e-6),
    );
  });

  testWidgets('a zoomed sphere keeps its zoom when the panel grows', (
    tester,
  ) async {
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2+z^2=1',
    );
    final double fitted = state.xRange;

    // Spread two fingers along a diagonal, so both axes zoom alike.
    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    final TestGesture a = await tester.startGesture(
      centre - const Offset(40, 40),
      pointer: 1,
    );
    final TestGesture b = await tester.startGesture(
      centre + const Offset(40, 40),
      pointer: 2,
    );
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-6, -6));
      await b.moveBy(const Offset(6, 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 300));

    const Size start = Size(width, startHeight);
    final double zoomed = state.xRange;
    expect(zoomed, lessThan(fitted * 0.9), reason: 'the pinch did not zoom');
    expect(
      roundness(state, start),
      closeTo(1, 0.02),
      reason: 'the pinch itself made the sphere an egg',
    );

    await slide(tester, height);
    await tester.pump(const Duration(milliseconds: 300));

    // Not framed afresh, which threw the zoom away: every unit is still drawn
    // the size the pinch left it, and the sphere is still round.
    final Size end = Size(width, height.value);
    expect(perUnitX(end, state.xRange), closeTo(perUnitX(start, zoomed), 1e-6));
    expect(roundness(state, end), closeTo(1, 0.02));
  });

  testWidgets('a typed box is held to the letter', (tester) async {
    final (Plot3DScreenState state, ValueNotifier<double> height) = await pump(
      tester,
      'x^2+y^2+z^2=1',
    );
    state.setBox(xMin: -2, xMax: 2, yMin: -2, yMax: 2, zMin: -3, zMax: 3);
    await tester.pump();

    await slide(tester, height);
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.xRange, 2);
    expect(state.yRange, 2);
    expect(state.zRange, 3);
  });

  testWidgets('a drag is drawn on the coarse grid, and sharpens after', (
    tester,
  ) async {
    // Starting a drag stops any spin, which is what cleared the flag — so a
    // drag was drawn on the fine grid, every frame, for the whole of it.
    final (Plot3DScreenState state, _) = await pump(tester, 'x^2+y^2');
    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));

    final TestGesture g = await tester.startGesture(centre);
    await tester.pump();
    expect(
      painterOf(tester).interacting,
      isFalse,
      reason: 'a finger resting on the plot is not moving it',
    );

    for (int i = 0; i < 6; i++) {
      await g.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(painterOf(tester).interacting, isTrue);

    await g.up();
    await tester.pump();
    // Coarse only while it is still turning on its own.
    expect(painterOf(tester).interacting, state.isSpinning);

    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.isSpinning, isFalse);
    expect(painterOf(tester).interacting, isFalse);
  });
}
