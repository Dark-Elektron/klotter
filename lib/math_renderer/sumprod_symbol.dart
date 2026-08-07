import 'dart:math' as math;
import 'package:flutter/material.dart';

enum SumProdType { sum, product }

class SumProdSymbol extends StatelessWidget {
  final SumProdType type;
  final double fontSize;
  final Color color;

  const SumProdSymbol({
    super.key,
    required this.type,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final width = fontSize * 0.9;
    final height = fontSize * 1.4;
    return CustomPaint(
      size: Size(width, height),
      painter: _SumProdPainter(
        type: type,
        color: color,
        strokeWidth: math.max(1.6, fontSize * 0.08),
      ),
    );
  }
}

class _SumProdPainter extends CustomPainter {
  final SumProdType type;
  final Color color;
  final double strokeWidth;

  _SumProdPainter({
    required this.type,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    if (type == SumProdType.sum) {
      final path = Path();
      final left = 0.0;
      final right = size.width;
      final top = 0.0;
      final bottom = size.height;
      final midY = size.height * 0.5;

      path.moveTo(right, top);
      path.lineTo(left, top);
      path.lineTo(right * 0.55, midY);
      path.lineTo(left, bottom);
      path.lineTo(right, bottom);

      canvas.drawPath(path, paint);
    } else {
      final left = 0.0;
      final right = size.width;
      final top = 0.0;
      final bottom = size.height;

      canvas.drawLine(Offset(left, top), Offset(right, top), paint);
      canvas.drawLine(Offset(left, bottom), Offset(right, bottom), paint);
      canvas.drawLine(Offset(left, top), Offset(left, bottom), paint);
      canvas.drawLine(Offset(right, top), Offset(right, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SumProdPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

