import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:ui' as ui;

import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/utils/app_colors.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// `z̲` — z with a low line — as a name for the complex variable.
///
/// The engine never sees the mark: its tokenizer drops combining characters,
/// so `z̲` arrives as a plain `z`, which in a complex line is already bound to
/// the point of the plane. The glyph's whole job is to say that the line is
/// complex, which is what an expression with no `i` in it otherwise cannot.
void main() {
  PlotExpression compile(String source) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: source)]);

  const String zc = PlotExpression.complexVariable;

  /// The same thing as a node, which is how it is really typed.
  PlotExpression compileNode(List<MathNode> extra) =>
      PlotExpression.compile(<MathNode>[ComplexVariableNode(), ...extra]);

  test('it is z with a combining low line', () {
    expect(zc.codeUnits, <int>[122, 818]);
  });

  group('on its own', () {
    test('it makes the line complex, where a bare z does not', () {
      expect(compile(zc).isComplex, isTrue);
      // The contrast that makes the glyph worth having: `z` alone is the
      // third coordinate, and there is no way to tell it from a complex
      // variable without saying so.
      expect(compile('z').isComplex, isFalse);
    });

    test('and it is the identity', () {
      final w = compile(zc).evaluateComplex(1, 2);
      expect(w.real, closeTo(1, 1e-9));
      expect(w.imag, closeTo(2, 1e-9));
    });

    test('so z̲² is the same picture as (x+yi)²', () {
      final a = compile('$zc^2').evaluateComplex(1, 2);
      final b = compile('(x+yi)^2').evaluateComplex(1, 2);
      expect(a.real, closeTo(b.real, 1e-9));
      expect(a.imag, closeTo(b.imag, 1e-9));
      // (1+2i)² = -3 + 4i
      expect(a.real, closeTo(-3, 1e-9));
      expect(a.imag, closeTo(4, 1e-9));
    });
  });

  group('with i', () {
    test('they mix, since both mean what they say', () {
      // z̲ + i at the origin is i.
      final w = compile('$zc+i').evaluateComplex(0, 0);
      expect(w.real, closeTo(0, 1e-9));
      expect(w.imag, closeTo(1, 1e-9));
    });

    test('and z̲ · i turns the plane a quarter turn', () {
      // At 1 + 0i, multiplying by i gives i.
      final w = compile('$zc*i').evaluateComplex(1, 0);
      expect(w.real, closeTo(0, 1e-9));
      expect(w.imag, closeTo(1, 1e-9));
    });
  });

  group('it plots', () {
    test('without an error', () {
      for (final String source in <String>[zc, '$zc^2', '$zc+i', '2$zc']) {
        final e = compile(source);
        expect(e.isValid, isTrue, reason: '$source: ${e.error}');
        expect(e.isComplex, isTrue, reason: '$source is not complex');
      }
    });

    test('and an unknown name in the same line is still caught', () {
      final e = compile('$zc+q');
      expect(e.isValid, isFalse);
      expect(e.error, contains('q'));
    });
  });

  group('it is drawn once', () {
    testWidgets('a complex line is a surface, not also a standing curve', (
      tester,
    ) async {
      // Its free variable is z, which every other path reads as the third
      // coordinate — so z̲ came out drawn twice, once correctly as a surface
      // and once as a yellow line up the z axis.
      await tester.runAsync(() async {
        final AppColors colors = AppColors.fromType(ThemeType.classic);
        final e = compile(zc);

        Future<int> inked(bool complexView) async {
          final painter = Plot3DPainter(
            function: e,
            functions: <PlotExpression>[e],
            is3DFunction: true,
            rotationX: 0.6,
            rotationZ: 0.8,
            rangeX: 5,
            rangeY: 5,
            rangeZ: 5,
            panX: 0,
            panY: 0,
            plotMode: PlotMode.function,
            fieldType: FieldType.scalar,
            showContour: false,
            surfaceMode: SurfaceMode.none,
            colors: colors,
            plotTheme: PlotThemeData.fromColors(colors),
            complexView:
                complexView
                    ? const ComplexView()
                    : const ComplexView(modulus: false),
          );
          final r = ui.PictureRecorder();
          painter.paint(Canvas(r), const Size(320, 320));
          final img = await r.endRecording().toImage(320, 320);
          final data = (await img.toByteData())!;
          int n = 0;
          for (int i = 0; i < 320 * 320; i++) {
            if (data.getUint8(i * 4 + 3) > 200) n++;
          }
          return n;
        }

        // With every component switched off there is nothing of the function
        // left to draw...
        final int bare = await inked(false);
        final int withSurface = await inked(true);
        expect(
          withSurface,
          greaterThan(bare + 3000),
          reason: 'the surface is not drawn: $withSurface vs $bare',
        );

        // ...and in particular no standing curve. Counted by its own colour
        // rather than by total ink: a 3px line is a few hundred pixels and
        // disappears into the floor grid, so an ink comparison passed with
        // the guard removed.
        final Color accent = colors.accent;
        final painter = Plot3DPainter(
          function: e,
          functions: <PlotExpression>[e],
          is3DFunction: true,
          rotationX: 0.6,
          rotationZ: 0.8,
          rangeX: 5,
          rangeY: 5,
          rangeZ: 5,
          panX: 0,
          panY: 0,
          plotMode: PlotMode.function,
          fieldType: FieldType.scalar,
          showContour: false,
          surfaceMode: SurfaceMode.none,
          colors: colors,
          plotTheme: PlotThemeData.fromColors(colors),
          complexView: const ComplexView(modulus: false),
        );
        final r = ui.PictureRecorder();
        painter.paint(Canvas(r), const Size(320, 320));
        final data =
            (await (await r.endRecording().toImage(320, 320)).toByteData())!;
        int curveish = 0;
        for (int i = 0; i < 320 * 320; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          if ((data.getUint8(o) - accent.r * 255).abs() < 40 &&
              (data.getUint8(o + 1) - accent.g * 255).abs() < 40 &&
              (data.getUint8(o + 2) - accent.b * 255).abs() < 40) {
            curveish++;
          }
        }
        expect(
          curveish,
          lessThan(60),
          reason: '$curveish px of standing curve remain',
        );
      });
    });
  });

  group('as a node', () {
    test('it is indivisible, which is the whole reason it is one', () {
      // As two characters in a literal the editor deleted them one at a time —
      // backspace left a bare z — and removing the exponent of z̲² took the
      // whole expression. A node is removed whole or not at all.
      final node = ComplexVariableNode();
      expect(node, isA<MathNode>());
      // It extends UnitVectorNode so that every rule the editor already has
      // for an indivisible glyph applies to it without being rewritten.
      expect(node, isA<UnitVectorNode>());
    });

    test('it compiles to the complex variable', () {
      final e = compileNode(<MathNode>[]);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isComplex, isTrue);
      final w = e.evaluateComplex(1, 2);
      expect(w.real, closeTo(1, 1e-9));
      expect(w.imag, closeTo(2, 1e-9));
    });

    test('and carries an exponent, the case that used to wipe the line', () {
      final e = PlotExpression.compile(<MathNode>[
        ExponentNode(
          base: <MathNode>[ComplexVariableNode()],
          power: <MathNode>[LiteralNode(text: '2')],
        ),
      ]);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isComplex, isTrue);
      // (1 + 2i)² = -3 + 4i
      final w = e.evaluateComplex(1, 2);
      expect(w.real, closeTo(-3, 1e-9));
      expect(w.imag, closeTo(4, 1e-9));
    });

    test('it is not a unit vector, however it is built', () {
      // It extends one for the editor's sake. A line containing it is a
      // function of a complex variable, not a field with a z̲ component.
      expect(
        VectorFieldParser.isVectorFieldNodes(<MathNode>[ComplexVariableNode()]),
        isFalse,
      );
      expect(
        VectorFieldParser.fromNodes(<MathNode>[ComplexVariableNode()]),
        isNull,
      );
      // And a real one still is.
      expect(
        VectorFieldParser.isVectorFieldNodes(<MathNode>[UnitVectorNode('x')]),
        isTrue,
      );
    });

    test('it survives being saved and read back', () {
      // Through the public round trip, which is what a cell actually uses.
      final String json = MathExpressionSerializer.serializeToJson(<MathNode>[
        ComplexVariableNode(),
      ]);
      final List<MathNode> back = MathExpressionSerializer.deserializeFromJson(
        json,
      );
      expect(back, hasLength(1));
      expect(back.first, isA<ComplexVariableNode>());
    });
  });
}
