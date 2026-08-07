import 'package:flutter/material.dart';
import 'walkthrough_service.dart';
import 'walkthrough_steps.dart';
import 'walkthrough_widgets.dart';

class WalkthroughOverlay extends StatelessWidget {
  final WalkthroughService walkthroughService;
  final Map<String, GlobalKey> targetKeys;
  final Widget child;

  const WalkthroughOverlay({
    super.key,
    required this.walkthroughService,
    required this.targetKeys,
    required this.child,
  });

  // ============== ADJUSTMENT CONSTANTS ==============
  static const double _spotlightPadding = 8.0;
  static const double _tooltipMargin = 16.0;
  static const double _tooltipPadding = 18.0;
  static const double _overlayDarkness = 0.75;
  static const double _swipeAreaDimness = 0.15;
  static const double _tooltipOffsetFromTarget = 16.0;

  // ============== MOBILE ADJUSTMENTS ==============
  static const Map<String, Rect> _mobileSpotlightAdjustments = {
    'ans_index': Rect.fromLTWH(8, 0, -15, 2),
    'expression_area': Rect.fromLTWH(10, 8, -20, -10),
    'result_area': Rect.fromLTWH(10, 4, -20, -10),
    'number_keypad': Rect.fromLTWH(10, 5, -20, -10),
    'scientific_keypad': Rect.fromLTWH(10, 5, -20, -10),
    'extras_keypad': Rect.fromLTWH(10, 5, -20, -10),
  };

  // ============== TABLET/LANDSCAPE ADJUSTMENTS ==============
  static const Map<String, Rect> _tabletSpotlightAdjustments = {
    'ans_index': Rect.fromLTWH(8, 0, -15, 2),
    'expression_area': Rect.fromLTWH(10, 8, -20, -10),
    'result_area': Rect.fromLTWH(10, 4, -20, -10),
    'tablet_keypads_visible': Rect.fromLTWH(10, 5, -20, -10),
    'tablet_extras_visible': Rect.fromLTWH(10, 5, -20, -10),
  };

  // ============== MOBILE TOOLTIP OFFSETS ==============
  static const Map<String, double> _mobileTooltipOffsets = {
    'ans_index': 25.0,
    'command_button': 12.0,
    'basic_keypad': 12.0,
    'expression_area': 20.0,
    'result_area': 20.0,
    'number_keypad': 25.0,
    'scientific_keypad': 25.0,
    'extras_keypad': 25.0,
    'settings_button': 12.0,
  };

  // ============== TABLET TOOLTIP OFFSETS ==============
  static const Map<String, double> _tabletTooltipOffsets = {
    'ans_index': 25.0,
    'command_button': 12.0,
    'basic_keypad': 12.0,
    'expression_area': 20.0,
    'result_area': 20.0,
    'tablet_keypads_visible': 25.0,
    'tablet_extras_visible': 25.0,
    'tablet_settings_button': 12.0,
  };

  Map<String, Rect> get _spotlightAdjustments {
    return walkthroughService.isTabletMode
        ? _tabletSpotlightAdjustments
        : _mobileSpotlightAdjustments;
  }

  Map<String, double> get _tooltipOffsets {
    return walkthroughService.isTabletMode
        ? _tabletTooltipOffsets
        : _mobileTooltipOffsets;
  }

  // ============== BUILD METHODS ==============

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: walkthroughService,
      builder: (context, _) {
        final shouldShow =
            walkthroughService.isActive && walkthroughService.isInitialized;

        return Stack(
          children: [
            child,
            if (shouldShow)
              Material(
                type: MaterialType.transparency,
                child: _buildOverlay(context),
              ),
          ],
        );
      },
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final step = walkthroughService.currentStepData;
    final screenSize = MediaQuery.of(context).size;
    final isSwipeStep =
        step.requiresAction &&
        (step.requiredAction == WalkthroughAction.swipeLeft ||
            step.requiredAction == WalkthroughAction.swipeRight);

    Rect? targetRect = _getTargetRect(step.id);

