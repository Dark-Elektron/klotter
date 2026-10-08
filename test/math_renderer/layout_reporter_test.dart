import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/renderer.dart';

/// What [LayoutReporter] promises the layout registry.
///
/// It measures its child where the child is painted, relative to the editor's
/// content box, and reports when that box changes or when what the report
/// describes does. It replaced three hand-written post-frame measurements,
/// each with its own retries, and whose check for a box mid-layout ran only in
/// debug builds.
void main() {
  final GlobalKey root = GlobalKey();
  late List<Rect> reports;
  late List<RenderObject?> drawn;

  setUp(() {
    reports = <Rect>[];
    drawn = <RenderObject?>[];
  });

  Widget host({double left = 10, Object version = 0, String text = 'x'}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: root,
            width: 300,
            height: 100,
            child: Padding(
              padding: EdgeInsets.only(left: left, top: 5),
              child: Align(
                alignment: Alignment.topLeft,
                child: LayoutReporter(
                  rootKey: root,
                  version: version,
                  report: (Rect rect, RenderObject? child) {
                    reports.add(rect);
                    drawn.add(child);
                  },
                  child: Text(text),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('reports where its child is painted, against the root', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(reports, hasLength(1));
    expect(reports.single.topLeft, const Offset(10, 5));
    expect(
      drawn.single,
      isA<RenderParagraph>(),
      reason: 'the text layout, for placing the caret between characters',
    );
  });

  testWidgets('a box that moves is reported again; one that stays is not', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(host());
    expect(reports, hasLength(1), reason: 'nothing changed');
    await tester.pumpWidget(host(left: 40));
    expect(reports, hasLength(2));
    expect(reports.last.left, 40);
  });

  testWidgets('a new version is reported even where nothing moved', (
    tester,
  ) async {
    // The registry is emptied on every new structure version, so a node that
    // has not moved still has to report into the empty one.
    await tester.pumpWidget(host());
    await tester.pumpWidget(host(version: 1));
    expect(reports, hasLength(2));
    expect(reports.last, reports.first);
  });
}
