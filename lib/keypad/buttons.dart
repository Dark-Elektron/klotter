import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/settings_provider.dart';

/// How the key labels of a keypad are drawn, where its keys have been measured
/// for them.
///
/// The keypad measures every label against its key and puts the answer here
/// (see [byLength]), so labels of one length stay the same size as each other
/// and none is shrunk further than it must be. A tablet's keys have room for
/// nearly every label whole. A phone's are about 36 dp wide, and there the
/// label sits closer to the edge of its key ([labelPadding]) and an inverse
/// function is drawn as two lines ([stackArc]), which is what lets sin, cos
/// and tan be drawn at full size where they used to be shrunk by length.
class KeyLabelScale extends InheritedWidget {
  const KeyLabelScale({
    super.key,
    required this.byLength,
    this.labelPadding = keyLabelPadding,
    this.stackArc = false,
    required super.child,
  });

  /// The share of its key's font size a label of each length is drawn at,
  /// by length in characters; a length that is not here is drawn whole.
  final Map<int, double> byLength;

  /// The room left either side of a label inside its key.
  final double labelPadding;

  /// Whether asin, acos and atan are drawn as a small "arc" over sin, cos and
  /// tan (see [keyLabel]).
  final bool stackArc;

  static KeyLabelScale? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeyLabelScale>();

  @override
  bool updateShouldNotify(KeyLabelScale oldWidget) =>
      !mapEquals(oldWidget.byLength, byLength) ||
      oldWidget.labelPadding != labelPadding ||
      oldWidget.stackArc != stackArc;
}

/// The room left either side of a key's label, unless its keypad says
/// otherwise (see [KeyLabelScale.labelPadding]).
const double keyLabelPadding = 2;

/// The share of the key's font size the "arc" of a stacked inverse function
/// is drawn at (see [keyLabel]).
const double arcShare = 0.5;

/// The labels drawn as "arc" over the function, where the keypad stacks them.
const Set<String> arcLabels = <String>{'asin', 'acos', 'atan'};

/// The labels drawn as a fraction on every keypad: numerator over
/// denominator, with a bar between, as the expression itself shows them.
const Map<String, (String, String)> fractionLabels = <String, (String, String)>{
  'd/dx': ('d', 'dx'),
};

/// The share of the key's font size a fraction's two lines are drawn at.
/// Two lines at full size would fill the key from top to bottom; at this
/// share they sit in it with room above and below, as a fraction does in a
/// line of text.
const double fractionShare = 0.7;

/// What a key shows on its face for [label]: the label, sized to its key (see
/// [keyLabelShare]), with room either side, and shrunk further if it still
/// cannot fit (large text-scale settings, narrow devices).
///
/// Where the keypad stacks them (see [KeyLabelScale.stackArc]), an inverse
/// function is two lines: a small "arc" over the function at the size the
/// function's own key draws it. "asin" in one line is four letters on a key
/// with room for three, and had to be drawn at half size; as "arc" over
/// "sin" it is no wider than sin itself.
Widget keyLabel(
  BuildContext context,
  String label, {
  required Color? color,
  required double fontSize,
}) {
  final KeyLabelScale? measured = KeyLabelScale.maybeOf(context);
  TextStyle sized(double size) =>
      TextStyle(color: color, fontSize: size, height: 1.0);

  final (String, String)? fraction = fractionLabels[label];
  final Widget face;
  if (fraction != null) {
    // d over dx rather than d/dx: the notation itself, and narrower than the
    // label written out in a line, so it never has to be shrunk to fit.
    final double size = fontSize * fractionShare;
    final Color? ink = color ?? DefaultTextStyle.of(context).style.color;
    Widget line(String text) => Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      style: sized(size),
    );
    face = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          line(fraction.$1),
          Container(
            height: math.max(1.0, size / 14),
            margin: EdgeInsets.symmetric(vertical: size * 0.12),
            color: ink,
          ),
          line(fraction.$2),
        ],
      ),
    );
  } else if ((measured?.stackArc ?? false) && arcLabels.contains(label)) {
    final String function = label.substring(1);
    face = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'arc',
          maxLines: 1,
          softWrap: false,
          style: sized(fontSize * arcShare),
        ),
        Text(
          function,
          maxLines: 1,
          softWrap: false,
          style: sized(fontSize * keyLabelShare(context, function)),
        ),
      ],
    );
  } else {
    face = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: sized(fontSize * keyLabelShare(context, label)),
    );
  }
  return Padding(
    padding: EdgeInsets.symmetric(
      horizontal: measured?.labelPadding ?? keyLabelPadding,
    ),
    child: FittedBox(fit: BoxFit.scaleDown, child: face),
  );
}

