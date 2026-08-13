import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/settings_provider.dart';

/// Menu item data for the popup menu
class CalcMenuItem {
  final String label;
  final VoidCallback onTap;

  const CalcMenuItem({required this.label, required this.onTap});
}

/// A button with long-press popup menu functionality.
/// Implements drag-to-select behavior.
class PopupMenuCalcButton extends StatefulWidget {
  final String buttonText;
  final VoidCallback? onTap;
  final List<CalcMenuItem> menuItems;
  final Color color;
  final Color textColor;
  final double fontSize;
  final bool hasIndicator;
  final Color? indicatorColor;
  final Color? menuBackgroundColor;
  final Color? separatorColor;

  const PopupMenuCalcButton({
    super.key,
    required this.buttonText,
    this.onTap,
    required this.menuItems,
    this.color = Colors.white,
    this.textColor = Colors.black,
    this.fontSize = 22,
    this.hasIndicator = true,
    this.indicatorColor,
    this.menuBackgroundColor,
    this.separatorColor,
    this.borderRadius = 0.0,
  });

  final double borderRadius;

  @override
  State<PopupMenuCalcButton> createState() => _PopupMenuCalcButtonState();
}

class _PopupMenuCalcButtonState extends State<PopupMenuCalcButton> {
  OverlayEntry? _overlayEntry;
  final ValueNotifier<int?> _highlightedIndex = ValueNotifier(null);
  bool _isPressed = false;

  double _effectiveBorderRadius(SettingsProvider settings) {
    return widget.borderRadius == 0
        ? settings.borderRadius
        : widget.borderRadius;
  }

  Widget _buildIndicatorDot() {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: widget.indicatorColor ?? widget.textColor.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
    );
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Size size = renderBox.size;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    // Menu styling
    // Menu styling
    const double itemWidth = 60.0;
    const double itemHeight = 60.0;
    const double separatorWidth = 1.0;

    final double totalWidth =
        (widget.menuItems.length * itemWidth) +
        ((widget.menuItems.length - 1) * separatorWidth) +
        16.0; // padding

    // Position above the button, centered horizontally if possible
    double left = position.dx + (size.width / 2) - (totalWidth / 2);
    // Clamp to screen edges
    final double screenWidth = MediaQuery.of(context).size.width;
    if (left < 8) left = 8;
    if (left + totalWidth > screenWidth - 8) {
      left = screenWidth - totalWidth - 8;
    }

