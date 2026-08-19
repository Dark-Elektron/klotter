import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/renderer.dart';

/// Where the caret goes when an expression has more than one line.
///
/// This is the difference between klotter and the app it was forked from. There,
/// the action key starts a new cell, so an editor is always one line and
/// "nearest node" and "rightmost node" both mean what they say. Here it inserts
/// a newline in the same cell — the comment on `_handleEnter` says so — and one
/// editor holds several lines. Both rules then reach across lines: a tap past
/// the end of a short line resolves to the long line above it.
///
/// The caret landing on a line the user was not pointing at is what made
/// backspace look erratic. It deleted correctly, from the wrong place.
void main() {
  /// Two lines: a long one on top, a short one below.
  ///
  /// Geometry rather than a rendered widget, because what is under test is the
  /// choice made from a set of rects — the rects themselves are the renderer's
  /// job and are tested elsewhere. This way the awkward case can be stated
  /// exactly, which a laid-out expression cannot.
  MathEditorController twoLines() {
    final controller = MathEditorController();
    final LiteralNode top = LiteralNode(text: '123456789012');
    final LiteralNode bottom = LiteralNode(text: '12');
    controller.setExpression(<MathNode>[top, NewlineNode(), bottom]);

    void register(LiteralNode node, int index, Rect rect) {
      controller.registerNodeLayout(
        NodeLayoutInfo(
          rect: rect,
          node: node,
          parentId: null,
          path: null,
          index: index,
          fontSize: 20,
          textScaler: TextScaler.noScaling,
        ),
      );
    }

    register(top, 0, const Rect.fromLTWH(0, 0, 200, 30));
    register(bottom, 2, const Rect.fromLTWH(0, 30, 40, 30));
    return controller;
  }

  test('the two lines are set up as intended', () {
    // Guards the test itself: the trap here is a fixture that cannot tell the
    // rules apart. The bottom line must be much shorter than the top one, or
    // straight-line distance happens to give the right answer and nothing is
    // being measured.
    final MathEditorController c = twoLines();
    addTearDown(c.dispose);
    final List<Rect> rects =
        c.layoutRegistry.values.map((NodeLayoutInfo i) => i.rect).toList();
    expect(rects.length, 2);
    expect(
      rects[1].bottom,
      greaterThan(rects[0].bottom),
      reason: 'not stacked',
    );
    expect(rects[1].right, lessThan(rects[0].right / 2), reason: 'not shorter');
  });

  test('a tap past the end of the short line stays on it', () {
    final MathEditorController c = twoLines();
    addTearDown(c.dispose);

    // x = 190 is beyond the short line but still within the long one's width,
    // and y = 45 is squarely on the short line. By straight-line distance the
    // long line's centre is nearer, which is the bug.
    c.tapAt(const Offset(190, 45));

    expect(
      c.cursor.index,
      2,
      reason: 'the caret jumped to the line above the one that was tapped',
    );
  });

  test('a tap on the long line still stays on it', () {
    final MathEditorController c = twoLines();
    addTearDown(c.dispose);
    c.tapAt(const Offset(190, 15));
    expect(c.cursor.index, 0);
  });

  test('a tap below both lines still finds the nearest', () {
    // Off the end of every line, so there is no line to prefer and the old
    // straight-line rule is the only sensible answer. Reaching for the bottom
    // line is what a tap under the expression means.
    final MathEditorController c = twoLines();
    addTearDown(c.dispose);
    c.tapAt(const Offset(20, 200));
    expect(c.cursor.index, 2);
  });

  group('the edges of a line', () {
    test('tapping off the right of the short line ends that line', () {
      final MathEditorController c = twoLines();
      addTearDown(c.dispose);

      // This is what the editor calls when a tap is past the content bounds,
      // and the bounds span both lines — so a tap to the right of the short
      // line is past them even though it is nowhere near the long line's end.
      c.moveCursorToEndWithRect(atY: 45);

      expect(c.cursor.index, 2, reason: 'it ended the widest line instead');
      expect(
        c.cursor.subIndex,
        2,
        reason: 'the caret should be after both characters of the short line',
      );
    });

    test('tapping off the left of the short line starts that line', () {
      final MathEditorController c = twoLines();
      addTearDown(c.dispose);
      c.moveCursorToStartWithRect(atY: 45);
      expect(c.cursor.index, 2);
      expect(c.cursor.subIndex, 0);
    });

    test('with no line named, the whole expression is used as before', () {
      // Every other caller passes nothing, and must keep the old meaning.
      final MathEditorController c = twoLines();
      addTearDown(c.dispose);
      c.moveCursorToEndWithRect();
      expect(c.cursor.index, 0, reason: 'the widest line is the long one');
    });
  });
}
