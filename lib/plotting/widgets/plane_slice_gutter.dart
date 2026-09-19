import 'package:flutter/material.dart';

import '../models/plane_slice.dart';
import '../utils/plot_theme.dart';

/// The strip beside a 2D plot that says which plane of a 3D plot it is showing,
/// and slides it.
///
/// Laid over the plot, not carved out of it. Reserving the width was tried
/// first and read wrong: the control column on the other side sits on top of
/// the grid, which runs on underneath it to the edge of the panel, so a strip
/// that pushed the grid away instead left the plot looking cropped down one
/// side and lopsided against the other.
///
/// It still keeps out of the corners' way rather than joining them. The mode
/// label holds the top leading corner, the u and v chips and the complex
/// toggles the bottom leading one, and each of those works out its own offset
/// from which of the others happen to be showing. Rather than add a fourth to
/// that pile, this stands off by however much they take — see [footInset].
class PlaneSliceGutter extends StatelessWidget {
  const PlaneSliceGutter({
    super.key,
    required this.slice,
    required this.extent,
    required this.theme,
    required this.chosen,
    required this.buttonSize,
    required this.onChanged,
    required this.onSlideStart,
    required this.onSlideEnd,
    required this.onAxisTapped,
    this.bottomInset = 0,
    this.footInset = 0,
  });

  /// How much width the strip takes off the plot.
  static const double width = 46;

  /// How long the slider is at most.
  ///
  /// Short, and nowhere near the height of the plot. Full height read as a
  /// scrollbar — as though it moved the view rather than the plane — and a
  /// thumb with that much track under it moves the plane a long way for a
  /// small drag. It is capped rather than fixed so a short panel shrinks it
  /// instead of overflowing.
  static const double sliderLength = 132;

  /// The plane on show.
  final PlaneSlice slice;

  /// How far the held variable runs either side of zero, from the 3D box.
  final double extent;

  final PlotThemeData theme;

  /// Whether the reader has chosen this plane, rather than it being the one
  /// this kind of plot has always opened on.
  ///
  /// Lights the button the way every other control here lights when it is
  /// doing something, so the strip says at a glance whether the view has been
  /// moved off its default.
  final bool chosen;

  /// The side of the square buttons the rest of the plot uses.
  final double buttonSize;

  /// Called continuously as the plane is slid.
  final ValueChanged<double> onChanged;

  /// Bracket the slide, so the plot can sample coarsely while it is moving and
  /// go back to full detail once it stops.
  final VoidCallback onSlideStart;
  final VoidCallback onSlideEnd;

  /// Called when the reader asks for a different plane.
  final VoidCallback onAxisTapped;

  /// How much of the bottom is covered by the expression rows, so the strip
  /// ends where the visible plot does rather than running on underneath them.
  final double bottomInset;

  /// How much of the strip's foot the parameter knobs and the complex toggles
  /// are already using.
  ///
  /// They are positioned against the panel rather than against the plot, so
  /// they come down over this strip — which is what had them sitting on the
  /// button and covering the track. Rather than move them, the strip stands
  /// off by however much they take, so the button rides up when they appear
  /// and drops back when they go.
  final double footInset;

  @override
  Widget build(BuildContext context) {
    final double span = extent > 0 ? extent : 1;
    final double value = slice.offset.clamp(-span, span);

    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottomInset + footInset),
      child: SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints room) {
            // What is left after the knobs below have had theirs. On a short
            // cell with both knobs showing there is barely any, so the parts
            // go in order of what they are worth: the button names the plane
            // and has to stay, the slider can shrink to a stub, and the number
            // is the first thing to go rather than the thing that overflows.
            final bool roomForValue = room.maxHeight >= _valueNeeds;

            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  // Vertical, because the plane it moves is one you think of as
                  // going up and down through the box.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: sliderLength),
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // Where the plane sits at zero, which is the one position
                        // worth being able to find without reading the number.
                        // Behind the slider and wider than its track, so the ends
                        // show either side of it like a tick.
                        Container(
                          width: 16,
                          height: 2,
                          color: theme.controlIdle,
                        ),
                        RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 13,
                              ),
                              // One colour both sides of the thumb. A filled track
                              // says the value is an amount measured up from the
                              // bottom, and this one is not — it runs either side
                              // of zero, and the fill drew most attention to the
                              // end furthest from where the plane actually is.
                              activeTrackColor: theme.controlOutline,
                              inactiveTrackColor: theme.controlOutline,
                              thumbColor: theme.controlActive,
                            ),
                            child: Slider(
                              min: -span,
                              max: span,
                              value: value,
                              onChanged: onChanged,
                              onChangeStart: (_) => onSlideStart(),
                              onChangeEnd: (_) => onSlideEnd(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Where the plane currently sits. The number matters as much as
                // the control: a slice with no value on it is the state this whole
                // strip exists to get rid of.
                //
                // Backed, because the strip lies over the plot rather than beside
                // it — bare grey digits on a grid line are unreadable, and every
                // other control here carries the same fill for the same reason.
                if (roomForValue) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Text(
                      _format(value),
                      style: TextStyle(color: theme.label, fontSize: 10),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // Which variable is held. Tapping moves to the next one, so all
                // three are two taps away at most. Built like the complex toggles
                // rather than in its own style: same square, same fill, same
                // border, so it reads as one of the plot's controls.
                Semantics(
                  button: true,
                  label: 'Slice plane ${slice.axis.label}, tap to change',
                  child: GestureDetector(
                    onTap: onAxisTapped,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: buttonSize,
                      height: buttonSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            chosen
                                ? theme.controlFill
                                : Colors.black.withValues(alpha: 0.5),
                        border: Border.all(
                          color:
                              chosen
                                  ? theme.controlActive
                                  : theme.controlOutline,
                          width: chosen ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        slice.axis.label,
                        style: TextStyle(
                          color:
                              chosen ? theme.controlActive : theme.controlIdle,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  /// How much height the strip needs before the number is worth keeping.
  ///
  /// The button, the gap under the number, the number itself and the foot,
  /// plus enough track left over for the slider to still be a slider.
  static const double _valueNeeds = 40 + 4 + 16 + 8 + 22;

  /// Short enough to fit the strip, and without a trailing `.00` on a round
  /// number, which is where the plane spends most of its time.
  static String _format(double v) {
    if (v == 0) return '0';
    final double r = (v * 100).roundToDouble() / 100;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
  }
}
