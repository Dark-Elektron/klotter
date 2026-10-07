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
    return Padding(
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
              onTap: () {
                // The lightest tick there is. Every key press makes one,
                // so it should say "pressed" and nothing more: a heavy
                // thud on every digit made typing feel like work.
                if (hapticEnabled) {
                  HapticFeedback.selectionClick();
                }
                if (buttontapped != null) {
                  buttontapped();
                }
              },
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
    );
  }
}
