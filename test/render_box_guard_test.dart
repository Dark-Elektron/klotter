import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/utils/render_box.dart';

/// Reading a render box that has not been laid out is what throws
/// `'debugNeedsLayout': is not true` — an assertion that took the whole app
/// down to a red screen. Gesture callbacks can easily run between a rebuild
/// and the layout that follows, so the geometry has to be asked for in a way
/// that can answer "not yet".
void main() {
  testWidgets('a laid-out box is returned', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox(key: key, width: 40, height: 20)),
      ),
    );
    final RenderBox? box = laidOutBox(key.currentContext);
    expect(box, isNotNull);
    expect(box!.size, const Size(40, 20));
  });

  test('a null context is not a crash', () {
    expect(laidOutBox(null), isNull);
  });

  testWidgets('a context with no render object yet gives null', (tester) async {
    // A key that was never mounted has no context and so no geometry.
    final key = GlobalKey();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(laidOutBox(key.currentContext), isNull);
  });

  testWidgets('an unmounted box gives null rather than stale geometry', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox(key: key, width: 40, height: 20)),
      ),
    );
    expect(laidOutBox(key.currentContext), isNotNull);

    // Take it out of the tree; anything still holding the key must now get
    // null instead of a detached box.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(laidOutBox(key.currentContext), isNull);
  });
}
