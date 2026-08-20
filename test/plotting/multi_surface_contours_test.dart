import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Contours belong to every surface on the axes.
///
/// The renderer read `function` — the cell's first line — so a plot holding two
/// surfaces drew contours on one and left the other bare, with nothing to say
/// anything was missing.
void main() {
  const Size canvas = Size(340, 340);
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression fn(String t, int row) {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: t),
    ]);
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isSurface, isTrue, reason: '$t is not a height surface');
    return e..seriesIndex = row;
  }

  Future<int> ink({required int surfaces, required bool contours}) async {
    final curves = <PlotExpression>[
      fn('x^2+y', 0),
      if (surfaces > 1) fn('x^2+y^2', 1),
    ];
    final painter = Plot3DPainter(
      function: curves.first,
      functions: curves,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 4,
      rangeY: 4,
      rangeZ: 30,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: contours,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(340, 340);
    final ByteData data = (await image.toByteData())!;

    int n = 0;
    for (int i = 0; i < 340 * 340; i++) {
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

  testWidgets('a second surface gets contours too', (tester) async {
    await tester.runAsync(() async {
      final int oneOff = await ink(surfaces: 1, contours: false);
      final int oneOn = await ink(surfaces: 1, contours: true);
      final int twoOff = await ink(surfaces: 2, contours: false);
      final int twoOn = await ink(surfaces: 2, contours: true);

      final int addedForOne = oneOn - oneOff;
      final int addedForTwo = twoOn - twoOff;
      expect(
        addedForOne,
        greaterThan(0),
        reason: 'contours drew nothing even on one surface',
      );
      // Two surfaces must gain more contour ink than one, comparing the gain
      // rather than the totals so the surfaces themselves stay out of it.
      //
      // The direction is what carries the meaning. The upper surface hides part
      // of the lower one's contours, so a renderer that contours only the first
      // curve gains *less* from two surfaces than from one: measured, the bug
      // scores 511 against 635 for a single surface, while contouring both
      // scores 711. Passing needs the second surface's own contours, not a
      // generous threshold.
      expect(
        addedForTwo,
        greaterThan(addedForOne),
        reason:
            'turning contours on added $addedForTwo with two surfaces against '
            '$addedForOne with one — the second surface got none',
      );
    });
  });

  Future<int> ink2D({required int surfaces, required bool contours}) async {
    final curves = <PlotExpression>[
      fn('x^2+y', 0),
      if (surfaces > 1) fn('x^2+y^2', 1),
    ];
    final painter = Plot2DPainter(
      function: curves.first,
      functions: curves,
      xMin: -4,
      xMax: 4,
      yMin: -4,
      yMax: 4,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: contours,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(340, 340);
    final ByteData data = (await image.toByteData())!;

    int n = 0;
    for (int i = 0; i < 340 * 340; i++) {
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

  testWidgets('a second surface gets contours in 2D too', (tester) async {
    await tester.runAsync(() async {
      final int oneAdded =
          await ink2D(surfaces: 1, contours: true) -
          await ink2D(surfaces: 1, contours: false);
      final int twoAdded =
          await ink2D(surfaces: 2, contours: true) -
          await ink2D(surfaces: 2, contours: false);

      expect(oneAdded, greaterThan(0), reason: 'contours drew nothing in 2D');
      // Nothing occludes anything here, so the second surface's contours are
      // simply extra ink and the gain should be clearly larger.
      expect(
        twoAdded,
        greaterThan(oneAdded * 1.5),
        reason:
            'contours added $twoAdded with two surfaces against $oneAdded '
            'with one — the second surface got none',
      );
    });
  });
}
