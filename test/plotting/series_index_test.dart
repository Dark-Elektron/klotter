import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// Which colour a row wears.
///
/// Colour used to be position in whatever list a painter was iterating. Those
/// lists are filtered — invalid lines dropped, vector lines dropped — and 3D
/// re-partitions them into surfaces, standing curves and equations, indexing
/// each from zero. So the same plot got different colours in 2D and in 3D, and
/// no swatch beside a row could have matched both.
///
/// The row number is the one index that means the same thing everywhere.
void main() {
  List<MathNode> cell(List<String> lines) {
    final List<MathNode> out = <MathNode>[];
    for (final String line in lines) {
      if (out.isNotEmpty) out.add(NewlineNode());
      out.add(LiteralNode(text: line));
    }
    return out;
  }

  // Written as bare literals, which is how the editor stores typed text. Note
  // `sin(x)` does *not* compile that way — it needs a TrigNode, and as a
  // literal it reads as an unknown variable `sin`. Fixtures here stick to
  // expressions a literal can actually carry.
  test('rows are numbered in the order they are written', () {
    final List<PlotExpression> c = PlotExpression.compileAll(
      cell(<String>['2x', 'x^2+y^2', 'x^2+y^2+z^2=4']),
    );
    expect(c.map((PlotExpression e) => e.seriesIndex), <int>[0, 1, 2]);
  });

  test('an invalid row keeps its number, and the ones after it keep theirs', () {
    // This is the case position could never handle. The middle line does not
    // compile, so it is dropped from whatever list the painter walks — and the
    // line below it would inherit its colour.
    final List<PlotExpression> c = PlotExpression.compileAll(
      cell(<String>['2x', 'q', 'x^2']),
    );
    expect(c, hasLength(3));
    expect(
      c[1].isValid,
      isFalse,
      reason: 'the fixture must have a bad line — q is an unknown variable',
    );
    expect(c[2].seriesIndex, 2, reason: 'the third row was renumbered to 1');

    final List<PlotExpression> drawable =
        c.where((PlotExpression e) => e.isValid).toList();
    expect(drawable, hasLength(2));
    expect(
      drawable.last.seriesIndex,
      2,
      reason:
          'after filtering, the surviving row reports position 1 rather than '
          'the row number 2 — which is exactly the bug',
    );
  });

  test('a row that is hidden still holds its number', () {
    // Hiding one curve must not recolour the others, which is why a hidden row
    // stays in the list with a flag rather than being removed from it.
    final List<PlotExpression> c = PlotExpression.compileAll(
      cell(<String>['2x', 'x^2', 'x^3']),
    );
    c[1].hidden = true;
    expect(c[2].seriesIndex, 2);
    expect(c.where((PlotExpression e) => !e.hidden).last.seriesIndex, 2);
  });

  test('a single row is row zero', () {
    final List<PlotExpression> c = PlotExpression.compileAll(
      cell(<String>['2x']),
    );
    expect(c.single.seriesIndex, 0);
  });
}
