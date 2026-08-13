import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/scrub.dart';

/// Drag-to-tune rewrites a number inside a literal without disturbing the rest
/// of the expression. klotter can do this without a slider declaration because
/// the expression is already a node tree rather than text.
void main() {
  ScrubTarget target(
    String text,
    int start,
    int end,
    double value, {
    int? signIndex,
    int typedDecimals = 0,
  }) => ScrubTarget(
    node: LiteralNode(text: text),
    start: start,
    end: end,
    initialValue: value,
    signIndex: signIndex,
    typedDecimals: typedDecimals,
  );

  group('applyScrub rewrites only the number', () {
    test('replaces the run and leaves surrounding characters', () {
      final c = MathEditorController();
      final t = target('2x', 0, 1, 2);
      c.applyScrub(t, 7);
      expect(t.node.text, equals('7x'));
      c.dispose();
    });

    test('handles a number in the middle of a literal', () {
      final c = MathEditorController();
      final t = target('x+12y', 2, 4, 12);
      c.applyScrub(t, 5);
      expect(t.node.text, equals('x+5y'));
      c.dispose();
    });

    test('end tracks the formatted length so repeated drags stay anchored', () {
      final c = MathEditorController();
      final t = target('2x', 0, 1, 2);
      c.applyScrub(t, 100);
      expect(t.node.text, equals('100x'));
      c.applyScrub(t, 3);
      expect(t.node.text, equals('3x'), reason: 'must not leave "1003x"');
      c.dispose();
    });

    test('does not emit floating-point noise', () {
      final c = MathEditorController();
      final t = target('3', 0, 1, 3);
      c.applyScrub(t, 3.0000000000000004);
      expect(t.node.text, equals('3'));
      c.dispose();
    });

    test('typed precision is a floor, so a decimal never collapses', () {
      // 3.14 must not silently become 4 partway through a drag.
      final c = MathEditorController();
      final t = target('3.14', 0, 4, 3.14, typedDecimals: 2);
      c.applyScrub(t, 4.0);
      expect(t.node.text, equals('4.00'));
      c.applyScrub(t, 3.14);
      expect(t.node.text, equals('3.14'), reason: 'must return exactly');
      c.dispose();
    });

    test('an integer may gain decimals but does not keep spurious zeros', () {
      final c = MathEditorController();
      final t = target('3', 0, 1, 3);
      c.applyScrub(t, 3.5);
      expect(t.node.text, equals('3.5'));
      c.applyScrub(t, 4);
      expect(t.node.text, equals('4'));
      c.dispose();
    });

    test('keeps precision for small values', () {
      final c = MathEditorController();
      final t = target('0.5', 0, 3, 0.5);
      c.applyScrub(t, 0.567);
      expect(t.node.text, equals('0.567'));
      c.dispose();
    });

    test('dragging through zero rewrites the operator, not the sign', () {
      // "2.5x+3.14" scrubbing the second number must become "2.5x-2",
      // never the malformed "2.5x+-2".
      final c = MathEditorController();
      final t = target('2.5x+3.14', 5, 9, 3.14, signIndex: 4, typedDecimals: 2);
      c.applyScrub(t, -2.0);
      expect(t.node.text, equals('2.5x-2.00'));
      c.applyScrub(t, 6.0);
      expect(t.node.text, equals('2.5x+6.00'), reason: 'and back again');
      c.dispose();
    });

    test('a leading minus stays part of the number', () {
      final c = MathEditorController();
      final t = target('-4', 1, 2, -4, signIndex: 0);
      c.applyScrub(t, 9);
      expect(t.node.text, equals('+9'));
      c.dispose();
    });

    test('negative zero reads as zero', () {
      final c = MathEditorController();
      final t = target('1', 0, 1, 1);
      c.applyScrub(t, -0.0001);
      expect(t.node.text, equals('0'));
      c.dispose();
    });
  });

  group('drag sensitivity scales with magnitude', () {
    test('a big number moves faster per pixel than a small one', () {
      expect(
        target('5000', 0, 4, 5000).perPixel,
        greaterThan(target('5', 0, 1, 5).perPixel),
      );
    });

    test('zero is still movable', () {
      expect(target('0', 0, 1, 0).perPixel, greaterThan(0));
    });

    test('roughly 150px doubles a value', () {
      final t = target('10', 0, 2, 10);
      expect(t.initialValue + 150 * t.perPixel, closeTo(20, 0.001));
    });
  });
}