    final double top = position.dy - itemHeight - 12; // 12px above button

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: top,
          left: left,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white, // Force white background
                borderRadius: BorderRadius.circular(
                  _effectiveBorderRadius(settings),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < widget.menuItems.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: separatorWidth,
                        height: itemHeight,
                        color:
                            widget.separatorColor ??
                            Colors.grey.withValues(alpha: 0.3),
                      ),
                    ValueListenableBuilder<int?>(
                      valueListenable: _highlightedIndex,
                      builder: (context, highlightedIdx, child) {
                        final isHighlighted = highlightedIdx == i;
                        return Container(
                          width: itemWidth,
                          height: itemHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isHighlighted
                                    ? Colors.black.withValues(
                                      alpha: 0.1,
                                    ) // Better highlight
                                    : Colors.transparent,
                            borderRadius: BorderRadius.zero, // Square highlight
                          ),
                          child: Text(
                            widget.menuItems[i].label.split(' ').first,
                            style: TextStyle(
                              color:
                                  widget.separatorColor != null
                                      ? (Theme.of(context).brightness ==
                                              Brightness.light
                                          ? Colors.black
                                          : Colors
                                              .black) // Force black text on white bg
                                      : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _highlightedIndex.value = null;
  }

  void _updateHighlight(Offset globalPosition) {
    if (_overlayEntry == null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Size size = renderBox.size;
    final Offset buttonPosition = renderBox.localToGlobal(Offset.zero);

    const double itemWidth = 60.0;
    const double itemHeight = 60.0;
    const double separatorWidth = 1.0;

    final double totalWidth =
        (widget.menuItems.length * itemWidth) +
        ((widget.menuItems.length - 1) * separatorWidth) +
        16.0;

    final double screenWidth = MediaQuery.of(context).size.width;
    double left = buttonPosition.dx + (size.width / 2) - (totalWidth / 2);
    if (left < 8) left = 8;
    if (left + totalWidth > screenWidth - 8) {
      left = screenWidth - totalWidth - 8;
    }

    final double menuTop = buttonPosition.dy - itemHeight - 12;
    final double menuBottom = menuTop + itemHeight + 12;

    if (globalPosition.dy < menuTop - 20 ||
        globalPosition.dy > menuBottom + 50) {
      if (_highlightedIndex.value != null) {
        _highlightedIndex.value = null;
        HapticFeedback.lightImpact();
      }
      return;
    }

    double currentX = left + 8;
    int? newIndex;

    for (int i = 0; i < widget.menuItems.length; i++) {
      if (globalPosition.dx >= currentX &&
          globalPosition.dx < currentX + itemWidth) {
        newIndex = i;
        break;
      }
      currentX += itemWidth + separatorWidth;
    }

    if (newIndex != _highlightedIndex.value) {
      if (newIndex != null) HapticFeedback.selectionClick();
      _highlightedIndex.value = newIndex;
    }
  }

  /// Scales the label down by its length, matching MyButton.
  double get _fittedFontSize {
    final int n = widget.buttonText.characters.length;
    if (n <= 2) return widget.fontSize;
    if (n == 3) return widget.fontSize * 0.66;
    if (n == 4) return widget.fontSize * 0.50;
    return widget.fontSize * 0.42;
  }

  @override
  Widget build(BuildContext context) {
    // Only depend on the settings this button actually uses so unrelated
    // settings changes don't rebuild every popup button.
    final (bool haptic, double sBorderRadius, double buttonSpacing) = context
        .select<SettingsProvider, (bool, double, double)>(
          (s) => (s.hapticFeedback, s.borderRadius, s.buttonSpacing),
        );
    final effectiveBorderRadius =
        widget.borderRadius == 0 ? sBorderRadius : widget.borderRadius;

    return Padding(
      padding: EdgeInsets.all(buttonSpacing / 2),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap?.call();
          if (haptic) {
            HapticFeedback.lightImpact();
          }
        },
        onTapCancel: () => setState(() => _isPressed = false),
        onLongPressStart: (details) {
          HapticFeedback.mediumImpact();
          setState(() => _isPressed = true);
          _showOverlay();
          _updateHighlight(details.globalPosition);
        },
        onLongPressMoveUpdate: (details) {
          _updateHighlight(details.globalPosition);
        },
        onLongPressEnd: (details) {
          setState(() => _isPressed = false);
          final index = _highlightedIndex.value;
          _removeOverlay();
          if (index != null) {
            widget.menuItems[index].onTap();
            if (haptic) {
              HapticFeedback.heavyImpact();
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                spreadRadius: 0,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            child: Material(
              color: widget.color,
              child: Container(
                color:
                    _isPressed
                        ? Colors.black.withValues(alpha: 0.1)
                        : Colors.transparent,
                child: Stack(
                  children: [
                    Center(
                      // Same length-based fitting as MyButton: these keys are
                      // only ~36dp wide and carry the longest labels on the
                      // keypad ("asin", "acos", "atan").
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.buttonText,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: widget.textColor,
                              fontSize: _fittedFontSize,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.hasIndicator)
                      (effectiveBorderRadius > 10)
                          ? Positioned(
                            bottom: 4,
                            left: 0,
                            right: 0,
                            child: Center(child: _buildIndicatorDot()),
                          )
                          : Positioned(
                            bottom: 4,
                            right: 4,
                            child: _buildIndicatorDot(),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