/// The share of its key's font size [label] is drawn at.
///
/// Measured, on a keypad that has measured its keys (see [KeyLabelScale]).
/// Otherwise by length: klotter's phone keys are only ~36 dp wide, so
/// multi-character labels like "asin", "acos" and "logn" do not fit at the
/// nominal size, and the type shrinks to the label's length rather than the
/// label being clipped or wrapped — the glyphs stay centred and the key keeps
/// its full touch target.
double keyLabelShare(BuildContext context, String label) {
  final int length = label.characters.length;
  final KeyLabelScale? measured = KeyLabelScale.maybeOf(context);
  if (measured != null) return measured.byLength[length] ?? 1.0;
  return length <= 2
      ? 1.0
      : length == 3
      ? 0.66
      : length == 4
      ? 0.50
      : 0.42;
}

// ---- what a screen reader says --------------------------------------------

/// The words for a key, by what the key shows.
///
/// A key's face is a glyph, and TalkBack reads glyphs badly or not at all: ⌫
/// is silent, ⁿ√ comes out letter by letter, and ⎌ as its Unicode name. A face
/// with no entry here is read as itself (see [spokenKeyLabel]), which suits
/// digits and plain letters.
const Map<String, String> _spokenFaces = <String, String>{
  // The number pad.
  '()': 'brackets',
  '⌫': 'backspace',
  '+': 'plus',
  '−': 'minus',
  '×': 'times',
  '÷': 'divide',
  '.': 'point',
  'ᴇ': 'times ten to the power',
  'CE': 'clear expression',
  '⌘': 'new row',
  // Relations.
  '=': 'equals',
  '≥': 'greater than or equal to',
  '≤': 'less than or equal to',
  '>': 'greater than',
  '<': 'less than',
  '≠': 'not equal to',
  // Powers and roots.
  'x²': 'squared',
  'xⁿ': 'power',
  '√': 'square root',
  'ⁿ√': 'root',
  // Functions.
  'sin': 'sine',
  'cos': 'cosine',
  'tan': 'tangent',
  'asin': 'inverse sine',
  'acos': 'inverse cosine',
  'atan': 'inverse tangent',
  'sinh': 'hyperbolic sine',
  'cosh': 'hyperbolic cosine',
  'tanh': 'hyperbolic tangent',
  'asinh': 'inverse hyperbolic sine',
  'acosh': 'inverse hyperbolic cosine',
  'atanh': 'inverse hyperbolic tangent',
  'log': 'log',
  'ln': 'natural log',
  'logᵣ': 'log to a base',
  '|x|': 'absolute value',
  '!': 'factorial',
  'ⁿPᵣ': 'permutations',
  'ⁿCᵣ': 'combinations',
  // Calculus.
  'd/dx': 'derivative',
  'd/dx|ₐ': 'derivative at a point',
  '∑': 'sum',
  '∏': 'product',
  '∫': 'integral',
  '∫ₐᵇ': 'definite integral',
  // Symbols and constants.
  'i': 'i, imaginary unit',
  'z̲': 'z, complex variable',
  'c₀': 'speed of light',
  'c₀ (speed of light)': 'speed of light',
  'ε₀': 'permittivity of free space',
  'ε₀ (permittivity)': 'permittivity of free space',
  'μ₀': 'permeability of free space',
  'μ₀ (permeability)': 'permeability of free space',
  'e⁻ (elementary charge)': 'elementary charge',
  // The whole-document keys.
  '⌧': 'clear all',
  '⎌': 'undo',
  '⇪': 'export',
  'ⓘ': 'help',
  '☰': 'settings',
};

