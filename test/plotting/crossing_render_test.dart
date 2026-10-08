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

/// Where two surfaces cross, they meet along an edge, not a sawtooth.
///
/// Triangles are painted far to near by the depths of their centres, so one
/// straddling a crossing was in front on one side of it and behind on the
/// other, and drawn whole one way or the other: a tooth for every course of
/// a wall all down the crossing. The walls of a rose and a spiral showed it
/// plainest, so they are what this draws.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int width = 600, height = 900;
  const ({double min, double max}) turn = (min: 0, max: 6.283185307179586);

  testWidgets('a rose and a spiral meet in a clean edge', (tester) async {
    await tester.runAsync(() async {
      final List<PlotExpression> walls = <PlotExpression>[
        PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'r='),
          TrigNode(
            function: 'sin',
            argument: <MathNode>[LiteralNode(text: '2θ')],
          ),
          LiteralNode(),
        ], thetaRange: turn)..seriesIndex = 0,
        PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'r=θ/5'),
        ], thetaRange: turn)..seriesIndex = 1,
      ];
      final painter = Plot3DPainter(
        function: walls.first,
        functions: walls,
        is3DFunction: false,
        rotationX: 0.75,
        rotationZ: 0.35,
        rangeX: 1.4,
        rangeY: 1.4,
        rangeZ: 1.4,
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
      painter.paint(
        Canvas(recorder),
        Size(width.toDouble(), height.toDouble()),
      );
      final ui.Image image = await recorder.endRecording().toImage(
        width,
        height,
      );
      final ByteData data = (await image.toByteData())!;

      // Told by hue, which shading and fog leave alone: the rose blue, about
      // 215°, and the spiral pink, about 350°.
      int wallAt(int x, int y) {
        final int p = (y * width + x) * 4;
        final HSVColor c = HSVColor.fromColor(
          Color.fromARGB(
            255,
            data.getUint8(p),
            data.getUint8(p + 1),
            data.getUint8(p + 2),
          ),
        );
        if (c.saturation < 0.25 || c.value < 0.15) return 0;
        if (c.hue > 195 && c.hue < 235) return 1;
        if (c.hue > 335 || c.hue < 10) return 2;
        return 0;
      }

      // Where blue gives way to pink along each row, and the place that
      // happens most: the edge where the spiral comes through the rose.
      final List<List<int>> switches = <List<int>>[];
      final List<int> histogram = List<int>.filled(width, 0);
      for (int y = 0; y < height; y++) {
        final List<int> row = <int>[];
        int last = 0;
        for (int x = 0; x < width; x++) {
          final int k = wallAt(x, y);
          if (k == 0) continue;
          if (last == 1 && k == 2) {
            row.add(x);
            histogram[x]++;
          }
          last = k;
        }
        switches.add(row);
      }
      int edge = 0;
      for (int x = 1; x < width; x++) {
        if (histogram[x] > histogram[edge]) edge = x;
      }

      // Followed down the picture row by row. A straight edge moves a pixel
      // at a time, leaning as perspective leans it; a tooth jumps.
      int rows = 0, jumps = 0;
      int? at;
      for (final List<int> row in switches) {
        if (row.isEmpty) continue;
        final int near = at ?? edge;
        int best = row.first;
        for (final int x in row) {
          if ((x - near).abs() < (best - near).abs()) best = x;
        }
        if ((best - near).abs() > 30) continue;
        if (at != null) {
          rows++;
          if ((best - at).abs() > 3) jumps++;
        }
        at = best;
      }
      expect(rows, greaterThan(300), reason: 'the edge was not found');
      // Measured at 8 against 31 before the surfaces were cut.
      expect(
        jumps,
        lessThan(16),
        reason: 'the edge jumped $jumps times in $rows rows',
      );
    });
  });
}
