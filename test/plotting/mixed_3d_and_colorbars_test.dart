import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The rest of the cell, in 3D — and a scale per ramp.
///
/// In 3D a sweep took an early branch that drew height surfaces and nothing
/// else. Equations are contoured rather than sampled, so they have a renderer
/// of their own, and only the scalar branch ever called it: a cell holding a
/// sweep and a circle compiled both, framed both, and drew the sweep alone.
///
/// The colorbar had the matching problem in 2D. Two fields draw on two ramps,
/// and one bar can only be right about one of them — it showed the rainbow
/// while the arrows were blue and amber.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  List<MathNode> sweepNodes() => <MathNode>[
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+u^2'),
    UnitVectorNode('y'),
  ];

  PlotExpression circle() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2=1')]);

  group('3D draws the whole cell', () {
    const Size canvas = Size(360, 360);

    /// Coloured pixels, so the axes and floor do not count.
    Future<int> ink({required bool withCircle}) async {
      final PlotExpression c = circle();
      expect(c.isValid, isTrue, reason: c.error);
      expect(c.isLevelSet, isTrue, reason: 'this must take the level-set path');

      final VectorFieldParser? sweep = VectorFieldParser.fromNodes(
        sweepNodes(),
      );
      expect(sweep?.isParametric, isTrue);

      final painter = Plot3DPainter(
        function: withCircle ? c : PlotExpression.invalid,
        functions: withCircle ? <PlotExpression>[c] : const <PlotExpression>[],
        vectorParser: sweep,
        vectorFields: <VectorFieldParser>[sweep!],
        is3DFunction: true,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 2,
        rangeY: 2,
        rangeZ: 2,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.vector,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: theme,
        uRange: (min: -1.0, max: 1.0),
        vRange: defaultParameterRange,
      );

      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(360, 360);
      final ByteData data = (await image.toByteData())!;

      int n = 0;
      for (int i = 0; i < 360 * 360; i++) {
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

    testWidgets('a level set beside a sweep is drawn too', (tester) async {
      await tester.runAsync(() async {
        final int sweepOnly = await ink(withCircle: false);
        final int both = await ink(withCircle: true);

        expect(sweepOnly, greaterThan(0), reason: 'the sweep drew nothing');
        expect(
          both,
          greaterThan(sweepOnly),
          reason:
              'adding a circle to a sweep drew $both against $sweepOnly for '
              'the sweep alone — the circle was never drawn',
        );
      });
    });
  });

  group('several fields in 3D', () {
    // Two arrow fields, deliberately different so their arrows do not coincide.
    VectorFieldParser field(String fx, String fy) =>
        VectorFieldParser.fromNodes(<MathNode>[
          LiteralNode(text: fx),
          UnitVectorNode('x'),
          LiteralNode(text: '+$fy'),
          UnitVectorNode('y'),
        ])!;

    Future<({int ink, int barRows})> render(int count) async {
      const Size canvas = Size(320, 320);
      final List<VectorFieldParser> fields = <VectorFieldParser>[
        field('y', '-x'),
        if (count > 1) field('x', 'y'),
      ];
      for (final VectorFieldParser f in fields) {
        expect(f.isParametric, isFalse, reason: 'these must be arrow fields');
      }

      final painter = Plot3DPainter(
        function: PlotExpression.invalid,
        vectorParser: fields.first,
        vectorFields: fields,
        is3DFunction: false,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 2,
        rangeY: 2,
        rangeZ: 2,
        panX: 0,
        panY: 0,
        // Arrows, not the magnitude field. `PlotMode.field` routes to a
        // different renderer — the shaded dot field — which still draws one
        // field only, so aiming there measures nothing about this change.
        plotMode: PlotMode.function,
        fieldType: FieldType.vector,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: theme,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(320, 320);
      final ByteData data = (await image.toByteData())!;

      bool coloured(int o, {int sat = 30}) {
        if (data.getUint8(o + 3) < 200) return false;
        final int r = data.getUint8(o);
        final int g = data.getUint8(o + 1);
        final int b = data.getUint8(o + 2);
        final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
        final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
        return mx > 60 && mx - mn > sat;
      }

      int ink = 0;
      // Below the bars, so the arrows are counted and the scales are not.
      for (int y = 60; y < 320; y++) {
        for (int x = 0; x < 320; x++) {
          if (coloured((y * 320 + x) * 4)) ink++;
        }
      }

      int barRows = 0;
      for (int y = 0; y < 60; y++) {
        int run = 0;
        for (int x = 220; x < 300; x++) {
          if (coloured((y * 320 + x) * 4, sat: 25)) run++;
        }
        if (run > 60) barRows++;
      }
      return (ink: ink, barRows: barRows);
    }

    testWidgets('a second field brings its own arrows and its own scale', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final one = await render(1);
        final two = await render(2);

        expect(one.ink, greaterThan(0), reason: 'one field drew no arrows');
        expect(
          two.ink,
          greaterThan(one.ink),
          reason:
              'two fields drew ${two.ink} arrow pixels against ${one.ink} for '
              'one — the second field was not drawn',
        );
        expect(one.barRows, greaterThan(4), reason: 'no scale was drawn');
        expect(
          two.barRows,
          greaterThan(one.barRows + 4),
          reason:
              'two fields drew ${two.barRows} bar rows against ${one.barRows} '
              'for one — the second field has no scale of its own',
        );
      });
    });
  });

  group('a scale per ramp', () {
    test('the stops match the ramp they describe', () {
      // The bar is a gradient over stops while the arrows sample a function,
      // so the two are separate code paths over the same ramp and could
      // disagree. They must not.
      for (final int of in <int>[1, 2, 3]) {
        for (int i = 0; i < of; i++) {
          final List<Color> stops = surfaceRampStops(i, of: of);
          expect(stops.first, surfaceColormap(i, of: of)(0));
          expect(stops.last, surfaceColormap(i, of: of)(1));
        }
      }
    });

    test('a lone field keeps the rainbow, two fields do not share', () {
      expect(surfaceRampStops(0, of: 1), plotColormapStops);
      expect(surfaceRampStops(0, of: 2), isNot(surfaceRampStops(1, of: 2)));
    });

    testWidgets('two fields draw two bars', (tester) async {
      await tester.runAsync(() async {
        const Size canvas = Size(300, 300);

        Future<int> barRows(int fieldCount) async {
          final List<VectorFieldParser> fields = <VectorFieldParser>[
            VectorFieldParser.fromNodes(<MathNode>[
              LiteralNode(text: 'y'),
              UnitVectorNode('x'),
              LiteralNode(text: '-x'),
              UnitVectorNode('y'),
            ])!,
            if (fieldCount > 1)
              VectorFieldParser.fromNodes(<MathNode>[
                LiteralNode(text: 'x'),
                UnitVectorNode('x'),
                LiteralNode(text: '+y'),
                UnitVectorNode('y'),
              ])!,
          ];

          final painter = Plot2DPainter(
            function: PlotExpression.invalid,
            vectorParser: fields.first,
            vectorFields: fields,
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
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), canvas);
          final ui.Image image = await recorder.endRecording().toImage(
            300,
            300,
          );
          final ByteData data = (await image.toByteData())!;

          // Rows in the top strip that are a solid run of colour across the
          // bar's width. A bar is 12 px tall, so one bar and two are far apart.
          int rows = 0;
          for (int y = 0; y < 60; y++) {
            int run = 0;
            for (int x = 200; x < 280; x++) {
              final int o = (y * 300 + x) * 4;
              if (data.getUint8(o + 3) < 250) continue;
              final int r = data.getUint8(o);
              final int g = data.getUint8(o + 1);
              final int b = data.getUint8(o + 2);
              final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
              final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
              if (mx > 60 && mx - mn > 25) run++;
            }
            if (run > 60) rows++;
          }
          return rows;
        }

        final int one = await barRows(1);
        final int two = await barRows(2);

        expect(one, greaterThan(4), reason: 'no colorbar was drawn at all');
        expect(
          two,
          greaterThan(one + 4),
          reason:
              'two fields drew $two bar rows against $one for one field — '
              'the second field has no scale of its own',
        );
      });
    });
  });
}
