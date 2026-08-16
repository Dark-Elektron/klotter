import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A complex function in 3D: the vertical axis stands for whichever of the
/// real part, the imaginary part or the modulus is asked for — any of them at
/// once, on the same axes.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  /// `z² + 0i`. The `0i` is what marks it complex; without it the line is a
  /// real function of the third coordinate and nothing here applies.
  PlotExpression squared() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'z^2+0i')]);

  Future<ui.Image> render(
    ComplexView view, {
    SurfaceMode mode = SurfaceMode.none,
  }) async {
    final expr = squared();
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 2,
      rangeY: 2,
      rangeZ: 4,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: mode,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
      complexView: view,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(320, 320);
  }

  Future<int> inked(ui.Image image) async {
    final data = (await image.toByteData())!;
    int n = 0;
    for (int i = 0; i < 320 * 320; i++) {
      if (data.getUint8(i * 4 + 3) > 40) n++;
    }
    return n;
  }

  Future<int> differing(ui.Image a, ui.Image b) async {
    final x = (await a.toByteData())!;
    final y = (await b.toByteData())!;
    int n = 0;
    for (int i = 0; i < 320 * 320; i++) {
      final int o = i * 4;
      if ((x.getUint8(o) - y.getUint8(o)).abs() > 24 ||
          (x.getUint8(o + 2) - y.getUint8(o + 2)).abs() > 24) {
        n++;
      }
    }
    return n;
  }

  const ComplexView none = ComplexView(modulus: false);
  const ComplexView re = ComplexView(modulus: false, real: true);
  const ComplexView im = ComplexView(modulus: false, imaginary: true);
  const ComplexView abs = ComplexView();

  test('the expression under test is complex', () {
    final e = squared();
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isComplex, isTrue);
  });

  testWidgets('with nothing selected there is no surface', (tester) async {
    await tester.runAsync(() async {
      final int bare = await inked(await render(none));
      final int withOne = await inked(await render(abs));
      expect(withOne, greaterThan(bare + 3000), reason: '$withOne vs $bare');
    });
  });

  testWidgets('the three components are three different surfaces', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // For z², Re = x²−y², Im = 2xy and |f| = x²+y² — a saddle, a saddle
      // turned through 45°, and a bowl. No two should look alike.
      final ui.Image a = await render(re);
      final ui.Image b = await render(im);
      final ui.Image c = await render(abs);
      expect(await differing(a, b), greaterThan(2000), reason: 'Re vs Im');
      expect(await differing(b, c), greaterThan(2000), reason: 'Im vs |f|');
      expect(await differing(a, c), greaterThan(2000), reason: 'Re vs |f|');
    });
  });

  testWidgets('two at once draws more than either alone', (tester) async {
    await tester.runAsync(() async {
      final int one = await inked(await render(re));
      final int both = await inked(
        await render(
          const ComplexView(modulus: false, real: true, imaginary: true),
        ),
      );
      expect(both, greaterThan(one), reason: '$both vs $one');
    });
  });

  testWidgets('the colouring is a separate choice from the height', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Same surface, different colouring: |f| shaded solid against |f|
      // coloured by the real part. The shape is identical and the picture is
      // not, which is the point of keeping the two menus apart.
      final ui.Image solid = await render(abs);
      final ui.Image byReal = await render(abs, mode: SurfaceMode.x);
      expect(await differing(solid, byReal), greaterThan(2000));
    });
  });

  group('the selection is remembered', () {
    test('it round-trips through the saved view', () {
      const PlotViewState v = PlotViewState(complexView: 6);
      expect(PlotViewState.fromJson(v.toJson()).complexView, 6);
    });

    test('an untouched view has none, so a default can apply', () {
      expect(PlotViewState.initial.complexView, isNull);
    });

    test('and a view with only this set is not the initial one', () {
      // Otherwise it is treated as untouched and never written — which is
      // exactly how the parameter sweep went missing before.
      const PlotViewState v = PlotViewState(complexView: 4);
      expect(v.isInitial, isFalse);
    });
  });

  group('colouring by argument', () {
    testWidgets('uses the hue wheel, not the ramp', (tester) async {
      await tester.runAsync(() async {
        // Phase wraps, so a ramp would draw a seam across the surface
        // everywhere the argument passes pi. On the wheel it comes round, and
        // z² sweeps the argument twice, so every hue appears on the surface.
        final data =
            (await (await render(abs, mode: SurfaceMode.z)).toByteData())!;
        final Set<int> sectors = <int>{};
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          final HSVColor c = HSVColor.fromColor(
            Color.fromARGB(
              255,
              data.getUint8(o),
              data.getUint8(o + 1),
              data.getUint8(o + 2),
            ),
          );
          if (c.saturation < 0.3 || c.value < 0.2) continue;
          sectors.add((c.hue / 30).floor() % 12);
        }
        expect(sectors.length, greaterThan(9), reason: '${sectors.length}');
      });
    });

    testWidgets('and is a different picture from colouring by modulus', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final byArg = await render(abs, mode: SurfaceMode.z);
        final byMod = await render(abs, mode: SurfaceMode.magnitude);
        expect(await differing(byArg, byMod), greaterThan(3000));
      });
    });
  });

  testWidgets('the modulus surface carries the hue, not one flat colour', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // The report this was written for: |f| came out solid green with only
      // the lighting varying across it. Coloured by argument it carries the
      // same wheel the 2D view shows.
      final data =
          (await (await render(abs, mode: SurfaceMode.z)).toByteData())!;
      final Set<int> sectors = <int>{};
      int coloured = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) < 200) continue;
        final HSVColor c = HSVColor.fromColor(
          Color.fromARGB(
            255,
            data.getUint8(o),
            data.getUint8(o + 1),
            data.getUint8(o + 2),
          ),
        );
        if (c.saturation < 0.3 || c.value < 0.2) continue;
        coloured++;
        sectors.add((c.hue / 30).floor() % 12);
      }
      expect(coloured, greaterThan(5000), reason: 'only $coloured px coloured');
      // A solid surface lands in one or two sectors however it is lit.
      expect(sectors.length, greaterThan(8), reason: '${sectors.length}');
    });
  });
}
