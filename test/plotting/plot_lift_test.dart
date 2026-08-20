import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The 3D box sits in the part of the panel that can be seen.
///
/// The expression rows float over the panel's lower edge, so the panel is
/// taller than the visible area. A box centred in the whole of it sits too low
/// — in 3D the floor plane ends up behind the rows, which is where it was.
///
/// The lift has to reach the picker as well as the painter. They invert the
/// same projection, so a shift applied to one and not the other puts every
/// marker half the covered height away from the surface it claims to be on.
void main() {
  const Size canvas = Size(360, 480);
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression bowl() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2')]);

  /// The vertical centre of everything drawn.
  ///
  /// Not the topmost and bottommost rows: a surface large enough to reach the
  /// canvas edge clamps at both, and then it reports the same span however far
  /// the drawing has moved. The centroid keeps moving.
  Future<double?> drawnCentre(double inset) async {
    final PlotExpression f = bowl();
    expect(f.isValid, isTrue, reason: f.error);
    final painter = Plot3DPainter(
      function: f,
      functions: <PlotExpression>[f],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 30,
      panX: 0,
      panY: 0,
      bottomInset: inset,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(360, 480);
    final ByteData data = (await image.toByteData())!;

    double sum = 0;
    int n = 0;
    for (int y = 0; y < 480; y++) {
      for (int x = 0; x < 360; x++) {
        final int o = (y * 360 + x) * 4;
        if (data.getUint8(o + 3) < 200) continue;
        final int r = data.getUint8(o);
        final int g = data.getUint8(o + 1);
        final int b = data.getUint8(o + 2);
        final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
        final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
        if (mx > 60 && mx - mn > 30) {
          sum += y;
          n++;
        }
      }
    }
    return n == 0 ? null : sum / n;
  }

  testWidgets('an inset lifts the drawing by half of it', (tester) async {
    await tester.runAsync(() async {
      final double? flat = await drawnCentre(0);
      final double? lifted = await drawnCentre(120);
      expect(flat, isNotNull, reason: 'nothing was drawn');
      expect(lifted, isNotNull);

      final double moved = flat! - lifted!;
      expect(
        moved,
        closeTo(60, 8),
        reason:
            'a 120px inset should raise the box by 60; it moved $moved. Too '
            'little and the floor stays behind the rows, too much and the box '
            'climbs off the top.',
      );
    });
  });

  test('the picker is lifted with the painter', () {
    // Same point, same camera, one told about the inset and one not. If they
    // disagree the marker lands where the surface is not.
    PlotCamera cam(double inset) => PlotCamera(
      size: canvas,
      rotationX: 0.6,
      rotationZ: 0.8,
      panX: 0,
      panY: 0,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 12,
      bottomInset: inset,
    );

    final Offset flat = cam(0).project(1, 1, 2);
    final Offset lifted = cam(120).project(1, 1, 2);
    expect(
      flat.dy - lifted.dy,
      closeTo(60, 0.01),
      reason: 'the camera does not apply the same lift the painter does',
    );
    expect(lifted.dx, closeTo(flat.dx, 0.01), reason: 'it moved sideways too');
  });
}
