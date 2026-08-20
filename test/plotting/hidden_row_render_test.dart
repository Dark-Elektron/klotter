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

/// A hidden row draws nothing, and costs its neighbours nothing.
///
/// It is not removed from the list — it keeps its place in the colour order, so
/// dropping it would recolour every row below it. That makes "hidden" a flag
/// the draw loops have to honour, in each of the three places 3D partitions its
/// curves into: height surfaces, standing curves and equations.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression fn(String text, int row, {bool hidden = false}) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: text),
    ]);
    expect(e.isValid, isTrue, reason: e.error);
    return e
      ..seriesIndex = row
      ..hidden = hidden;
  }

  Future<int> ink(List<PlotExpression> curves) async {
    final painter = Plot3DPainter(
      function: curves.first,
      functions: curves,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 12,
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
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(320, 320);
    final ByteData data = (await image.toByteData())!;

    int n = 0;
    for (int i = 0; i < 320 * 320; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) < 200) continue;
      final int r = data.getUint8(o);
      final int g = data.getUint8(o + 1);
      final int b = data.getUint8(o + 2);
      final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
      final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
      if (mx > 60 && mx - mn > 30) n++;
    }
    return n;
  }

  testWidgets('hiding a height surface stops it being drawn', (tester) async {
    await tester.runAsync(() async {
      final int both = await ink(<PlotExpression>[
        fn('x^2+y^2', 0),
        fn('9-x^2-y^2', 1),
      ]);
      final int one = await ink(<PlotExpression>[
        fn('x^2+y^2', 0),
        fn('9-x^2-y^2', 1, hidden: true),
      ]);
      expect(both, greaterThan(0), reason: 'nothing was drawn at all');
      expect(
        one,
        lessThan(both),
        reason: 'hiding the second surface changed nothing — it still drew',
      );
    });
  });

  testWidgets('hiding one leaves the other exactly as it was', (tester) async {
    // The point of keeping a hidden row in the list: its neighbour must not
    // move, change colour, or be re-fitted because of it.
    await tester.runAsync(() async {
      final int alone = await ink(<PlotExpression>[fn('x^2+y^2', 0)]);
      final int withHidden = await ink(<PlotExpression>[
        fn('x^2+y^2', 0),
        fn('9-x^2-y^2', 1, hidden: true),
      ]);
      expect(
        withHidden,
        closeTo(alone, alone * 0.02),
        reason:
            'the visible surface drew $withHidden beside a hidden row against '
            '$alone on its own — the hidden row is still affecting it',
      );
    });
  });
}
