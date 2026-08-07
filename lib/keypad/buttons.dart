import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/settings_provider.dart';

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
    final (bool hapticEnabled, double settingsBorderRadius, double buttonSpacing) =
        context.select<SettingsProvider, (bool, double, double)>(
      (s) => (s.hapticFeedback, s.borderRadius, s.buttonSpacing),
    );
    final double effectiveBorderRadius =
        borderRadius == 0 ? settingsBorderRadius : borderRadius;
    final double outerPadding = buttonSpacing / 2;

    // 2. Create the text widget separately for clarity
    //
    // klotter's keys are only ~36dp wide, so multi-character labels like
    // "asin", "acos" and "logn" do not fit at the nominal size. Shrink the
    // type to the label's length rather than clipping or wrapping it — the
    // glyphs stay centred and the key keeps its full touch target.
    final int labelLength = buttonText.characters.length;
    final double fittedFontSize =
        labelLength <= 2
            ? fontSize
            : labelLength == 3
            ? fontSize * 0.66
            : labelLength == 4
            ? fontSize * 0.50
            : fontSize * 0.42;

    Widget textWidget = Text(
      buttonText,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: textColor,
        fontSize: fittedFontSize,
        height: 1.0,
      ),
    );

    // Keep a little air either side so four-letter labels like "asin" do not
    // run edge to edge, and scale down further if the label still cannot fit
    // (large text-scale settings, narrow devices).
    textWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(fit: BoxFit.scaleDown, child: textWidget),
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
                if (hapticEnabled) {
                  HapticFeedback.heavyImpact();
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
