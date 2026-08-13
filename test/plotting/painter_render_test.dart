import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// What the painters actually put on the canvas.
///
/// Deliberately pixel assertions rather than golden files. Every plotting bug
/// that reached the device recently was invisible to the unit tests, and a
/// golden diff would have caught them only as "something changed" — the
/// failures were structural: a surface drawn by the wrong method, a surface
/// drawn one pixel wide because world scaling was skipped, a translucent fill,
/// a flat-shaded cell. Coverage, extent and colour variety state those
/// failures directly, and unlike reference images they do not drift with
/// platform font and antialiasing differences.
void main() {
  late AppColors colors;
  late PlotThemeData theme;

  const Size canvas = Size(300, 300);

  PlotExpression fn(String t) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

  setUp(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });

  /// Paint [painter] and report what landed on the canvas.
  /// Region excluding the colorbar, which sits at the left margin and is
  /// drawn whether or not a surface is. Counting it once hid the very bug
  /// these tests exist for: with world scaling removed the sphere collapsed to
  /// a pixel, yet total coverage did not move, because the 15x104 bar
  /// accounted for all of it.
  const Rect plotArea = Rect.fromLTRB(60, 0, 300, 300);

  Future<ByteData> rasterise(WidgetTester tester, CustomPainter painter) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(
        canvas.width.toInt(),
        canvas.height.toInt(),
      );
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return pixels;
  }

  /// Fraction of [plotArea] where two renders disagree.
  ///
  /// Counting non-transparent pixels is useless here: the background and grid
  /// are opaque and cover the canvas, so a surface collapsing to a dot moved
  /// total coverage by nothing. Differencing against the same scene minus the
  /// surface measures the surface itself.
  double differenceIn(ByteData a, ByteData b, Rect area) {
    final int w = canvas.width.toInt();
    int differing = 0;
    int considered = 0;
    for (int y = area.top.toInt(); y < area.bottom.toInt(); y++) {
      for (int x = area.left.toInt(); x < area.right.toInt(); x++) {
        considered++;
        final int o = (y * w + x) * 4;
        for (int c = 0; c < 3; c++) {
          if ((a.getUint8(o + c) - b.getUint8(o + c)).abs() > 8) {
            differing++;
            break;
          }
        }
      }
    }
    return considered == 0 ? 0 : differing / considered;
  }

  Future<({double coverage, Rect bounds, int distinctColours})> render(
    WidgetTester tester,
    CustomPainter painter, {
    Rect? region,
  }) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(
        canvas.width.toInt(),
        canvas.height.toInt(),
      );
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });

    final int w = canvas.width.toInt();
    final int h = canvas.height.toInt();
    final Rect area = region ?? Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    int drawn = 0;
    int considered = 0;
    double minX = w.toDouble();
    double maxX = 0;
    double minY = h.toDouble();
    double maxY = 0;
    final Set<int> distinct = <int>{};

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!area.contains(Offset(x.toDouble(), y.toDouble()))) continue;
        considered++;
        final int o = (y * w + x) * 4;
        if (pixels.getUint8(o + 3) == 0) continue;
        drawn++;
        if (x < minX) minX = x.toDouble();
        if (x > maxX) maxX = x.toDouble();
        if (y < minY) minY = y.toDouble();
        if (y > maxY) maxY = y.toDouble();
        // Quantised so antialiasing does not inflate the count.
        distinct.add(
          ((pixels.getUint8(o) >> 4) << 8) |
              ((pixels.getUint8(o + 1) >> 4) << 4) |
              (pixels.getUint8(o + 2) >> 4),
        );
      }
    }

    return (
      coverage: considered == 0 ? 0.0 : drawn / considered,
      bounds:
          drawn == 0
              ? Rect.zero
              : Rect.fromLTRB(minX, minY, maxX + 1, maxY + 1),
      distinctColours: distinct.length,
    );
  }

  Future<void> prepare(WidgetTester tester) async {
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              colors = AppColors.of(context);
              theme = PlotThemeData.fromColors(colors);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  Plot3DPainter painter3D(PlotExpression f, SurfaceMode mode) => Plot3DPainter(
    function: f,
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
    surfaceMode: mode,
    colors: colors,
    plotTheme: theme,
  );

  Plot2DPainter painter2D(PlotExpression f, SurfaceMode mode) => Plot2DPainter(
    function: f,
    xMin: -5,
    xMax: 5,
    yMin: -5,
    yMax: 5,
    plotMode: PlotMode.function,
    fieldType: FieldType.scalar,
    showContour: false,
    surfaceMode: mode,
    colors: colors,
    plotTheme: theme,
  );

  /// Coverage attributable to the *surface*, by subtracting a paint of the
  /// same scene whose expression cannot be plotted.
  ///
  /// Measuring the whole canvas is not enough: axes, grid and the colorbar
  /// dominate it, so a surface collapsing to a single pixel barely moves the
  /// total. That is exactly how the missing world-scale bug slipped past the
  /// first version of these tests.
  Future<double> surfaceCoverage(
    WidgetTester tester,
    CustomPainter withSurface,
    CustomPainter chromeOnly,
  ) async {
    final a = await rasterise(tester, withSurface);
    final b = await rasterise(tester, chromeOnly);
    return differenceIn(a, b, plotArea);
  }

  group('3D surfaces reach the canvas', () {
    testWidgets('a height surface covers a real area', (tester) async {
      await prepare(tester);
      final only = await surfaceCoverage(
        tester,
        painter3D(fn('xx+yy'), SurfaceMode.magnitude),
        painter3D(fn('q'), SurfaceMode.magnitude),
      );
      // ~0.072 of the plot area. It was ~0.27 while the world box was a fixed
      // 200 logical pixels: on a canvas this size the box projected wider than
      // the canvas, so the surface ran off every edge. A scene that fits shows
      // less of itself, which is the point.
      expect(
        only,
        greaterThan(0.04),
        reason: 'the surface should occupy a real part of the view',
      );
    });

    testWidgets('a level surface is drawn at world scale, not a dot', (
      tester,
    ) async {
      // The sphere once rendered about a pixel wide, because data coordinates
      // were projected without the 200/range world scaling every other surface
      // applies. It was drawing the whole time.
      await prepare(tester);
      final only = await surfaceCoverage(
        tester,
        painter3D(fn('xx+yy+zz=1'), SurfaceMode.none),
        painter3D(fn('q'), SurfaceMode.none),
      );
      // Measured ~0.068 with world scaling, ~0.00006 without — the sphere
      // collapses to a dot, which is exactly how this shipped.
      expect(
        only,
        greaterThan(0.008),
        reason:
            'unscaled, the sphere is about a pixel; at world scale it covers '
            'a real part of the view',
      );
    });

    testWidgets('an open surface still renders', (tester) async {
      await prepare(tester);
      final only = await surfaceCoverage(
        tester,
        painter3D(fn('xx+yy-zz=1'), SurfaceMode.none),
        painter3D(fn('q'), SurfaceMode.none),
      );
      expect(only, greaterThan(0.05));
    });
  });

  group('colour varies with the data', () {
    testWidgets('a height surface is not one flat colour', (tester) async {
      // Catches a collapsed colormap, and the per-cell flat fill that made a
      // 50x50 surface 2,500 solid blocks.
      await prepare(tester);
      final r = await render(
        tester,
        painter3D(fn('xx+yy'), SurfaceMode.magnitude),
      );
      expect(
        r.distinctColours,
        greaterThan(20),
        reason: 'the magnitude ramp should span many colours',
      );
    });

    testWidgets('a 2D heatmap spans the ramp and fills the plot', (
      tester,
    ) async {
      await prepare(tester);
      final r = await render(
        tester,
        painter2D(fn('xy'), SurfaceMode.magnitude),
      );
      expect(r.distinctColours, greaterThan(20));
      expect(r.coverage, greaterThan(0.5));
    });
  });

  group('2D curves reach the canvas', () {
    testWidgets('an explicit curve spans the window', (tester) async {
      await prepare(tester);
      final r = await render(tester, painter2D(fn('2x'), SurfaceMode.none));
      expect(r.coverage, greaterThan(0.01));
      expect(r.bounds.width, greaterThan(200));
    });

    testWidgets('an implicit circle is drawn as a closed curve', (
      tester,
    ) async {
      await prepare(tester);
      final r = await render(
        tester,
        painter2D(fn('xx+yy=4'), SurfaceMode.none),
      );
      expect(r.coverage, greaterThan(0.01));
      // Radius 2 in a [-5,5] window spans 40% of the canvas each way.
      expect(r.bounds.width, greaterThan(80));
      expect(r.bounds.height, greaterThan(80));
    });
  });

  group('nothing is drawn when there is nothing to draw', () {
    testWidgets('an unplottable expression paints less than a valid one', (
      tester,
    ) async {
      await prepare(tester);
      final withCurve = await render(
        tester,
        painter2D(fn('2x'), SurfaceMode.none),
      );
      final invalid = await render(
        tester,
        painter2D(fn('q'), SurfaceMode.none),
      );
      expect(
        invalid.coverage,
        lessThan(withCurve.coverage),
        reason: 'no curve should be drawn for an unplottable expression',
      );
    });
  });
}
