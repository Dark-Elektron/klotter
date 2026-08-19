import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A cell whose lines are not all the same kind of plot.
///
/// `x²+y²=1`, `x²−y²=0.1` and `u x̂ + u² ŷ` are a circle, a hyperbola and a
/// swept parabola — three plots that belong on one set of axes. The cell drew
/// none of them and labelled itself "vector arrows".
///
/// The cause was that the whole cell was handed to the vector parser as one
/// node list. Lines without a unit vector were dropped for not being a
/// component, and the terms of the ones that remained were folded together, so
/// the sweep compiled from a mixture of three equations. Classification is now
/// per line, because that is what a line is: its own plot.
void main() {
  const Size canvas = Size(320, 320);
  final AppColors colors = AppColors.fromType(ThemeType.classic);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  /// The cell from the report, as the editor holds it.
  List<MathNode> mixedCell() => <MathNode>[
    LiteralNode(text: 'x^2+y^2=1'),
    NewlineNode(),
    LiteralNode(text: 'x^2-y^2=0.1'),
    NewlineNode(),
    LiteralNode(text: 'u'),
    UnitVectorNode('x'),
    LiteralNode(text: '+u^2'),
    UnitVectorNode('y'),
  ];

  group('reading the cell', () {
    test('it splits into three lines', () {
      final List<List<MathNode>> lines = PlotExpression.splitLines(mixedCell());
      expect(lines.length, 3, reason: 'the newlines were not honoured');
    });

    test('only the last line is a vector line', () {
      final List<List<MathNode>> lines = PlotExpression.splitLines(mixedCell());
      expect(lines.map(VectorFieldParser.isVectorFieldNodes).toList(), <bool>[
        false,
        false,
        true,
      ]);
    });

    test('the whole cell read at once is a vector line — which was the bug', () {
      // Not an assertion about desired behaviour; it records why asking of the
      // node list as a whole cannot work. One unit vector anywhere makes the
      // entire cell answer yes.
      expect(VectorFieldParser.isVectorFieldNodes(mixedCell()), isTrue);
    });

    test('the sweep compiles on its own', () {
      final List<List<MathNode>> lines = PlotExpression.splitLines(mixedCell());
      final VectorFieldParser? v = VectorFieldParser.fromNodes(lines.last);
      expect(v, isNotNull);
      expect(v!.error, isNull, reason: v.error);
      expect(v.isParametric, isTrue, reason: 'u should make this a sweep');
    });

    test('the level sets compile on their own', () {
      final List<List<MathNode>> lines = PlotExpression.splitLines(mixedCell());
      for (final List<MathNode> line in lines.take(2)) {
        final PlotExpression e = PlotExpression.compile(line);
        expect(e.isValid, isTrue, reason: e.error);
        expect(e.isLevelSet, isTrue);
      }
    });
  });

  group('drawing it', () {
    /// Render the cell, optionally holding back one half, and count the
    /// pixels that are neither background nor grid.
    Future<int> inkFor({
      required bool withCurves,
      required bool withSweep,
    }) async {
      final List<List<MathNode>> lines = PlotExpression.splitLines(mixedCell());
      final List<PlotExpression> curves =
          withCurves
              ? <PlotExpression>[
                for (final List<MathNode> line in lines.take(2))
                  PlotExpression.compile(line),
              ]
              : const <PlotExpression>[];
      final VectorFieldParser? sweep =
          withSweep ? VectorFieldParser.fromNodes(lines.last) : null;

      final painter = Plot2DPainter(
        function: curves.isEmpty ? PlotExpression.invalid : curves.first,
        functions: curves,
        vectorParser: sweep,
        fieldType: sweep == null ? FieldType.scalar : FieldType.vector,
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
      final ui.Image image = await recorder.endRecording().toImage(320, 320);
      final ByteData data = (await image.toByteData())!;

      int ink = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) < 128) continue;
        final int r = data.getUint8(o);
        final int g = data.getUint8(o + 1);
        final int b = data.getUint8(o + 2);
        // The axes are white-ish and the background dark; a curve is coloured.
        final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
        final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
        if (mx > 60 && mx - mn > 30) ink++;
      }
      return ink;
    }

    testWidgets('each half draws something on its own', (tester) async {
      await tester.runAsync(() async {
        expect(
          await inkFor(withCurves: true, withSweep: false),
          greaterThan(50),
          reason: 'the level sets draw nothing even alone',
        );
        expect(
          await inkFor(withCurves: false, withSweep: true),
          greaterThan(20),
          reason: 'the sweep draws nothing even alone',
        );
      });
    });

    testWidgets('together, both are drawn', (tester) async {
      await tester.runAsync(() async {
        final int curvesOnly = await inkFor(withCurves: true, withSweep: false);
        final int sweepOnly = await inkFor(withCurves: false, withSweep: true);
        final int both = await inkFor(withCurves: true, withSweep: true);

        // More than either alone. Not the exact sum — the curves cross the
        // sweep, so some pixels are shared — but a painter that drew only one
        // of the two would land on one of these numbers, and that is what this
        // separates.
        expect(
          both,
          greaterThan(curvesOnly),
          reason:
              'adding a sweep to two level sets drew $both, and the level '
              'sets alone drew $curvesOnly — the sweep replaced them',
        );
        expect(
          both,
          greaterThan(sweepOnly),
          reason:
              'adding two level sets to a sweep drew $both, and the sweep '
              'alone drew $sweepOnly — the level sets were thrown away',
        );
      });
    });
  });
}
