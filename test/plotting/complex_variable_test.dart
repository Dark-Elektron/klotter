import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/settings/settings_provider.dart';

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

  group('on the keypad', () {
    testWidgets('it is revealed by long-pressing i', (tester) async {
      // It belongs on that key because it is the same idea: i is what makes a
      // line complex, and z̲ is what such a line is a function of.
      SharedPreferences.setMockInitialValues({
        'walkthrough_completed_v2': true,
      });
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));

      // The extras page, where i lives.
      await tester.fling(
        find.byType(PageView).last,
        const Offset(-400, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('i'), findsOneWidget);

      await tester.longPress(find.text('i'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text(PlotExpression.complexVariable),
        findsOneWidget,
        reason: 'long-pressing i does not offer the complex variable',
      );
    });
  });
}
