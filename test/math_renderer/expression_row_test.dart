import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/expression_row.dart';

/// The unit a plot is now made of.
///
/// A plot used to be one editor whose lines were `NewlineNode` sentinels, so a
/// line could carry nothing of its own. These are the two properties the rest
/// of the feature rests on: a row has an identity that survives being moved,
/// and it remembers whether it is shown.
void main() {
  test('ids are unique', () {
    final Set<String> seen = <String>{
      for (int i = 0; i < 200; i++) ExpressionRowIds.take(),
    };
    expect(seen, hasLength(200));
  });

  test('fresh ids do not collide with loaded ones', () {
    // Saved rows arrive with ids minted in an earlier session. Handing the
    // same id to a new row would make the two indistinguishable — the hidden
    // flag of one would follow the other.
    ExpressionRowIds.reserveAbove(<String>['r5000', 'r4999']);
    final String next = ExpressionRowIds.take();
    expect(next, isNot('r5000'));
    expect(int.parse(next.substring(1)), greaterThan(5000));
  });

  test('reserving ignores ids it did not mint', () {
    // Older saves, or hand-edited data, may carry anything at all. It must not
    // throw and must not reset the counter.
    final String before = ExpressionRowIds.take();
    ExpressionRowIds.reserveAbove(<String>['', 'x', 'rabbit', 'r']);
    final String after = ExpressionRowIds.take();
    expect(
      int.parse(after.substring(1)),
      greaterThan(int.parse(before.substring(1))),
    );
  });

  test('a row starts visible and can be hidden', () {
    final ExpressionRow row = ExpressionRow(id: ExpressionRowIds.take());
    addTearDown(row.dispose);
    expect(row.visible, isTrue, reason: 'a new row must draw');
    row.visible = false;
    expect(row.visible, isFalse);
  });

  test('two rows have different tokens', () {
    // The token keys the widget, so two rows sharing one would make Flutter
    // reuse the wrong element when rows are renumbered.
    final ExpressionRow a = ExpressionRow(id: ExpressionRowIds.take());
    final ExpressionRow b = ExpressionRow(id: ExpressionRowIds.take());
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(a.token, isNot(b.token));
  });
}
