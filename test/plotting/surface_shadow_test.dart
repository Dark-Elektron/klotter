import 'dart:math' as math;
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

/// A surface casts a shadow on the floor.
///
/// The first attempt drew nothing, and the reason is worth keeping: by the time
/// a `Quad` exists its corners have been rotated into camera space, so `p.z` is
/// not height and projecting it onto z = 0 is meaningless. The floor point is
/// now taken while the corner is still a data point. That is the same trap that
/// once coloured a complex surface by its rotated coordinates.
void main() {
  const Size canvas = Size(360, 360);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  PlotExpression bowl() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2')]);

  Future<ByteData> render({required double rangeZ}) async {
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
      rangeZ: rangeZ,
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
    final Canvas c = Canvas(recorder);
    // The painter draws onto transparency — the panel behind it is the
    // widget's job. Without a ground to composite against, a translucent
    // shadow lands as a nearly transparent pixel and reads as nothing.
    c.drawRect(Offset.zero & canvas, Paint()..color = const Color(0xFFEDEDED));
    painter.paint(c, canvas);
    final ui.Image image = await recorder.endRecording().toImage(360, 360);
    return (await image.toByteData())!;
  }

  /// Total ink in the picture.
  ///
  /// Counting dark pixels on the floor was tried and does not work: the floor
  /// already carries grid lines and axes, so that count stays healthy with the
  /// shadow switched off entirely and passed the mutation. Comparing the same
  /// scene against itself with the shadow off is the only reading that
  /// isolates it.
  double totalInk(ByteData data) {
    double sum = 0;
    for (int i = 0; i < 360 * 360; i++) {
      final int o = i * 4;
      sum +=
          255 * 3 -
          (data.getUint8(o) + data.getUint8(o + 1) + data.getUint8(o + 2));
    }
    return sum;
  }

  Future<double> inkAddedByShadow({required double rangeZ}) async {
    Plot3DPainter.shadowAlpha = 0;
    final double off = totalInk(await render(rangeZ: rangeZ));
    Plot3DPainter.shadowAlpha = 0.22;
    final double on = totalInk(await render(rangeZ: rangeZ));
    return on - off;
  }

  tearDown(() => Plot3DPainter.shadowAlpha = 0.22);

  testWidgets('turning the shadow on darkens the picture', (tester) async {
    await tester.runAsync(() async {
      final double added = await inkAddedByShadow(rangeZ: 10);
      expect(
        added,
        greaterThan(0),
        reason: 'the shadow changed nothing — none was drawn',
      );
    });
  });

  testWidgets('the shadow follows the surface', (tester) async {
    // The discriminating half. A fixed dark patch would pass the test above
    // and fail this one, because a real shadow is a function of the geometry
    // it falls from — reframing the box moves the surface relative to the
    // floor, so the shadow it casts has to change too.
    await tester.runAsync(() async {
      final double near = await inkAddedByShadow(rangeZ: 10);
      final double far = await inkAddedByShadow(rangeZ: 25);
      expect(near, greaterThan(0));
      expect(far, greaterThan(0));
      expect(
        near,
        isNot(closeTo(far, near * 0.02)),
        reason:
            'the shadow adds $near either way — it does not depend on where '
            'the surface is, so it is not a shadow of it',
      );
    });
  });

  testWidgets('the shadow slides with height, not just with footprint', (
    tester,
  ) async {
    // The property that was actually broken, and the one the tests above
    // cannot see: `x^2+y^2` and `x^2+y^2+6` have the same footprint on the
    // floor and differ only in how high they sit. A shadow that carries the
    // corner's height slides between them; one that merely drops the corner
    // straight down does not, and lands identically for both.
    //
    // Dropping the height was mutated in and passed every other test here.
    await tester.runAsync(() async {
      Future<double> addedFor(String expr) async {
        final PlotExpression f = PlotExpression.compile(<MathNode>[
          LiteralNode(text: expr),
        ]);
        expect(f.isValid, isTrue, reason: f.error);

        Future<double> ink(double alpha) async {
          Plot3DPainter.shadowAlpha = alpha;
          final painter = Plot3DPainter(
            function: f,
            functions: <PlotExpression>[f],
            is3DFunction: true,
            rotationX: 0.6,
            rotationZ: 0.8,
            rangeX: 3,
            rangeY: 3,
            // Roomy enough that both surfaces fit whole, so the difference is
            // height and not clipping.
            rangeZ: 40,
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
          final Canvas c = Canvas(recorder);
          c.drawRect(
            Offset.zero & canvas,
            Paint()..color = const Color(0xFFEDEDED),
          );
          painter.paint(c, canvas);
          final ui.Image image = await recorder.endRecording().toImage(
            360,
            360,
          );
          return totalInk((await image.toByteData())!);
        }

        final double off = await ink(0);
        final double on = await ink(0.22);
        return on - off;
      }

      final double low = await addedFor('x^2+y^2');
      final double high = await addedFor('x^2+y^2+6');
      expect(low, greaterThan(0));
      expect(
        low,
        isNot(closeTo(high, low * 0.02)),
        reason:
            'lifting the surface 6 units changed the shadow by less than 2% '
            '($low against $high) — the corner is being dropped straight '
            'down, so its height is not reaching the shadow',
      );
    });
  });

  group('the lamp stays in the room', () {
    test('the light is off-axis', () {
      // Straight overhead is the one direction that cannot read: the shadow
      // lands exactly beneath the surface and is never seen.
      final s = Plot3DPainter.shadowSlide(0.6, 0.8);
      expect(s.dx.abs() + s.dy.abs(), greaterThan(0.1));
    });

    test('turning the plot moves the light through the plot frame', () {
      // The bug this replaced. The slide was a pair of constants in the
      // plot's own coordinates, so the lamp was nailed to the data: turn the
      // plot and the shadow turned rigidly with it, as though painted on the
      // surface. A lamp fixed in the room has to arrive at different plot
      // coordinates as the plot turns beneath it.
      final a = Plot3DPainter.shadowSlide(0.6, 0.0);
      final b = Plot3DPainter.shadowSlide(0.6, 1.2);
      expect(
        (a.dx - b.dx).abs() + (a.dy - b.dy).abs(),
        greaterThan(0.05),
        reason:
            'the slide is the same at both angles, so the light is turning '
            'with the plot instead of staying put',
      );
    });

    test('a half turn mirrors the light, as a fixed lamp must', () {
      // Turning the plot by pi puts the same lamp on the opposite side of it.
      final a = Plot3DPainter.shadowSlide(0.6, 0.0);
      final b = Plot3DPainter.shadowSlide(0.6, math.pi);
      expect(b.dx, closeTo(-a.dx, 1e-9));
      expect(b.dy, closeTo(-a.dy, 1e-9));
    });

    test('the slide stays finite when the light grazes the floor', () {
      // Near-horizontal light casts a shadow to infinity. Whatever the view,
      // the slide has to stay small enough to draw.
      for (double rx = -math.pi; rx <= math.pi; rx += 0.05) {
        final s = Plot3DPainter.shadowSlide(rx, 0.7);
        expect(s.dx.isFinite && s.dy.isFinite, isTrue, reason: 'rx=$rx');
        expect(s.dx.abs() + s.dy.abs(), lessThan(12), reason: 'rx=$rx');
      }
    });
  });
}
