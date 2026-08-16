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

/// What happens where a surface leaves the box.
///
/// Three behaviours have been tried. Dropping whole cells left a row of teeth
/// the size of the grid — an artefact of where the samples fell rather than
/// anything about the function. Holding the corners at the wall replaced the
/// teeth with a flat lid, so a cone came out with its point cut off square.
/// Cutting each cell at the crossing gives neither.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  /// A cone: z = √(x² + y²), which leaves the top of the box over most of the
  /// floor and so is nearly all boundary.
  PlotExpression cone() => PlotExpression.compile(<MathNode>[
    RootNode(
      isSquareRoot: true,
      radicand: <MathNode>[LiteralNode(text: 'x^2+y^2')],
    ),
  ]);

  Future<ui.Image> render({required double rangeZ}) async {
    final expr = cone();
    final painter = Plot3DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      is3DFunction: true,
      // A side-on tilt. Looking straight down the z axis hides the whole
      // question — a lid and a point have the same outline from above, and a
      // test written that way passed with the clipping switched off.
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: rangeZ,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.magnitude,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(320, 320);
  }

  test('the expression under test plots as a surface', () {
    final e = cone();
    expect(e.isValid, isTrue, reason: e.error);
    expect(e.isSurface, isTrue);
  });

  Future<int> drawn(ui.Image image) async {
    final data = (await image.toByteData())!;
    int n = 0;
    for (int i = 0; i < 320 * 320; i++) {
      if (data.getUint8(i * 4 + 3) > 200) n++;
    }
    return n;
  }

  // NOT TESTED: that the overflow is cut rather than lidded or dropped.
  //
  // Three measurements were tried and none of them separates the three
  // behaviours, so none of them is here — a test that passes whatever the
  // code does is worse than no test, because it reads like cover.
  //
  //   * From directly above, a lid and a point have the same outline.
  //   * Counting ink fails because what overflows leaves the canvas rather
  //     than adding to the count.
  //   * Asking whether anything reaches the top of the frame fails because
  //     the box is fitted to the canvas, so a surface that legitimately
  //     reaches the top of the box is already at the edge of the frame.
  //
  // What would work is reading the geometry rather than the picture: the
  // clipped quads should have no vertex with |z| past rangeZ, and at least
  // one lying exactly on it. That needs _surfaceQuads reachable from a test.

  testWidgets('and a surface that fits is left alone', (tester) async {
    await tester.runAsync(() async {
      // Nothing is cut at rangeZ = 10, so this is the ordinary path. The
      // guard that clipping does not quietly reshape surfaces that never
      // reach a wall.
      expect(await drawn(await render(rangeZ: 10)), greaterThan(15000));
    });
  });

  testWidgets('the cut edge is smooth, not serrated', (tester) async {
    await tester.runAsync(() async {
      // Dropping whole cells left the boundary stepping in and out by a grid
      // cell at a time, so the topmost drawn pixel jumped from column to
      // column. Cutting puts it on a smooth curve.
      final data = (await (await render(rangeZ: 2)).toByteData())!;
      int? previous;
      int jumps = 0;
      int measured = 0;
      for (int x = 60; x < 260; x++) {
        int? top;
        for (int y = 0; y < 320; y++) {
          if (data.getUint8((y * 320 + x) * 4 + 3) > 200) {
            top = y;
            break;
          }
        }
        if (top == null) continue;
        if (previous != null) {
          measured++;
          if ((top - previous).abs() > 8) jumps++;
        }
        previous = top;
      }
      expect(measured, greaterThan(80), reason: 'too few columns to judge');
      expect(
        jumps,
        lessThan(measured ~/ 8),
        reason: '$jumps of $measured columns step by more than eight pixels',
      );
    });
  });
}
