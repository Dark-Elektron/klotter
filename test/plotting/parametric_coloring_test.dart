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
      Future<List<int>> tones(SurfaceMode m) async {
        final data = (await (await render(m)).toByteData())!;
        final List<int> hist = List<int>.filled(32, 0);
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) > 200) hist[data.getUint8(o) ~/ 8]++;
        }
        return hist;
      }

      // The saddle is symmetric in u and v, so Fx and Fy shade it along
      // perpendicular directions — same palette, different picture.
      final byX = await tones(SurfaceMode.x);
      final byZ = await tones(SurfaceMode.z);
      int differing = 0;
      for (int i = 0; i < byX.length; i++) {
        if ((byX[i] - byZ[i]).abs() > 200) differing++;
      }
      expect(differing, greaterThan(2), reason: 'Fx and Fz look alike');
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
