import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'math_editor_controller.dart';
import 'renderer.dart';

/// A number inside a [LiteralNode] that can be dragged to change its value.
///
/// klotter's expression is a live node tree rather than text, so any number in
/// it can be scrubbed without the user first declaring a slider — the thing a
/// calculator+grapher can do that a standalone grapher cannot.
class ScrubTarget {
  final LiteralNode node;

  /// Character range of the number within [node].text. [end] moves as the
  /// formatted value grows or shrinks.
  final int start;
  int end;

  /// Value when the drag began, so the whole gesture is relative to one
  /// origin and repeated small drags do not accumulate rounding error.
  final double initialValue;

  /// Index of an adjacent `+`/`-` that carries this number's sign, if there is
  /// one. Writing through it keeps `a + 3` turning into `a - 3` rather than the
  /// malformed `a + -3`.
  final int? signIndex;

  /// Decimal places the number was typed with. Held as a floor so dragging
  /// never silently reshapes `3.14` into `4` — the value should move, not the
  /// number's precision.
  final int typedDecimals;

  ScrubTarget({
    required this.node,
    required this.start,
    required this.end,
    required this.initialValue,
    this.signIndex,
    this.typedDecimals = 0,
  });

  /// How much one logical pixel of drag changes the value.
  ///
  /// Scaled by magnitude so dragging feels the same whether the number is
  /// 0.5 or 5000 — roughly 150px to double it — with a floor so a value of
  /// exactly zero is still movable.
  double get perPixel {
    final double magnitude = initialValue.abs();
    return (magnitude < 1 ? 1.0 : magnitude) / 150.0;
  }
}

extension ScrubbableEditor on MathEditorController {
  /// The number under [localPosition], or null if there is not one there.
  ScrubTarget? scrubTargetAt(Offset localPosition) {
    NodeLayoutInfo? best;
    for (final NodeLayoutInfo info in layoutRegistry.values) {
      if (!info.rect.contains(localPosition)) continue;
      if (best == null ||
          info.rect.width * info.rect.height <
              best.rect.width * best.rect.height) {
        best = info;
      }
    }
    if (best == null) return null;

    final String text = best.node.text;
    if (text.isEmpty) return null;

    // Map the touch to a character. Display text is not the raw text — it
    // gains spacing around operators — so the offset has to be translated
    // back before it can index node.text.
    int charIndex;
    final RenderParagraph? paragraph = best.renderParagraph;
    if (paragraph != null && paragraph.attached) {
      final pos = paragraph.getPositionForOffset(
        Offset(localPosition.dx - best.rect.left, best.fontSize / 2),
      );
      charIndex = MathTextStyle.displayToLogicalIndex(
        text,
        pos.offset.clamp(0, best.displayText.length),
        forceLeadingOperatorPadding: best.forceLeadingOperatorPadding,
      );
    } else {
      charIndex = text.length ~/ 2;
    }
    charIndex = charIndex.clamp(0, text.length - 1);

    final (int start, int end)? run = _numericRunAround(text, charIndex);
    if (run == null) return null;

    final String literal = text.substring(run.$1, run.$2);
    final double? magnitude = double.tryParse(literal);
    if (magnitude == null) return null;

    final int dot = literal.indexOf('.');
    final int decimals = dot == -1 ? 0 : literal.length - dot - 1;

    // Fold an adjacent binary +/- into the value, so dragging through zero
    // rewrites the operator instead of stacking signs.
    int? signIndex;
    double value = magnitude;
    final int before = run.$1 - 1;
    if (before >= 0 && (text[before] == '+' || text[before] == '-')) {
      final bool isBinary = before > 0 && _endsOperand(text[before - 1]);
      if (isBinary) {
        signIndex = before;
        if (text[before] == '-') value = -magnitude;
      } else if (before == 0 && text[before] == '-') {
        // A leading minus on the whole literal is part of the number.
        signIndex = before;
        value = -magnitude;
      }
    }

    return ScrubTarget(
      node: best.node,
      start: run.$1,
      end: run.$2,
      initialValue: value,
      signIndex: signIndex,
      typedDecimals: decimals,
    );
  }

  /// Write [value] back into [target], keeping the rest of the literal intact.
  void applyScrub(ScrubTarget target, double value) {
    final String text = target.node.text;
    final int? signIndex = target.signIndex;

    final String body = _formatScrubbed(
      signIndex == null ? value : value.abs(),
      target.initialValue,
      target.typedDecimals,
    );

    if (signIndex == null) {
      target.node.text =
          text.substring(0, target.start) + body + text.substring(target.end);
      target.end = target.start + body.length;
    } else {
      // Rewrite the operator with the sign so the expression stays well formed.
      final String sign = value < 0 ? '-' : '+';
      target.node.text =
          text.substring(0, signIndex) +
          sign +
          body +
          text.substring(target.end);
      target.end = signIndex + 1 + body.length;
    }
    refreshDisplay();
  }
}

/// Expand around [index] to the digits (and at most one decimal point) that
/// surround it. Returns null when the character touched is not part of a
/// number — a sign is deliberately excluded, since a leading `-` is almost
/// always an operator rather than part of the literal.
(int, int)? _numericRunAround(String text, int index) {
  bool isDigit(int i) {
    if (i < 0 || i >= text.length) return false;
    final int c = text.codeUnitAt(i);
    return c >= 0x30 && c <= 0x39;
  }

  bool isPart(int i) =>
      isDigit(i) || (i >= 0 && i < text.length && text[i] == '.');

  // The touch may land just past the number's last character.
  int seed = index;
  if (!isPart(seed) && isPart(seed - 1)) seed = index - 1;
  if (!isDigit(seed) &&
      !(isPart(seed) && (isDigit(seed - 1) || isDigit(seed + 1)))) {
    return null;
  }

  int start = seed;
  while (isPart(start - 1)) {
    start--;
  }
  int end = seed + 1;
  while (isPart(end)) {
    end++;
  }

  // Trim a trailing dot so "2." scrubs as "2".
  if (text[end - 1] == '.') end--;
  if (start >= end) return null;
  // Reject a run that is only dots.
  if (!RegExp(r'\d').hasMatch(text.substring(start, end))) return null;
  return (start, end);
}

/// Format a scrubbed value at a precision that matches its size, so dragging
/// never produces `3.0000000000000004` or drops to a useless `3`.
String _formatScrubbed(double value, double origin, int typedDecimals) {
  final double magnitude = math.max(value.abs(), origin.abs());
  final int byMagnitude =
      magnitude >= 100 ? 0 : (magnitude >= 10 ? 1 : (magnitude >= 1 ? 2 : 3));

  // The typed precision is a floor. Dragging should move the value, not
  // reshape the number: 3.14 stays two decimals all the way to 4.00 rather
  // than collapsing to 4 and never coming back.
  final int decimals = math.max(typedDecimals, byMagnitude).clamp(0, 6);
  String out = value.toStringAsFixed(decimals);

  // Trim only the digits beyond what was typed.
  if (out.contains('.') && decimals > typedDecimals) {
    while (out.contains('.') &&
        out.endsWith('0') &&
        _decimalsOf(out) > typedDecimals) {
      out = out.substring(0, out.length - 1);
    }
    if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  }
  if (out == '-0') out = '0';
  return out;
}

int _decimalsOf(String s) {
  final int dot = s.indexOf('.');
  return dot == -1 ? 0 : s.length - dot - 1;
}

/// Whether [c] ends an operand, which is what makes a following +/- binary
/// rather than a sign.
bool _endsOperand(String c) => RegExp(r'[0-9a-zA-Z\)\]\.]').hasMatch(c);
