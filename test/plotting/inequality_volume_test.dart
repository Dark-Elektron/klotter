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
import 'package:klotter/utils/coordinate_system.dart';

/// A 3D inequality bounds a solid, not a shell.
///
/// It cannot be filled: this renderer sorts triangles back to front and has no
/// depth buffer, so there is nothing to render an interior against. What that
/// same back-to-front order *does* give for free is correct alpha blending, so
/// the boundary is drawn see-through and the body reads as having an inside.
void main() {
  const Size canvas = Size(400, 400);

  Future<ByteData> render(WidgetTester tester, String? expr) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final colors = AppColors.fromType(ThemeType.classic);
      final curves = <PlotExpression>[
        if (expr != null)
          PlotExpression.compile(<MathNode>[
            LiteralNode(text: expr),
          ], system: CoordinateSystem.spherical),
      ];
      for (final c in curves) {
        expect(c.isValid, isTrue, reason: c.error);
      }

      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.drawRect(
        Offset.zero & canvas,
        Paint()..color = const Color(0xFF12161C),
      );
      Plot3DPainter(
        function: curves.isEmpty ? PlotExpression.invalid : curves.first,
        functions: curves,
        is3DFunction: true,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 2,
        rangeY: 2,
        rangeZ: 2,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: PlotThemeData.fromColors(colors),
      ).paint(c, canvas);

      final img = await recorder.endRecording().toImage(400, 400);
      pixels = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      img.dispose();
    });
    return pixels;
  }

  /// How far a render moves the background, averaged over a box in the middle
  /// of the shape. An opaque surface replaces what is behind it; a
  /// see-through one lets some of it survive.
  double hiding(ByteData bare, ByteData over) {
    double total = 0;
    int n = 0;
    for (int y = 170; y < 230; y++) {
      for (int x = 170; x < 230; x++) {
        final int o = (y * 400 + x) * 4;
        for (int ch = 0; ch < 3; ch++) {
          total += (bare.getUint8(o + ch) - over.getUint8(o + ch)).abs();
          n++;
        }
      }
    }
    return n == 0 ? 0 : total / n;
  }

  testWidgets('an inequality is drawn see-through, an equation is not', (
    tester,
  ) async {
    final ByteData bare = await render(tester, null);
    final ByteData shell = await render(tester, 'ρ^2=1');
    final ByteData ball = await render(tester, 'ρ^2<1');

    final double shellHides = hiding(bare, shell);
    final double ballHides = hiding(bare, ball);

    expect(shellHides, greaterThan(20), reason: 'the shell should be drawn');
    expect(ballHides, greaterThan(10), reason: 'the ball should be drawn too');
    expect(
      ballHides,
      lessThan(shellHides * 0.8),
      reason:
          'the ball should let the axes and grid behind it through; '
          'shell=$shellHides ball=$ballHides',
    );
  });

  testWidgets('a strict inequality is fainter than a closed one', (
    tester,
  ) async {
    // ρ² < 1 excludes its own boundary, so that boundary is drawn lighter —
    // the counterpart of the dashed edge a strict 2D region gets.
    final ByteData bare = await render(tester, null);
    final double open = hiding(bare, await render(tester, 'ρ^2<1'));
    final double closed = hiding(bare, await render(tester, 'ρ^2≤1'));

    expect(open, lessThan(closed), reason: 'open=$open closed=$closed');
  });
}
