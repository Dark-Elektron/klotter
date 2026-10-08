import 'dart:typed_data';
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

/// An equation's surface and a height surface hide each other by depth.
///
/// The equations were drawn first, as a finished scene of their own, and the
/// heights over them, so a height surface was always in front: a saddle
/// covered a sphere sitting on it, and a polar curve's wall, wherever the two
/// really were. Everything in the box is one scene now.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int width = 400, height = 600;

  final Map<String, PlotExpression> compiled = <String, PlotExpression>{};
  PlotExpression of(String src, int series) => compiled.putIfAbsent(
    '$src#$series',
    () =>
        PlotExpression.compile(<MathNode>[LiteralNode(text: src)])
          ..seriesIndex = series,
  );

  /// Seen from well above, so a surface higher up is nearer the camera.
  Future<ByteData> render(List<PlotExpression> lines) async {
    final painter = Plot3DPainter(
      function: lines.first,
      functions: lines,
      showMesh: false,
      is3DFunction: true,
      rotationX: 1.2,
      rotationZ: 0.3,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 3,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final ui.Image image = await recorder.endRecording().toImage(width, height);
    return (await image.toByteData())!;
  }

  /// Pixels of the sphere's colour: series 4 is violet in the dark theme,
  /// unlike the plane's orange and every axis. Told by hue, which shading
  /// and fog leave alone, rather than by an exact colour.
  int violet(ByteData data) {
    int n = 0;
    for (int p = 0; p < width * height * 4; p += 4) {
      final HSVColor hsv = HSVColor.fromColor(
        Color.fromARGB(
          255,
          data.getUint8(p),
          data.getUint8(p + 1),
          data.getUint8(p + 2),
        ),
      );
      if (hsv.saturation > 0.2 &&
          hsv.value > 0.15 &&
          hsv.hue > 255 &&
          hsv.hue < 300) {
        n++;
      }
    }
    return n;
  }

  testWidgets('a sphere on a surface shows, and one under it does not', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final PlotExpression sphere = of('x^2+y^2+z^2=1', 4);
      final int alone = violet(await render(<PlotExpression>[sphere]));
      expect(alone, greaterThan(1000), reason: 'the sphere drew too little');

      // The plane at z = -2, under the sphere: nothing is in front of it.
      final int onPlane = violet(
        await render(<PlotExpression>[sphere, of('0.01xy-2', 3)]),
      );
      expect(
        onPlane,
        greaterThan(alone * 0.9),
        reason:
            'the plane under the sphere was painted over it: $onPlane '
            'violet pixels against $alone alone',
      );

      // The plane at z = 2, over it: all of it is hidden.
      final int underPlane = violet(
        await render(<PlotExpression>[sphere, of('0.01xy+2', 3)]),
      );
      expect(
        underPlane,
        lessThan(alone * 0.05),
        reason: 'the sphere showed through the plane over it: $underPlane',
      );
    });
  });
}
