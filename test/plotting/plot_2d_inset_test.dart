import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A flat plot keeps clear of the expression rows, as the 3D box does.
///
/// The rows float over the plot, so the panel is taller than the part you can
/// see. The 2D mapping used the whole panel height, so adding rows pushed the
/// curve underneath them; the 3D box already shrank to what was left.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int side = 240;

  Future<int> lowestInkRow(double inset) async {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x'),
    ]);
    final painter = Plot2DPainter(
      function: e,
      functions: <PlotExpression>[e],
      bottomInset: inset,
      xMin: -5,
      xMax: 5,
      yMin: -5,
      yMax: 5,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(240, 240));
    final ui.Image image = await recorder.endRecording().toImage(side, side);
    final ByteData data = (await image.toByteData())!;

    int lowest = 0;
    for (int y = 0; y < side; y++) {
      for (int x = 0; x < side; x++) {
        final int o = (y * side + x) * 4;
        if (data.getUint8(o + 3) > 200 &&
            [
                  data.getUint8(o),
                  data.getUint8(o + 1),
                  data.getUint8(o + 2),
                ].reduce((a, c) => a > c ? a : c) >
                60) {
          if (y > lowest) lowest = y;
        }
      }
    }
    return lowest;
  }

  testWidgets('rows below push the drawing up', (tester) async {
    await tester.runAsync(() async {
      final int noRows = await lowestInkRow(0);
      final int withRows = await lowestInkRow(80);

      expect(noRows, greaterThan(0), reason: 'nothing was drawn at all');
      expect(
        withRows,
        lessThan(noRows - 40),
        reason:
            'the plot still reaches row $withRows of $side with 80px of rows '
            'over it — it is being drawn underneath them',
      );
    });
  });
}
