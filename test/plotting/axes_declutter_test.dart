import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The 3D axes say what they need to and no more: round numbers, a few of
/// them, never under a control or over the colorbar — and none at all when
/// switched off.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const Size canvas = Size(300, 300);

  group('tick values', () {
    test('are round numbers on their multiples, not counted from the edge', () {
      // A ±3.06 box was labelled −2.06, −1.06, 0.94, 1.94, 2.94.
      expect(Plot3DPainter.axisTicksFor(3.06), <double>[-2, 2]);
      expect(Plot3DPainter.axisTicksFor(5), <double>[-4, -2, 2, 4]);
      expect(Plot3DPainter.axisTicksFor(2.2), <double>[-2, -1, 1, 2]);
      expect(Plot3DPainter.axisTicksFor(1.08), <double>[-1, -0.5, 0.5, 1]);
    });

    test('there are never more than four on an axis', () {
      for (final double range in <double>[
        0.003,
        0.7,
        1,
        1.5,
        3.06,
        4,
        7.5,
        10,
        42,
        999,
        123456,
      ]) {
        final List<double> ticks = Plot3DPainter.axisTicksFor(range);
        expect(ticks.length, inInclusiveRange(1, 4), reason: 'range $range');
        for (final double t in ticks) {
          expect(t.abs(), lessThanOrEqualTo(range * (1 + 1e-9)));
        }
      }
    });

    test('an unusable range labels nothing rather than throwing', () {
      expect(Plot3DPainter.axisTicksFor(double.nan), isEmpty);
      expect(Plot3DPainter.axisTicksFor(double.infinity), isEmpty);
      expect(Plot3DPainter.axisTicksFor(0), isEmpty);
    });
  });

  Plot3DPainter painter({
    bool showAxes = true,
    List<Rect> keepOut = const <Rect>[],
    SurfaceMode mode = SurfaceMode.none,
  }) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x^2+y^2+z^2=4'),
    ]);
    return Plot3DPainter(
      function: e,
      functions: <PlotExpression>[e],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 3,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: mode,
      colors: colors,
      plotTheme: theme,
      showAxes: showAxes,
      labelKeepOut: keepOut,
    );
  }

  Future<ByteData> render(Plot3DPainter p) async {
    final recorder = ui.PictureRecorder();
    p.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(
      canvas.width.toInt(),
      canvas.height.toInt(),
    );
    return (await image.toByteData())!;
  }

  int differing(ByteData a, ByteData b) {
    int n = 0;
    for (int i = 0; i < a.lengthInBytes; i += 4) {
      if (a.getUint32(i) != b.getUint32(i)) n++;
    }
    return n;
  }

  testWidgets('switching the axes off removes them and their plane', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final ByteData on = await render(painter());
      final ByteData off = await render(painter(showAxes: false));

      // The x axis is drawn in its own red; nothing else on this plot is.
      int red(ByteData d) {
        int n = 0;
        for (int i = 0; i < d.lengthInBytes; i += 4) {
          final int r = d.getUint8(i);
          final int g = d.getUint8(i + 1);
          final int b = d.getUint8(i + 2);
          if (r > 150 && g < 120 && b < 120) n++;
        }
        return n;
      }

      // The floor grid and its outline are drawn in greys; the sphere is not.
      int grey(ByteData d) {
        int n = 0;
        for (int i = 0; i < d.lengthInBytes; i += 4) {
          final int r = d.getUint8(i);
          final int g = d.getUint8(i + 1);
          final int b = d.getUint8(i + 2);
          if ((r - g).abs() < 14 && (g - b).abs() < 14 && r > 70) n++;
        }
        return n;
      }

      // Blue enough to be the sphere.
      int blue(ByteData d) {
        int n = 0;
        for (int i = 0; i < d.lengthInBytes; i += 4) {
          if (d.getUint8(i + 2) > d.getUint8(i) + 40) n++;
        }
        return n;
      }

      expect(red(on), greaterThan(50), reason: 'no x axis was drawn at all');
      expect(red(off), 0, reason: 'the x axis survived being switched off');
      // The plane the axes stand on goes with them. It used to stay, and cut
      // through the middle of a surface the user had asked to see bare.
      expect(grey(on), greaterThan(200), reason: 'no floor was drawn at all');
      expect(
        grey(off),
        lessThan(grey(on) ~/ 20),
        reason: 'the floor survived the axes being switched off',
      );
      // And the sphere is untouched.
      expect(blue(off), closeTo(blue(on), blue(on) * 0.2));
    });
  });

  testWidgets('no number is drawn where a control covers the plot', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final ByteData free = await render(painter());
      final ByteData covered = await render(
        painter(keepOut: <Rect>[Offset.zero & canvas]),
      );
      final ByteData corner = await render(
        painter(keepOut: <Rect>[const Rect.fromLTWH(0, 0, 1, 1)]),
      );
      // Covering everything takes the numbers away — and only them: the axis
      // lines, which are not annotations, are still drawn.
      expect(differing(free, covered), greaterThan(0));
      // Covering a corner nothing is drawn in changes nothing.
      expect(differing(free, corner), 0);
    });
  });

  testWidgets('a number behind a surface is hidden by it', (tester) async {
    // Looking straight down +y, a plane at y = −3 is nearer than everything
    // the axes draw, and one at y = +3 is behind all of it. The numbers used
    // to be painted over the finished scene, so they showed through the near
    // plane as if it were glass.
    Plot3DPainter facing(String plane, {bool labels = true}) {
      final PlotExpression e = PlotExpression.compile(<MathNode>[
        LiteralNode(text: plane),
      ]);
      return Plot3DPainter(
        function: e,
        functions: <PlotExpression>[e],
        is3DFunction: true,
        rotationX: 0,
        rotationZ: 0,
        rangeX: 4,
        // Not 4: the y axis points at the camera here, and a tick on the box's
        // front face is in front of any plane inside the box — correctly
        // visible, but not what this measures. At 3.9 the y ticks are ±2.
        rangeY: 3.9,
        rangeZ: 4,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: theme,
        // Keeping the numbers out everywhere leaves everything else as it was,
        // so the difference is the numbers alone.
        labelKeepOut: labels ? const <Rect>[] : <Rect>[Offset.zero & canvas],
      );
    }

    await tester.runAsync(() async {
      // Counted inside the plane only. It spans the box, so the axis names —
      // which sit just past the box — and the numbers on its very edge are
      // beside the plane rather than behind it, and rightly stay visible.
      const Rect inside = Rect.fromLTRB(80, 170, 220, 295);
      Future<int> numbersSeen(String plane) async {
        final ByteData a = await render(facing(plane));
        final ByteData b = await render(facing(plane, labels: false));
        int n = 0;
        for (int y = inside.top.toInt(); y < inside.bottom; y++) {
          for (int x = inside.left.toInt(); x < inside.right; x++) {
            final int o = (y * canvas.width.toInt() + x) * 4;
            if (a.getUint32(o) != b.getUint32(o)) n++;
          }
        }
        return n;
      }

      final int behindThePlane = await numbersSeen('y=-3');
      final int inFrontOfIt = await numbersSeen('y=3');
      expect(inFrontOfIt, greaterThan(100), reason: 'no numbers were drawn');
      expect(
        behindThePlane,
        lessThan(inFrontOfIt * 0.25),
        reason:
            '$behindThePlane pixels of numbers showed through a plane in '
            'front of them, against $inFrontOfIt with nothing in the way',
      );
    });
  });

  testWidgets('the colorbar keeps clear of the screen edge', (tester) async {
    // A phone's display is rounded at the corner the bar sits in, and the
    // last number was cut by the glass at ten pixels from the edge.
    await tester.runAsync(() async {
      final ByteData d = await render(painter(mode: SurfaceMode.magnitude));
      int drawn = 0;
      for (int y = 0; y < 50; y++) {
        for (int x = canvas.width.toInt() - 14; x < canvas.width; x++) {
          if (d.getUint8((y * canvas.width.toInt() + x) * 4 + 3) > 0) drawn++;
        }
      }
      expect(drawn, 0, reason: 'something was drawn in the last 14 px');
    });
  });

  group('the axes switch', () {
    test('is saved with the view and on unless turned off', () {
      expect(PlotViewState.initial.showAxes, isTrue);
      final PlotViewState off = PlotViewState.initial.copyWith(showAxes: false);
      expect(off.isInitial, isFalse);
      expect(PlotViewState.fromJson(off.toJson()).showAxes, isFalse);
      // Saved before the switch existed: those plots all had their axes.
      expect(
        PlotViewState.fromJson(<String, dynamic>{'show3D': true}).showAxes,
        isTrue,
      );
    });

    testWidgets('sits in the toolbar and turns the axes off and on', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      final GlobalKey<InlinePlotPanelState> key =
          GlobalKey<InlinePlotPanelState>();
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 420,
                child: InlinePlotPanel(
                  key: key,
                  expression: 'x^2+y^2',
                  nodes: <MathNode>[LiteralNode(text: 'x^2+y^2')],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final Finder toggle = find.byKey(const ValueKey<String>('axes-toggle'));
      expect(toggle, findsOneWidget);
      expect(key.currentState!.currentView().showAxes, isTrue);

      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(key.currentState!.currentView().showAxes, isFalse);

      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(key.currentState!.currentView().showAxes, isTrue);
    });
  });

  test('the plot repaints when only the axes or the covered places change', () {
    final Plot3DPainter base = painter();
    expect(painter(showAxes: false).shouldRepaint(base), isTrue);
    expect(
      painter(
        keepOut: <Rect>[const Rect.fromLTWH(0, 200, 300, 100)],
      ).shouldRepaint(base),
      isTrue,
    );
  });
}
