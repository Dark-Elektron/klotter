import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The 3D trace, from the gesture down to the pixels.
///
/// surface_pick_test.dart covers the maths. This covers the wiring, which is
/// where the equivalent 2D bug actually lived: the painter called the wrong
/// function on each curve and the solver was never the problem.
void main() {
  const Size canvas = Size(400, 400);

  late AppColors colors;
  late PlotThemeData theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    colors = AppColors.fromType(ThemeType.classic);
    theme = PlotThemeData.fromColors(colors);
  });

  PlotExpression fn(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  PlotCamera camera() => PlotCamera(
    size: canvas,
    rotationX: 0.6,
    rotationZ: 0.8,
    panX: 0,
    panY: 0,
    rangeX: 5,
    rangeY: 5,
    rangeZ: 5,
  );

  Plot3DPainter painter(List<PlotExpression> curves, {SurfaceHit? trace}) =>
      Plot3DPainter(
        function: curves.first,
        functions: curves,
        is3DFunction: true,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 5,
        rangeY: 5,
        rangeZ: 5,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: theme,
        tracePoint: trace,
      );

  Future<ByteData> rasterise(WidgetTester tester, CustomPainter p) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(400, 400);
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return pixels;
  }

  /// Bounding box of the pixels the marker added, ignoring the readout box in
  /// the top strip.
  Rect changedBounds(ByteData a, ByteData b) {
    double mnx = 1e9, mxx = -1, mny = 1e9, mxy = -1;
    for (int y = 80; y < 400; y++) {
      for (int x = 0; x < 400; x++) {
        final int o = (y * 400 + x) * 4;
        for (int ch = 0; ch < 3; ch++) {
          if ((a.getUint8(o + ch) - b.getUint8(o + ch)).abs() > 20) {
            if (x < mnx) mnx = x.toDouble();
            if (x > mxx) mxx = x.toDouble();
            if (y < mny) mny = y.toDouble();
            if (y > mxy) mxy = y.toDouble();
            break;
          }
        }
      }
    }
    return mxx < 0 ? Rect.zero : Rect.fromLTRB(mnx, mny, mxx, mxy);
  }

  testWidgets('the marker lands where the point projects', (tester) async {
    final PlotCamera c = camera();
    final List<PlotExpression> curves = <PlotExpression>[fn('x+y')];
    const SurfaceHit hit = (x: 1.2, y: -1.4, z: -0.2, curveIndex: 0);

    final ByteData without = await rasterise(tester, painter(curves));
    final ByteData with_ = await rasterise(tester, painter(curves, trace: hit));

    final Rect drawn = changedBounds(without, with_);
    expect(drawn, isNot(Rect.zero), reason: 'no marker was drawn at all');

    final Offset expected = c.project(hit.x, hit.y, hit.z);
    expect(
      (drawn.center - expected).distance,
      lessThan(8),
      reason: 'marker at ${drawn.center}, point projects to $expected',
    );
  });

  testWidgets('no marker without a trace point', (tester) async {
    final List<PlotExpression> curves = <PlotExpression>[fn('x+y')];
    final ByteData a = await rasterise(tester, painter(curves));
    final ByteData b = await rasterise(tester, painter(curves));
    expect(changedBounds(a, b), Rect.zero);
  });

  group('the gesture', () {
    Future<Plot3DScreenState> pump(
      WidgetTester tester,
      String expression,
    ) async {
      final key = GlobalKey<Plot3DScreenState>();
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      final curve = fn(expression);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: canvas.width,
                height: canvas.height,
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
                  plotTheme: theme,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return key.currentState!;
    }

    testWidgets('a long press places a point on the surface', (tester) async {
      final state = await pump(tester, 'x+y');
      expect(state.tracePointForTest, isNull);

      await tester.longPressAt(tester.getCenter(find.byType(Plot3DScreen)));
      await tester.pump(const Duration(milliseconds: 300));

      final SurfaceHit? hit = state.tracePointForTest;
      expect(hit, isNotNull, reason: 'long press should place a marker');
      // On the surface, which is the claim — z = x + y at the point found.
      // Not the origin itself: the box is fitted and centred on what it
      // draws, so the middle of the widget looks a little to one side of it.
      expect(hit!.z, closeTo(hit.x + hit.y, 1e-6));
      // And somewhere near the middle of the box rather than out at an edge.
      // Not tighter than that: where the centre of the widget falls in data
      // terms depends on how the view is placed, and the placement is now a
      // per-screen knob rather than a fixed centring.
      expect(hit.x.abs(), lessThan(3));
      expect(hit.y.abs(), lessThan(3));
    });

    testWidgets('a tap takes it away again', (tester) async {
      final state = await pump(tester, 'x+y');
      await tester.longPressAt(tester.getCenter(find.byType(Plot3DScreen)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.tracePointForTest, isNotNull);

      await tester.tapAt(tester.getCenter(find.byType(Plot3DScreen)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.tracePointForTest, isNull);
    });

    testWidgets('a drag still rotates rather than tracing', (tester) async {
      final state = await pump(tester, 'x+y');
      final double before = state.rotationZ;

      await tester.drag(find.byType(Plot3DScreen), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.rotationZ,
        isNot(closeTo(before, 1e-9)),
        reason: 'dragging must still rotate the plot',
      );
      expect(state.tracePointForTest, isNull);
    });
  });
}
