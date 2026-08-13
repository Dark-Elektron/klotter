import 'package:flutter/material.dart';

import 'plot_theme.dart';

/// One line of a trace readout.
typedef ReadoutLine = ({Color color, String text, bool bold});

/// How a coordinate is written in a readout.
///
/// Fixed to three decimals over the range a plot window normally covers, and
/// exponential only where that would be unreadable — a value of 1e-9 printed
/// as "0.000" says nothing, and 120000 as "120000.000" is noise.
String formatReadout(double v) {
  if (!v.isFinite) return '—';
  if (v.abs() >= 1e5 || (v != 0 && v.abs() < 1e-3)) {
    return v.toStringAsExponential(3);
  }
  return v.toStringAsFixed(3);
}

/// Draw the small boxed readout a trace puts on the plot.
///
/// Shared by the 2D and 3D traces so the two look and behave alike: same
/// padding, same corner, same flip away from the right edge. [anchorX] is the
/// point being reported — the box sits beside it, and moves to its other side
/// rather than running off the plot.
void drawReadoutBox(
  Canvas canvas,
  Size size,
  PlotThemeData theme,
  List<ReadoutLine> lines, {
  required double anchorX,
  double top = 8,
}) {
  if (lines.isEmpty) return;

  final List<TextPainter> painters = <TextPainter>[
    for (final ReadoutLine line in lines)
      TextPainter(
        text: TextSpan(
          text: line.text,
          style: TextStyle(
            color: line.color,
            fontSize: 11,
            fontWeight: line.bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
  ];

  const double pad = 6;
  final double w =
      painters.map((t) => t.width).reduce((a, b) => a > b ? a : b) + pad * 2;
  final double h =
      painters.map((t) => t.height).reduce((a, b) => a + b) + pad * 2;

  // Flip to the other side of the marker near the right edge.
  double left = anchorX + 10;
  if (left + w > size.width - 4) left = anchorX - 10 - w;
  left = left.clamp(4.0, (size.width - w - 4).clamp(4.0, double.infinity));

  final RRect box = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, top, w, h),
    const Radius.circular(4),
  );
  canvas.drawRRect(
    box,
    Paint()..color = theme.colorbarBorder.withValues(alpha: 0.12),
  );
  canvas.drawRRect(
    box,
    Paint()
      ..color = theme.colorbarBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );

  double y = top + pad;
  for (final TextPainter t in painters) {
    t.paint(canvas, Offset(left + pad, y));
    y += t.height;
  }
}
