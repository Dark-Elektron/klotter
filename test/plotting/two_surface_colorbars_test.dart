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

/// Two surfaces coloured by value get two scales.
///
/// Each surface is coloured against its own range — sharing one would flatten a
/// shallow surface to a single colour whenever a steeper one is beside it — so
/// one bar cannot label both. The swatch legend this replaced said which ramp
/// belonged to which line but never what any colour meant, which is the whole
/// point of colouring by value.
void main() {
  const Size canvas = Size(360, 420);
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression fn(String text, int row) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: text),
    ]);
    expect(e.isValid, isTrue, reason: e.error);
    return e..seriesIndex = row;
  }

  Future<int> barRows(int surfaces, SurfaceMode mode) async {
    final curves = <PlotExpression>[
      fn('x^2+y^2', 0),
      if (surfaces > 1) fn('20-x^2-y^2', 1),
    ];
    final painter = Plot3DPainter(
      function: curves.first,
      functions: curves,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 25,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: mode,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(360, 420);
    final ByteData data = (await image.toByteData())!;

    // Rows in the top strip that run solid colour across the bar's width.
    int rows = 0;
    for (int y = 0; y < 70; y++) {
      int run = 0;
      for (int x = 240; x < 330; x++) {
        final int o = (y * 360 + x) * 4;
        if (data.getUint8(o + 3) < 250) continue;
        final int r = data.getUint8(o);
        final int g = data.getUint8(o + 1);
        final int b = data.getUint8(o + 2);
        final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
        final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
        if (mx > 55 && mx - mn > 20) run++;
      }
      if (run > 60) rows++;
    }
    return rows;
  }

  testWidgets('two surfaces coloured by value draw two bars', (tester) async {
    await tester.runAsync(() async {
      final int one = await barRows(1, SurfaceMode.magnitude);
      final int two = await barRows(2, SurfaceMode.magnitude);
      expect(one, greaterThan(4), reason: 'one surface drew no scale at all');
      expect(
        two,
        greaterThan(one + 4),
        reason:
            'two surfaces drew $two bar rows against $one for one — the second '
            'surface has no scale of its own',
      );
    });
  });

  testWidgets('solid surfaces draw no scale', (tester) async {
    // Off means one colour, so a bar of numbers would be labelling nothing.
    await tester.runAsync(() async {
      expect(await barRows(2, SurfaceMode.none), lessThan(4));
    });
  });
}
