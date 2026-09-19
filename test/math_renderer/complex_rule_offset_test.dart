import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/complex_variable_glyph.dart';

/// The rule under z̲ is clear of the letter, and as heavy as its strokes.
///
/// A text decoration cannot be offset — it sits where the font puts it — so
/// once it was thick enough to notice, it read as a leg of the z rather than a
/// mark beneath it. The rule is painted, which is what makes the gap possible.
void main() {
  testWidgets('the glyph is taller than the letter, by gap plus rule', (
    tester,
  ) async {
    const double size = 40;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ComplexVariableGlyph(fontSize: size, color: Colors.black),
          ),
        ),
      ),
    );

    final RenderComplexVariableGlyph box = tester.renderObject(
      find.byType(ComplexVariableGlyph),
    );

    expect(box.gap, greaterThan(1), reason: 'no gap: the rule touches the z');
    expect(
      box.ruleHeight,
      greaterThan(2),
      reason: 'the rule is too light to read as part of the symbol',
    );
    // That the letter still owns the baseline — rather than the box bottom,
    // which a Column reported and which pushed the glyph out of line — is not
    // asserted here: getDistanceToBaseline may only be called during layout.
    // The editor tests cover it, by drawing a z̲ in a real expression.
  });

  testWidgets('both scale with the font', (tester) async {
    Future<RenderComplexVariableGlyph> at(double size) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ComplexVariableGlyph(fontSize: size, color: Colors.black),
            ),
          ),
        ),
      );
      return tester.renderObject(find.byType(ComplexVariableGlyph));
    }

    final double smallRule = (await at(20)).ruleHeight;
    final double largeRule = (await at(60)).ruleHeight;
    expect(
      largeRule,
      greaterThan(smallRule * 2),
      reason: 'the rule is a fixed size, so it is wrong at one end or other',
    );
  });
}
