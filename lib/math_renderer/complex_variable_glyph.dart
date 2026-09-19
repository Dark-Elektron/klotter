import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'math_text_style.dart';

/// `z̲` — the complex variable, drawn as a letter with a rule beneath it.
///
/// The rule is painted rather than left to `TextDecoration`, because a text
/// decoration sits where the font puts it: tight against the glyph, so once it
/// was thick enough to notice it read as a leg of the z rather than a mark
/// under it. There is no way to offset a decoration.
///
/// It is a render object rather than a `Column` of a `Text` and a line. A
/// column reports its own height as its baseline, so the letter floated above
/// the row it belongs to; every glyph in an expression is laid out against a
/// shared baseline, and this reports the letter's own.
class ComplexVariableGlyph extends LeafRenderObjectWidget {
  const ComplexVariableGlyph({
    super.key,
    required this.fontSize,
    required this.color,
    this.textScaler = TextScaler.noScaling,
  });

  final double fontSize;
  final Color color;
  final TextScaler textScaler;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderComplexVariableGlyph(
        fontSize: fontSize,
        color: color,
        textScaler: textScaler,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderComplexVariableGlyph renderObject,
  ) {
    renderObject
      ..fontSize = fontSize
      ..color = color
      ..textScaler = textScaler;
  }
}

/// Public so a test can measure the letter and the rule directly.
class RenderComplexVariableGlyph extends RenderBox {
  RenderComplexVariableGlyph({
    required double fontSize,
    required Color color,
    required TextScaler textScaler,
  }) : _fontSize = fontSize,
       _color = color,
       _textScaler = textScaler;

  double _fontSize;
  Color _color;
  TextScaler _textScaler;

  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    markNeedsLayout();
  }

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    markNeedsLayout();
  }

  /// The gap between the letter and the rule, and the rule's weight, both as a
  /// share of the font so they hold at every size.
  double get _scaled => _textScaler.scale(_fontSize);
  double get gap => _scaled * 0.05;

  /// Where the letter actually sits, as opposed to how tall its line box is.
  ///
  /// The rule hangs from the baseline, not from the bottom of the text. A text
  /// box reserves room for descenders — the tail of a g — and `z` has none, so
  /// measuring from the bottom pushed the rule a descender's depth too low.
  double get _baselineY =>
      _painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  double get ruleHeight => _scaled * 0.08;

  late TextPainter _painter;

  void _layoutText() {
    _painter = TextPainter(
      text: TextSpan(
        text: 'z',
        style: MathTextStyle.getStyle(_fontSize).copyWith(color: _color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();
  }

  @override
  void performLayout() {
    _layoutText();
    size = constraints.constrain(
      Size(
        _painter.width,
        math.max(_painter.height, _baselineY + gap + ruleHeight),
      ),
    );
  }

  // The letter's baseline, not the box's bottom, so this sits in a row of
  // glyphs like any other character.
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    _layoutText();
    return _painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _layoutText();
    return constraints.constrain(
      Size(
        _painter.width,
        math.max(_painter.height, _baselineY + gap + ruleHeight),
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset);
    context.canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + _baselineY + gap,
        _painter.width,
        ruleHeight,
      ),
      Paint()..color = _color,
    );
  }
}
