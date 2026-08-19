import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A cell's plots are numbered in the order they are written, and a sweep is
/// one of them.
///
/// The sweep took `seriesColor(0)` unconditionally, so on a cell that already
/// had a curve it arrived wearing that curve's colour and the two could not be
/// told apart. Its place in the cycle comes from how many plots precede it.
///
/// The same list is what lets several fields be drawn at once: each gets its
/// own arrows and its own ramp, because two fields sharing the full rainbow put
/// every magnitude in both.
void main() {
  const Size canvas = Size(240, 240);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  List<MathNode> sweep(String fx, String fy) => <MathNode>[
    LiteralNode(text: fx),
    UnitVectorNode('x'),
    LiteralNode(text: '+$fy'),
    UnitVectorNode('y'),
  ];

  VectorFieldParser parsed(List<MathNode> nodes) {
    final VectorFieldParser? f = VectorFieldParser.fromNodes(nodes);
    expect(f, isNotNull, reason: 'not read as a vector line');
    expect(f!.error, isNull, reason: f.error);
    return f;
  }

  Future<Set<int>> render({
    required List<PlotExpression> curves,
    required List<VectorFieldParser> fields,
    required int seriesBase,
  }) async {
    final painter = Plot2DPainter(
      function: curves.isEmpty ? PlotExpression.invalid : curves.first,
      functions: curves,
      vectorParser: fields.isEmpty ? null : fields.first,
      vectorFields: fields,
      vectorSeriesBase: seriesBase,
      fieldType: fields.isEmpty ? FieldType.scalar : FieldType.vector,
      xMin: -2,
      xMax: 2,
      yMin: -2,
      yMax: 2,
      plotMode: PlotMode.function,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
      uRange: (min: -1.0, max: 1.0),
      vRange: defaultParameterRange,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    final ui.Image image = await recorder.endRecording().toImage(240, 240);
    final ByteData data = (await image.toByteData())!;

    // Every strongly coloured pixel, as packed RGB. Colour identity is the
    // whole question here, so the pixels are collected rather than counted.
    final Set<int> seen = <int>{};
    // Below the colorbar. It runs across the top and is still painted with the
    // full rainbow whatever the arrows use, so including it would report jet's
    // colours as drawn no matter what — which is exactly the mistake that let
    // a shared-ramp mutation pass unnoticed here.
    const int colorbarRows = 48;
    for (int i = colorbarRows * 240; i < 240 * 240; i++) {
      final int o = i * 4;
      if (data.getUint8(o + 3) < 250) continue;
      final int r = data.getUint8(o);
      final int g = data.getUint8(o + 1);
      final int b = data.getUint8(o + 2);
      final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
      final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
      if (mx > 70 && mx - mn > 40) seen.add((r << 16) | (g << 8) | b);
    }
    return seen;
  }

  int packed(Color c) =>
      ((c.r * 255).round() << 16) |
      ((c.g * 255).round() << 8) |
      (c.b * 255).round();

  group('a sweep takes its place in the cycle', () {
    test('the first two series colours differ, so the test can tell', () {
      expect(packed(theme.seriesColor(0)), isNot(packed(theme.seriesColor(1))));
    });

    testWidgets('alone, it is the first series', (tester) async {
      await tester.runAsync(() async {
        final Set<int> seen = await render(
          curves: const <PlotExpression>[],
          fields: <VectorFieldParser>[parsed(sweep('u', 'u^2'))],
          seriesBase: 0,
        );
        expect(seen, contains(packed(theme.seriesColor(0))));
      });
    });

    testWidgets('after one curve, it is the second', (tester) async {
      await tester.runAsync(() async {
        final PlotExpression circle = PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'x^2+y^2=1'),
        ]);
        expect(circle.isValid, isTrue, reason: circle.error);

        final Set<int> seen = await render(
          curves: <PlotExpression>[circle],
          fields: <VectorFieldParser>[parsed(sweep('u', 'u^2'))],
          seriesBase: 1,
        );
        expect(
          seen,
          contains(packed(theme.seriesColor(1))),
          reason: 'the sweep did not continue the cycle',
        );
      });
    });
  });

  group('several fields at once', () {
    // Two fields, deliberately different so their arrows do not coincide.
    List<MathNode> fieldA() => sweep('y', '-x');
    List<MathNode> fieldB() => sweep('x', 'y');

    test('both are read as fields, and neither is a sweep', () {
      for (final List<MathNode> nodes in <List<MathNode>>[fieldA(), fieldB()]) {
        final VectorFieldParser f = parsed(nodes);
        expect(
          f.isParametric,
          isFalse,
          reason:
              'these must be arrow fields, or the arrow path is not '
              'what is being measured',
        );
      }
    });

    test('two fields get different ramps, one field keeps the rainbow', () {
      // The property the arrows rely on. `of: 1` is the full rainbow because a
      // lone field has nothing to be confused with.
      expect(surfaceColormap(0, of: 1)(0.5), plotColormap(0.5));
      expect(
        surfaceColormap(0, of: 2)(0.5),
        isNot(surfaceColormap(1, of: 2)(0.5)),
      );
    });

    testWidgets('drawing two draws more than drawing one', (tester) async {
      await tester.runAsync(() async {
        final Set<int> one = await render(
          curves: const <PlotExpression>[],
          fields: <VectorFieldParser>[parsed(fieldA())],
          seriesBase: 0,
        );
        final Set<int> both = await render(
          curves: const <PlotExpression>[],
          fields: <VectorFieldParser>[parsed(fieldA()), parsed(fieldB())],
          seriesBase: 0,
        );

        expect(one, isNotEmpty, reason: 'one field drew no arrows');
        expect(
          both.difference(one),
          isNotEmpty,
          reason: 'the second field added nothing — it was not drawn',
        );

        // And they are on separate ramps, not both on the rainbow. Measured by
        // jet's middle, a saturated green: a lone field uses jet and reaches
        // it, while the blue and amber ramps contain no such colour at all.
        //
        // The obvious check — that two fields draw colours one does not —
        // cannot see this. Two fields differ in their magnitudes as well as
        // their ramps, so it passes just as happily when both share the
        // rainbow, which is how it let exactly that mutation through.
        bool hasJetMiddle(Set<int> seen) {
          final Color mid = plotColormap(0.5);
          return seen.any((int rgb) {
            final int r = (rgb >> 16) & 0xFF;
            final int g = (rgb >> 8) & 0xFF;
            final int b = rgb & 0xFF;
            return (r - mid.r * 255).abs() < 40 &&
                (g - mid.g * 255).abs() < 40 &&
                (b - mid.b * 255).abs() < 40;
          });
        }

        expect(
          hasJetMiddle(one),
          isTrue,
          reason: 'a lone field should keep the full rainbow',
        );
        expect(
          hasJetMiddle(both),
          isFalse,
          reason:
              'two fields are sharing the rainbow, so every magnitude appears '
              'in both and neither can be followed',
        );
      });
    });

    testWidgets('with no explicit list, the single parser still draws', (
      tester,
    ) async {
      // Every caller written before a cell could hold several fields passes
      // only `vectorParser`, and must keep working.
      await tester.runAsync(() async {
        final painter = Plot2DPainter(
          function: PlotExpression.invalid,
          vectorParser: parsed(fieldA()),
          fieldType: FieldType.vector,
          xMin: -2,
          xMax: 2,
          yMin: -2,
          yMax: 2,
          plotMode: PlotMode.function,
          showContour: false,
          surfaceMode: SurfaceMode.none,
          colors: colors,
          plotTheme: theme,
        );
        expect(painter.fieldsToDraw.length, 1);
      });
    });
  });
}
