import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// What a parametric surface's colours stand for.
///
/// With no mode chosen the mesh is shaded by its own geometry in the series
/// colour; choosing one hands the colours over to the value ramp.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const ParameterRange sweep = (min: -2.0, max: 2.0);

  /// A saddle: `u x̂ + v ŷ + u·v ẑ`. Its height runs from -4 to 4, so a mode
  /// reading any one component has a real range to colour over.
  List<MathNode> saddle() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+v'),
    UnitVectorNode('y'),
    LiteralNode(text: '+u*v'),
    UnitVectorNode('z'),
  ];

  Future<ui.Image> render(SurfaceMode mode) async {
    final nodes = saddle();
    final expr = PlotExpression.compile(nodes);
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      vectorParser: VectorFieldParser.fromNodes(nodes),
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: 5,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.vector,
      showContour: false,
      surfaceMode: mode,
      colors: colors,
      plotTheme: theme,
      uRange: sweep,
      vRange: sweep,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(320, 320);
  }

  double distance(Color a, Color b) =>
      (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

  /// How many pixels of [image] sit near [want].
  int near(ByteData data, int pixels, Color want, {double within = 0.25}) {
    int n = 0;
    for (int i = 0; i < pixels; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) < 200) continue;
      final Color c = Color.fromARGB(
        255,
        data.getUint8(o),
        data.getUint8(o + 1),
        data.getUint8(o + 2),
      );
      if (distance(c, want) < within) n++;
    }
    return n;
  }

  testWidgets('colouring by height puts both ends of the ramp on the mesh', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await render(SurfaceMode.z);
      final data = (await image.toByteData())!;
      const int pixels = 320 * 320;

      // The saddle rises and falls, so its highest and lowest corners must
      // carry the ramp's extremes — otherwise the colours are not the value.
      expect(
        near(data, pixels, plotColormapStops.first),
        greaterThan(80),
        reason: 'the low end of the ramp is missing',
      );
      expect(
        near(data, pixels, plotColormapStops.last),
        greaterThan(80),
        reason: 'the high end of the ramp is missing',
      );
    });
  });

  testWidgets('with no mode chosen the ramp is not used at all', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final data = (await (await render(SurfaceMode.none)).toByteData())!;
      const int pixels = 320 * 320;
      // Shaded in the series colour instead. A stray pixel or two of ramp
      // colour could come from the axes, so this allows a handful.
      expect(near(data, pixels, plotColormapStops.last), lessThan(40));
      expect(
        near(data, pixels, theme.seriesColor(0), within: 0.6),
        greaterThan(500),
      );
    });
  });

  testWidgets('x, y and z colour it differently', (tester) async {
    await tester.runAsync(() async {
      // Compared pixel for pixel rather than by histogram. The saddle is
      // symmetric in u and v, so Fx and Fz shade it along different
      // directions — same palette, different picture — and a histogram can
      // miss that entirely by counting the same colours in the wrong places.
      int differenceBetween(ByteData a, ByteData b) {
        int n = 0;
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if ((a.getUint8(o) - b.getUint8(o)).abs() > 24 ||
              (a.getUint8(o + 2) - b.getUint8(o + 2)).abs() > 24) {
            n++;
          }
        }
        return n;
      }

      final byX = (await (await render(SurfaceMode.x)).toByteData())!;
      final byZ = (await (await render(SurfaceMode.z)).toByteData())!;
      final again = (await (await render(SurfaceMode.x)).toByteData())!;

      // The control: the same mode twice is the same picture, so any
      // difference at all is the mode doing something. Measured at 1,881 px
      // between Fx and Fz on a 320x320 canvas.
      expect(differenceBetween(byX, again), 0);
      expect(
        differenceBetween(byX, byZ),
        greaterThan(800),
        reason: 'Fx and Fz look alike',
      );
    });
  });

  testWidgets('the magnitude of a flat patch is its distance from the axis', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final data = (await (await render(SurfaceMode.magnitude)).toByteData())!;
      const int pixels = 320 * 320;
      // The saddle's origin is at distance 0 and its corners much further, so
      // the magnitude spans a real range and both ends must show.
      expect(near(data, pixels, plotColormapStops.first), greaterThan(40));
      expect(near(data, pixels, plotColormapStops.last), greaterThan(40));
    });
  });
}