    return Stack(
      children: [
        // Overlay background
        if (isSwipeStep)
          _buildSwipeStepOverlay(context, screenSize)
        else
          _buildNormalOverlay(context, screenSize, targetRect, step.id),

        // Tooltip
        _buildTooltip(context, step, targetRect, screenSize),

        // Skip button with persistent hint
        _buildSkipButtonWithHint(context),

        // Progress indicator
        _buildProgressIndicator(context),
      ],
    );
  }

  String _getTargetKeyId(String stepId) {
    const tabletTargetMappings = {
      'tablet_keypads_visible': 'main_keypad_area',
      'tablet_swipe_left_extras': 'main_keypad_area',
      'tablet_extras_visible': 'main_keypad_area',
      'tablet_swipe_right_back': 'main_keypad_area',
      'tablet_settings_button': 'settings_button',
    };

    return tabletTargetMappings[stepId] ?? stepId;
  }

  Rect? _getTargetRect(String stepId) {
    final targetKeyId = _getTargetKeyId(stepId);
    final targetKey = targetKeys[targetKeyId];

    if (targetKey?.currentContext == null) return null;

    final RenderBox? box =
        targetKey!.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    final position = box.localToGlobal(Offset.zero);
    Rect rect = position & box.size;

    final adjustments = _spotlightAdjustments;
    if (adjustments.containsKey(stepId)) {
      final adj = adjustments[stepId]!;
      rect = Rect.fromLTWH(
        rect.left + adj.left,
        rect.top + adj.top,
        rect.width + adj.width,
        rect.height + adj.height,
      );
    }

    return rect;
  }

  Widget _buildSwipeStepOverlay(BuildContext context, Size screenSize) {
    Rect? keypadRect;

    final keypadKey = targetKeys['main_keypad_area'];
    if (keypadKey?.currentContext != null) {
      final RenderBox? box =
          keypadKey!.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        final position = box.localToGlobal(Offset.zero);
        keypadRect = position & box.size;
      }
    }

    final keypadTop = keypadRect?.top ?? screenSize.height * 0.50;
    final adjustedKeypadTop = keypadTop - 5;

    return Column(
      children: [
        GestureDetector(
          onTap: () {},
          child: Container(
            height: adjustedKeypadTop,
            width: screenSize.width,
            color: Colors.black.withValues(alpha: _overlayDarkness),
          ),
        ),
        Expanded(
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: _swipeAreaDimness),
                border: Border(
                  top: BorderSide(
                    color: Colors.amber.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalOverlay(
    BuildContext context,
    Size screenSize,
    Rect? targetRect,
    String stepId,
  ) {
    return GestureDetector(
      onTap: () {},
      child:
          targetRect != null
              ? CustomPaint(
                size: screenSize,
                painter: SpotlightPainter(
                  targetRect: targetRect,
                  padding: _spotlightPadding,
                ),
              )
              : Container(
                color: Colors.black.withValues(alpha: _overlayDarkness),
              ),
    );
  }

  Widget _buildTooltip(
    BuildContext context,
    WalkthroughStep step,
    Rect? targetRect,
    Size screenSize,
  ) {
    final isSwipeStep =
        step.requiresAction &&
        (step.requiredAction == WalkthroughAction.swipeLeft ||
            step.requiredAction == WalkthroughAction.swipeRight);

    final primaryColor = Colors.amber;

    Widget content = Container(
      margin: EdgeInsets.symmetric(horizontal: _tooltipMargin),
      padding: EdgeInsets.all(_tooltipPadding),
      constraints: BoxConstraints(
        maxWidth: screenSize.width - (_tooltipMargin * 2),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSwipeStep)
            Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconForStep(step.id),
                color: primaryColor,
                size: 22,
              ),
            ),
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            step.description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          // Swipe animation and instruction
          if (isSwipeStep) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 140,
              height: 45,
              child: SwipeGestureAnimation(
                swipeLeft: step.requiredAction == WalkthroughAction.swipeLeft,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    step.requiredAction == WalkthroughAction.swipeLeft
                        ? Icons.swipe_left
                        : Icons.swipe_right,
                    color: primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    step.requiredAction == WalkthroughAction.swipeLeft
                        ? 'Swipe LEFT'
                        : 'Swipe RIGHT',
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.keyboard_arrow_down,
              color: primaryColor.withValues(alpha: 0.5),
              size: 24,
            ),
            // BACK BUTTON for swipe steps
            const SizedBox(height: 12),
            if (walkthroughService.currentStep > 0)
              TextButton(
                onPressed: walkthroughService.previousStep,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 14),
                    SizedBox(width: 4),
                    Text('Back', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],

          // Next/Back buttons for non-swipe steps
          if (!step.requiresAction) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (walkthroughService.currentStep > 0)
                  TextButton(
                    onPressed: walkthroughService.previousStep,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 14),
                        SizedBox(width: 4),
                        Text('Back', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                if (walkthroughService.currentStep > 0)
                  const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: walkthroughService.nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 1,
                  ),
                  child: Text(
                    walkthroughService.currentStep ==
                            walkthroughService.steps.length - 1
                        ? 'Get Started!'
                        : 'Next',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    // ============== TOOLTIP POSITIONING ==============

    if (isSwipeStep) {
      Rect? keypadRect;
      final keypadKey = targetKeys['main_keypad_area'];
      if (keypadKey?.currentContext != null) {
        final RenderBox? box =
            keypadKey!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          final position = box.localToGlobal(Offset.zero);
          keypadRect = position & box.size;
        }
      }

      final keypadTop = keypadRect?.top ?? screenSize.height * 0.50;
      const swipeTooltipOffset = 25.0;

      return Positioned(
        left: 0,
        right: 0,
        bottom: screenSize.height - keypadTop + swipeTooltipOffset,
        child: Center(child: content),
      );
    }

    if (step.position == TooltipPosition.center || targetRect == null) {
      return Center(child: content);
    }

    final offsets = _tooltipOffsets;
    final offset = offsets[step.id] ?? _tooltipOffsetFromTarget;

    if (step.id == 'command_button' ||
        step.id == 'settings_button' ||
        step.id == 'tablet_settings_button') {
      return Positioned(
        left: 0,
        right: 0,
        bottom: screenSize.height - targetRect.top + offset,
        child: Center(child: content),
      );
    }

    double? top, bottom;
    if (step.position == TooltipPosition.above) {
      bottom = screenSize.height - targetRect.top + offset;
    } else {
      top = targetRect.bottom + offset;
    }

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      bottom: bottom,
      child: Center(child: content),
    );
  }

  Widget _buildSkipButtonWithHint(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Skip button
          TextButton.icon(
            onPressed: walkthroughService.skipWalkthrough,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Skip'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.amberAccent,
              backgroundColor: Colors.black45,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Persistent hint bubble
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Colors.amber.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'You can restart this tutorial anytime. Swipe left on the keypad to find Settings \u2630',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 14,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${walkthroughService.currentStep + 1}/${walkthroughService.steps.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  IconData _getIconForStep(String stepId) {
    switch (stepId) {
      case 'expression_area':
        return Icons.calculate_outlined;
      case 'result_area':
        return Icons.auto_awesome;
      case 'ans_index':
        return Icons.tag;
      case 'basic_keypad':
        return Icons.dialpad;
      case 'command_button':
        return Icons.add_box_outlined;
      case 'number_keypad':
        return Icons.grid_view;
      case 'scientific_keypad':
        return Icons.science_outlined;
      case 'extras_keypad':
        return Icons.more_horiz;
      case 'settings_button':
      case 'tablet_settings_button':
        return Icons.settings;
      case 'tablet_keypads_visible':
        return Icons.view_column_outlined;
      case 'tablet_extras_visible':
        return Icons.more_horiz;
      case 'complete':
        return Icons.check_circle_outline;
      default:
        return Icons.touch_app;
    }
  }
}