/// Greek letters by name, for the coordinate keys and any face built on one.
const Map<String, String> _greekNames = <String, String>{
  'π': 'pi',
  'θ': 'theta',
  'φ': 'phi',
  'ρ': 'rho',
  'ε': 'epsilon',
  'μ': 'mu',
};

/// What a screen reader says for a key whose face is [face].
String spokenKeyLabel(String face) {
  final String? known = _spokenFaces[face];
  if (known != null) return known;
  // A unit vector is a letter under a combining circumflex: x̂, θ̂.
  if (face.length == 2 && face.codeUnitAt(1) == 0x0302) {
    return 'unit vector ${_greekNames[face[0]] ?? face[0]}';
  }
  return _greekNames[face] ?? face;
}

// creating Stateless Widget for buttons
class MyButton extends StatelessWidget {
  // declaring variables
  final dynamic color;
  final dynamic textColor;
  final String buttonText;
  final dynamic buttontapped;
  final double fontSize;
  final bool mirror;
  final double borderRadius;

  /// What a screen reader says for this key, where its face alone does not
  /// tell it (undo and redo share one glyph). Otherwise [spokenKeyLabel].
  final String? semanticLabel;

  //Constructor
  const MyButton({
    super.key,
    this.color,
    this.textColor,
    required this.buttonText,
    this.buttontapped,
    this.fontSize = 22,
    this.mirror = false,
    this.borderRadius = 0,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Only depend on the three settings this button actually uses, so
    // unrelated settings changes (precision, theme, font, ...) don't rebuild
    // every keypad button.
    final (
      bool hapticEnabled,
      double settingsBorderRadius,
      double buttonSpacing,
    ) = context.select<SettingsProvider, (bool, double, double)>(
      (s) => (s.hapticFeedback, s.borderRadius, s.buttonSpacing),
    );
    final double effectiveBorderRadius =
        borderRadius == 0 ? settingsBorderRadius : borderRadius;
    final double outerPadding = buttonSpacing / 2;

    void press() {
      // The lightest tick there is. Every key press makes one, so it should
      // say "pressed" and nothing more: a heavy thud on every digit made
      // typing feel like work.
      if (hapticEnabled) {
        HapticFeedback.selectionClick();
      }
      if (buttontapped != null) {
        buttontapped();
      }
    }

    // 2. Create the label separately for clarity (see [keyLabel]).
    Widget textWidget = keyLabel(
      context,
      buttonText,
      color: textColor,
      fontSize: fontSize,
    );

    // 3. If mirror is true, wrap the text in a Transform
    if (mirror) {
      textWidget = Transform.scale(
        scaleX: -1, // This flips the widget horizontally
        child: textWidget,
      );
    }
    // One node per key, read as what the key does rather than as its glyph,
    // and pressed by the screen reader's double tap as by a finger.
    return Semantics(
      button: true,
      enabled: buttontapped != null,
      label: semanticLabel ?? spokenKeyLabel(buttonText),
      onTap: buttontapped == null ? null : press,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.all(outerPadding),
        child: Container(
          decoration: BoxDecoration(
            // IMPORTANT: borderRadius here must match ClipRRect to make the shadow curved
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), // Shadow color
                blurRadius: 2, // Softness
                spreadRadius: 0, // Size
                offset: Offset(0, 0), // Position (x, y)
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            child: Material(
              color: color,
              child: InkWell(
                onTap: press,
                splashColor: Colors.black.withValues(alpha: 0.2),
                highlightColor: Colors.white.withValues(alpha: 0.1),
                // child: Container(
                // Remove color here since Material has it now
                child: Center(child: textWidget),
                // ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
