part of 'plot_3d_painter.dart';

/// Drawn over the plot: the trace marker and its readout, and the colorbar.
extension Plot3DOverlays on Plot3DPainter {
  /// Smooth colorbar with labelled ticks.
  ///
  /// The strip matches the surface: both are the continuous ramp, so a colour
  /// on the plot can be read back against the bar directly. Ticks are spaced
  /// rather than min/max only, which is what makes an intermediate value
  /// readable without counting bands.
  /// Mark the point a long-press picked out of the scene, and name it.
  ///
  /// Drawn last and unoccluded: the point is on the surface the user touched,
  /// so hiding it behind that surface would defeat the purpose. The ring is
  /// hollow for the same reason the 2D one is — the surface stays visible
  /// underneath it.
  void _drawTrace3D(Canvas canvas, Size size) {
    final SurfaceHit? hit = tracePoint;
    if (hit == null) return;
    if (!hit.x.isFinite || !hit.y.isFinite || !hit.z.isFinite) return;

    final Offset at = Point3D(hit.x * scaleX, hit.y * scaleY, hit.z * scaleZ)
        .rotateZ(rotationZ)
        .rotateX(rotationX)
        .project(_focalLength, size, _panX, _panY);
    if (!at.dx.isFinite || !at.dy.isFinite) return;

    // One neutral marker rather than one tinted to the surface's own ramp.
    // Only ever one point is marked — the one under the finger — so there is
    // nothing to tell apart, and a ramp colour would have to be looked up by
    // the curve's position within its own kind, which is not what
    // [SurfaceHit.curveIndex] counts.
    // Light fill, dark ring. The marker lands anywhere on a surface that runs
    // the whole colour ramp, so it cannot borrow a colour from the plot and
    // stay visible; a light dot outlined in the label colour reads against
    // both the dark end of a ramp and the bright end.
    canvas.drawCircle(at, 5, Paint()..color = _theme.boundary);
    canvas.drawCircle(
      at,
      5,
      Paint()
        ..color = _theme.label
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    drawReadoutBox(canvas, size, _theme, <ReadoutLine>[
      (color: _theme.axisX, text: 'x = ${formatReadout(hit.x)}', bold: false),
      (color: _theme.axisY, text: 'y = ${formatReadout(hit.y)}', bold: false),
      (color: _theme.axisZ, text: 'z = ${formatReadout(hit.z)}', bold: false),
      // On a sweep these are the numbers worth having: x, y and z say where
      // the point is, u and v say which part of the sweep put it there.
      if (hit.u case final double u)
        (color: _theme.label, text: 'u = ${formatReadout(u)}', bold: false),
      if (hit.v case final double v)
        (color: _theme.label, text: 'v = ${formatReadout(v)}', bold: false),
    ], anchorX: at.dx);
  }

  /// The value scale, laid along the top of the plot.
  ///
  /// Horizontal and in the top right corner to match 2D, leaving the left
  /// edge to the parameter panels and the top left to the mode label. Ticks
  /// hang below the bar rather than beside it, which is the only arrangement
  /// that keeps the numbers from colliding.
  ///
  /// [stops] is the ramp being labelled and [row] which bar this is, counting
  /// down from the top — several fields on one set of axes each need their own,
  /// exactly as in 2D.
  void _drawColorbar3D(
    Canvas canvas,
    Size size,
    double minVal,
    double maxVal, {
    List<Color>? stops,
    int row = 0,
  }) {
    // The ramp in use unless told otherwise; it is a setting, so it cannot be
    // the parameter's default.
    final List<Color> ramp = stops ?? plotColormapStops(palette);
    final double barWidth = Plot3DPainter._colorbarWidth(size);
    final Rect barRect = Rect.fromLTWH(
      size.width - barWidth - Plot3DPainter._colorbarMarginRight,
      Plot3DPainter._colorbarMarginTop + row * Plot3DPainter._colorbarPitch,
      barWidth,
      Plot3DPainter._colorbarHeight,
    );

    // Left end is the minimum, so it reads like the axis underneath it. Drawn
    // as one gradient rather than a line per pixel, which quantised the ramp
    // to the bar's width in steps and showed as bands.
    canvas.drawRect(
      barRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: ramp,
        ).createShader(barRect),
    );

    canvas.drawRect(
      barRect,
      Paint()
        ..color = _theme.colorbarBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final double span = maxVal - minVal;
    if (!span.isFinite || span <= 0) return;

    // Round values, where they fall, rather than the bar's ends and quarters:
    // those are wherever the data happened to stop, and read as −1.53 and
    // 0.77 instead of −1 and 1.
    final double step = Plot3DPainter._niceStep(span, 4);
    final TextStyle textStyle = TextStyle(
      color: _theme.colorbarText,
      fontSize: 9,
    );
    final Paint tickPaint =
        Paint()
          ..color = _theme.colorbarBorder
          ..strokeWidth = 1;
    double lastRight = double.negativeInfinity;
    for (
      int k = (minVal / step - 1e-9).ceil();
      k * step <= maxVal + span * 1e-9;
      k++
    ) {
      final double value = k * step;
      final double x = barRect.left + (value - minVal) / span * barWidth;

      final TextPainter tp = TextPainter(
        text: TextSpan(text: _formatNumber(value), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Centred under its tick, but held inside the bar's own width, so the
      // first and last numbers are never past its ends — or the screen's.
      final double left = (x - tp.width / 2).clamp(
        barRect.left,
        max(barRect.left, barRect.right - tp.width),
      );
      // A number that would touch its neighbour is left out with its tick.
      if (left < lastRight + 4) continue;
      lastRight = left + tp.width;

      canvas.drawLine(
        Offset(x, barRect.bottom),
        Offset(x, barRect.bottom + 3),
        tickPaint,
      );
      tp.paint(canvas, Offset(left, barRect.bottom + 5));
    }
  }
}
