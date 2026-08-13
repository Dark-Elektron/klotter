import 'package:flutter/material.dart';

/// Animated swipe gesture hint - now responsive
class SwipeGestureAnimation extends StatefulWidget {
  final bool swipeLeft;
  final Color color;

  const SwipeGestureAnimation({
    super.key,
    required this.swipeLeft,
    this.color = Colors.blue,
  });

  @override
  State<SwipeGestureAnimation> createState() => _SwipeGestureAnimationState();
}

class _SwipeGestureAnimationState extends State<SwipeGestureAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use available width, with max of 180 and min of 120
        final width = constraints.maxWidth.clamp(120.0, 180.0);
        final height = 60.0;

        return SizedBox(
          width: width,
          height: height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: SwipeGesturePainter(
                  progress: _controller.value,
                  swipeLeft: widget.swipeLeft,
                  color: widget.color,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class SwipeGesturePainter extends CustomPainter {
  final double progress;
  final bool swipeLeft;
  final Color color;

  SwipeGesturePainter({
    required this.progress,
    required this.swipeLeft,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final startX = swipeLeft ? size.width * 0.75 : size.width * 0.25;
    final endX = swipeLeft ? size.width * 0.25 : size.width * 0.75;
    final currentX =
        startX + (endX - startX) * Curves.easeInOut.transform(progress);
    final centerY = size.height / 2;

    // Draw trail
    final trailPaint =
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;

    final trailPath = Path();
    trailPath.moveTo(startX, centerY);
    trailPath.lineTo(currentX, centerY);
    canvas.drawPath(trailPath, trailPaint);

    // Draw dots along trail
    const dotCount = 4;
    for (int i = 0; i < dotCount; i++) {
      final dotProgress = (progress - i * 0.1).clamp(0.0, 1.0);
      if (dotProgress > 0) {
        final dotX =
            startX + (endX - startX) * Curves.easeInOut.transform(dotProgress);
        final dotOpacity = (1.0 - i * 0.2) * (1.0 - progress * 0.5);
        canvas.drawCircle(
          Offset(dotX, centerY),
          3,
          Paint()..color = color.withValues(alpha: dotOpacity.clamp(0.0, 1.0)),
        );
      }
    }

    // Draw hand circle
    final handOpacity = progress < 0.8 ? 1.0 : (1.0 - (progress - 0.8) * 5);
    canvas.drawCircle(
      Offset(currentX, centerY),
      14,
      Paint()..color = color.withValues(alpha: handOpacity.clamp(0.0, 1.0)),
    );

    // Draw finger icon
    final iconPaint =
        Paint()
          ..color = Colors.white.withValues(
            alpha: handOpacity.clamp(0.0, 1.0) * 0.9,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    final fingerPath = Path();
    fingerPath.moveTo(currentX, centerY - 5);
    fingerPath.lineTo(currentX, centerY + 3);
    canvas.drawPath(fingerPath, iconPaint);

    // Draw arrow
    final arrowX = swipeLeft ? size.width * 0.12 : size.width * 0.88;
    final arrowPaint =
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;

    final arrowPath = Path();
    if (swipeLeft) {
      arrowPath.moveTo(arrowX + 10, centerY - 8);
      arrowPath.lineTo(arrowX, centerY);
      arrowPath.lineTo(arrowX + 10, centerY + 8);
    } else {
      arrowPath.moveTo(arrowX - 10, centerY - 8);
      arrowPath.lineTo(arrowX, centerY);
      arrowPath.lineTo(arrowX - 10, centerY + 8);
    }
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant SwipeGesturePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Spotlight painter - creates dark overlay with transparent cutout
class SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double padding;

  SpotlightPainter({required this.targetRect, this.padding = 8});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.75);

    final fullPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutRect = RRect.fromRectAndRadius(
      targetRect.inflate(padding),
      const Radius.circular(12),
    );

    final cutoutPath = Path()..addRRect(cutoutRect);

    final combinedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      cutoutPath,
    );

    canvas.drawPath(combinedPath, paint);

    // Draw highlight border
    final borderPaint =
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawRRect(cutoutRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}
