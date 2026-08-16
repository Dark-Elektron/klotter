import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Turning the colouring off on an ordinary height surface.
///
/// The menu had offered "Off" all along and the painter ignored it, so a
/// surface was always coloured by its own height — which the shape already
/// shows.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  /// `x·y`, a saddle. Written as a literal the engine can actually read:
  /// `sin(x)+cos(y)` typed this way compiles to "unknown variable sin, cos",
  /// draws nothing, and makes every mode look identical — which is how an
  /// earlier version of this test cleared a change that was never running.
  PlotExpression saddle() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x*y')]);

  /// A sphere: an implicit surface, where every point satisfies the same
  /// equation and so the colouring can only ever come from position.
  PlotExpression sphere() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2+z^2=9')]);

  Future<ui.Image> render(
    SurfaceMode mode, {
    int surfaces = 1,
    PlotExpression? of,
  }) async {
    final expr = of ?? saddle();
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[for (int i = 0; i < surfaces; i++) expr],
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
      plotTheme: PlotThemeData.fromColors(colors),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(320, 320);
  }

  /// How many distinct hues the picture uses.
  ///
  /// A surface coloured by value runs through a ramp, so it has many. One
  /// coloured solid and shaded has a single hue at many brightnesses, so it
  /// has few — the difference the mode makes, whatever the ramp happens to be.
  Future<int> hueCount(ui.Image image) async {
    final data = (await image.toByteData())!;
    final Set<int> hues = <int>{};
    for (int i = 0; i < 320 * 320; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) < 200) continue;
      final HSVColor hsv = HSVColor.fromColor(
        Color.fromARGB(
          255,
          data.getUint8(o),
          data.getUint8(o + 1),
          data.getUint8(o + 2),
        ),
      );
      // Grey has no hue worth counting — that is the box and the grid.
      if (hsv.saturation < 0.25 || hsv.value < 0.15) continue;
      hues.add((hsv.hue / 20).floor());
    }
    return hues.length;
  }

  test('the expression under test actually plots', () {
    // The guard the earlier version needed: everything below compares two
    // renders, and two renders of nothing are identical.
    final e = saddle();
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isSurface, isTrue);
  });

  testWidgets('turning it off changes what is drawn', (tester) async {
    await tester.runAsync(() async {
      final a = (await (await render(SurfaceMode.magnitude)).toByteData())!;
      final b = (await (await render(SurfaceMode.none)).toByteData())!;
      int n = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final int o = i * 4;
        if ((a.getUint8(o) - b.getUint8(o)).abs() > 24 ||
            (a.getUint8(o + 2) - b.getUint8(o + 2)).abs() > 24) {
          n++;
        }
      }
      expect(n, greaterThan(3000), reason: 'only $n px differ');
    });
  });

  testWidgets('off uses far fewer hues than by value', (tester) async {
    await tester.runAsync(() async {
      // Compared rather than counted against a threshold: the three axes are
      // themselves red, green and blue, so a picture is never down to one hue
      // however solid the surface is.
      final int byValue = await hueCount(await render(SurfaceMode.magnitude));
      final int off = await hueCount(await render(SurfaceMode.none));
      // Measured at 17 against 13. Not down to one, because a solid surface
      // still has the axes and the shading's own tint around it, and the hue
      // buckets are coarse.
      expect(
        off,
        lessThan(byValue - 2),
        reason: 'by value $byValue hues, off $off',
      );
    });
  });

  testWidgets('but still shaded, not a flat silhouette', (tester) async {
    await tester.runAsync(() async {
      final data = (await (await render(SurfaceMode.none)).toByteData())!;
      final Set<int> tones = <int>{};
      int opaque = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) > 200) {
          opaque++;
          tones.add(data.getUint8(o) ~/ 8);
        }
      }
      expect(opaque, greaterThan(10000), reason: 'only $opaque px drawn');
      // The cells face different ways, so one colour is many brightnesses.
      expect(tones.length, greaterThan(4), reason: '${tones.length} tones');
    });
  });

  testWidgets('a solid surface takes its colour from the series palette', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // The first surface is the palette's first colour whether or not it has
      // company. It used to be the accent when alone, so adding a second plot
      // recoloured the first from yellow to blue.
      final theme = PlotThemeData.fromColors(colors);
      final Color first = theme.seriesColor(0);

      final data = (await (await render(SurfaceMode.none)).toByteData())!;
      int matching = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) < 200) continue;
        // Shaded, so the colour is the series hue at some brightness.
        final HSVColor hsv = HSVColor.fromColor(
          Color.fromARGB(
            255,
            data.getUint8(o),
            data.getUint8(o + 1),
            data.getUint8(o + 2),
          ),
        );
        if (hsv.saturation < 0.25) continue;
        final double d = (hsv.hue - HSVColor.fromColor(first).hue).abs();
        if (d < 25 || d > 335) matching++;
      }
      expect(matching, greaterThan(8000), reason: 'only $matching px match');
    });
  });

  group('an implicit surface', () {
    test('is a level set, and plots', () {
      final e = sphere();
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isLevelSet, isTrue);
    });

    testWidgets('turning it off changes what is drawn', (tester) async {
      await tester.runAsync(() async {
        final a =
            (await (await render(
              SurfaceMode.magnitude,
              of: sphere(),
            )).toByteData())!;
        final b =
            (await (await render(
              SurfaceMode.none,
              of: sphere(),
            )).toByteData())!;
        int n = 0;
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if ((a.getUint8(o) - b.getUint8(o)).abs() > 24 ||
              (a.getUint8(o + 2) - b.getUint8(o + 2)).abs() > 24) {
            n++;
          }
        }
        // The mesh carries its colours and is cached, so this also proves the
        // mode reaches the cache key — without that the second render would
        // reuse the first's triangles, colours and all.
        expect(n, greaterThan(2000), reason: 'only $n px differ');
      });
    });

    testWidgets('off is the series palette, as a height surface is', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Counting hues does not transfer here: a sphere spans only part of
        // the z ramp, so the coloured version already uses few. What matters
        // is that the solid one is the palette colour every other plot uses.
        final Color first = PlotThemeData.fromColors(colors).seriesColor(0);
        final double want = HSVColor.fromColor(first).hue;

        final data =
            (await (await render(
              SurfaceMode.none,
              of: sphere(),
            )).toByteData())!;
        int matching = 0;
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          final HSVColor hsv = HSVColor.fromColor(
            Color.fromARGB(
              255,
              data.getUint8(o),
              data.getUint8(o + 1),
              data.getUint8(o + 2),
            ),
          );
          if (hsv.saturation < 0.25) continue;
          final double d = (hsv.hue - want).abs();
          if (d < 25 || d > 335) matching++;
        }
        expect(matching, greaterThan(2000), reason: 'only $matching px match');
      });
    });
  });
}
