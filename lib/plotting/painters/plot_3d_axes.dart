part of 'plot_3d_painter.dart';

/// The frame of a 3D plot: the box, the floor grid and its boundary, the axes
/// with their ticks and labels, and keeping labels clear of what they annotate.
extension Plot3DAxes on Plot3DPainter {
  /// Add a world-space line to [scene], cut into depth-varying pieces.
  ///
  /// A line crossing the scene has very different depths at its two ends, so a
  /// single depth cannot say whether a surface passes in front of part of it.
  void _addWorldLineTo(
    _LineSink scene,
    Size size,
    double focalLength,
    Point3D a,
    Point3D b,
    Paint paint, {
    int pieces = 16,
  }) {
    final Rect bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    for (int k = 0; k < pieces; k++) {
      final double t0 = k / pieces;
      final double t1 = (k + 1) / pieces;
      Point3D at(double t) => Point3D(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      ).rotateZ(rotationZ).rotateX(rotationX);

      final Point3D p0 = at(t0);
      final Point3D p1 = at(t1);
      final clipped = _clipLineToRect(
        p0.project(focalLength, size, _panX, _panY),
        p1.project(focalLength, size, _panX, _panY),
        bounds,
      );
      if (clipped == null) continue;
      scene.addLine(clipped.$1, clipped.$2, paint, (p0.y + p1.y) / 2);
    }
  }

  /// Add the axis lines and the floor outline to [scene].
  ///
  /// These were drawn before the surface and so were always behind it: the
  /// near half of an axis, and the near edge of the floor, could never appear
  /// in front of a surface they pass through. Labels and arrowheads are not
  /// included — they are annotations and belong on top.
  void _addAxisChromeTo(_LineSink scene, Size size, double focalLength) {
    // Off means the whole frame of reference — the axes, and the plane they
    // stand on with its outline — so the shape is left on its own. The plane
    // went on being drawn once, cutting through the middle of a surface the
    // user had asked to see bare.
    if (!showAxes) return;
    final theme = plotTheme;

    final List<(Color, Point3D, double, double)> axes =
        <(Color, Point3D, double, double)>[
          (theme.axisX, const Point3D(1, 0, 0), rangeX, scaleX),
          (theme.axisY, const Point3D(0, 1, 0), rangeY, scaleY),
          (theme.axisZ, const Point3D(0, 0, 1), rangeZ, scaleZ),
        ];

    for (final (color, dir, range, scale) in axes) {
      final Paint axisPaint =
          Paint()
            ..color = color
            ..strokeWidth = 2;
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(
          -dir.x * range * 2 * scale,
          -dir.y * range * 2 * scale,
          -dir.z * range * 2 * scale,
        ),
        Point3D(
          dir.x * range * 2 * scale,
          dir.y * range * 2 * scale,
          dir.z * range * 2 * scale,
        ),
        axisPaint,
      );
    }

    final Paint boundaryPaint =
        Paint()
          ..color = theme.boundary
          ..strokeWidth = 2;
    final corners = <Point3D>[
      Point3D(-rangeX * scaleX, -rangeY * scaleY, 0),
      Point3D(rangeX * scaleX, -rangeY * scaleY, 0),
      Point3D(rangeX * scaleX, rangeY * scaleY, 0),
      Point3D(-rangeX * scaleX, rangeY * scaleY, 0),
    ];
    for (int i = 0; i < 4; i++) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        corners[i],
        corners[(i + 1) % 4],
        boundaryPaint,
      );
    }
  }

  /// Add the floor grid to [scene] as depth-sorted segments.
  ///
  /// Each grid line is cut into pieces because a single line spans the whole
  /// floor: its near end and far end have very different depths, so one depth
  /// per line cannot say whether the surface crosses in front of it.
  void _addFloorGridTo(_LineSink scene, Size size, double focalLength) {
    // The plane goes with the axes (see [_addAxisChromeTo]).
    if (!showAxes) return;
    final theme = plotTheme;

    // The plane has to read as a plane even where it passes in front of a
    // bright surface. At the 8-10% alpha used for a grid on empty background,
    // a hairline over a saturated surface is invisible — the depth order was
    // right and nothing appeared to change. Major lines carry the structure,
    // minor ones the texture.
    final Paint majorPaint =
        Paint()
          ..color = theme.grid.withValues(alpha: 0.55)
          ..strokeWidth = 1.4;
    final Paint minorPaint =
        Paint()
          ..color = theme.subGrid.withValues(alpha: 0.28)
          ..strokeWidth = 0.9;

    // On the multiples of the step, like the ticks. Counted from the edge of
    // the box, as they were, the majors almost never landed on a multiple —
    // so the floor drew nothing but minor lines.
    for (final (double x, bool major) in Plot3DPainter._gridLinesWithin(
      rangeX,
    )) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(x * scaleX, -rangeY * scaleY, 0),
        Point3D(x * scaleX, rangeY * scaleY, 0),
        major ? majorPaint : minorPaint,
      );
    }
    for (final (double y, bool major) in Plot3DPainter._gridLinesWithin(
      rangeY,
    )) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(-rangeX * scaleX, y * scaleY, 0),
        Point3D(rangeX * scaleX, y * scaleY, 0),
        major ? majorPaint : minorPaint,
      );
    }
  }

  void _drawFloorGrid(Canvas canvas, Size size, double focalLength) {
    if (!showAxes) return;
    final theme = plotTheme;
    final gridPaint =
        Paint()
          ..color = theme.grid
          ..strokeWidth = 1.2;
    final subGridPaint =
        Paint()
          ..color = theme.subGrid
          ..strokeWidth = 0.8;

    for (final (double x, bool major) in Plot3DPainter._gridLinesWithin(
      rangeX,
    )) {
      final Point3D start = Point3D(
        x * scaleX,
        -rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final Point3D end = Point3D(
        x * scaleX,
        rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(
        canvas,
        size,
        focalLength,
        start,
        end,
        major ? gridPaint : subGridPaint,
      );
    }
    for (final (double y, bool major) in Plot3DPainter._gridLinesWithin(
      rangeY,
    )) {
      final Point3D start = Point3D(
        -rangeX * scaleX,
        y * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final Point3D end = Point3D(
        rangeX * scaleX,
        y * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(
        canvas,
        size,
        focalLength,
        start,
        end,
        major ? gridPaint : subGridPaint,
      );
    }
  }

  void _drawFloorBoundary(Canvas canvas, Size size, double focalLength) {
    if (!showAxes) return;
    final theme = plotTheme;
    final boundaryPaint =
        Paint()
          ..color = theme.boundary
          ..strokeWidth = 2;

    final corners = [
      Point3D(-rangeX * scaleX, -rangeY * scaleY, 0),
      Point3D(rangeX * scaleX, -rangeY * scaleY, 0),
      Point3D(rangeX * scaleX, rangeY * scaleY, 0),
      Point3D(-rangeX * scaleX, rangeY * scaleY, 0),
    ];

    for (int i = 0; i < 4; i++) {
      final start = corners[i].rotateZ(rotationZ).rotateX(rotationX);
      final end = corners[(i + 1) % 4].rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(canvas, size, focalLength, start, end, boundaryPaint);
    }
  }

  void _drawClippedLine(
    Canvas canvas,
    Size size,
    double focalLength,
    Point3D start,
    Point3D end,
    Paint paint,
  ) {
    final startProj = start.project(focalLength, size, _panX, _panY);
    final endProj = end.project(focalLength, size, _panX, _panY);
    final clipped = _clipLineToRect(
      startProj,
      endProj,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    if (clipped != null) canvas.drawLine(clipped.$1, clipped.$2, paint);
  }

  /// Where no axis annotation may go: the controls floating over the plot,
  /// and the colorbar when there is one.
  ///
  /// A label under a control cannot be read, and one over the colorbar makes
  /// the bar unreadable instead, so either way the label goes.
  List<Rect> _annotationKeepOut(Size size) => <Rect>[
    ...labelKeepOut,
    if (surfaceMode != SurfaceMode.none || fieldType == FieldType.vector)
      Plot3DPainter._colorbarZone(size),
  ];
  void _paintHaloed(
    Canvas canvas,
    TextPainter fill,
    String text,
    TextStyle style,
    Offset at,
    Color halo,
  ) {
    final TextPainter outline = Plot3DPainter._laidOut(text, style, halo: halo);
    final Offset topLeft = at - Offset(fill.width / 2, fill.height / 2);
    outline.paint(canvas, topLeft);
    fill.paint(canvas, topLeft);
  }

  /// The axes for a plot with no surface to sort them against: the lines and
  /// their marks painted straight onto the canvas.
  void _drawAxes(Canvas canvas, Size size, double focalLength) {
    if (!showAxes) return;
    final theme = plotTheme;
    for (final (Color color, Point3D dir, double range, double scale)
        in <(Color, Point3D, double, double)>[
          (theme.axisX, const Point3D(1, 0, 0), rangeX, scaleX),
          (theme.axisY, const Point3D(0, 1, 0), rangeY, scaleY),
          (theme.axisZ, const Point3D(0, 0, 1), rangeZ, scaleZ),
        ]) {
      final Point3D negPoint = Point3D(
        -dir.x * range * 2 * scale,
        -dir.y * range * 2 * scale,
        -dir.z * range * 2 * scale,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final Point3D posPoint = Point3D(
        dir.x * range * 2 * scale,
        dir.y * range * 2 * scale,
        dir.z * range * 2 * scale,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(
        canvas,
        size,
        focalLength,
        negPoint,
        posPoint,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      _drawClippedLine(
        canvas,
        size,
        focalLength,
        negPoint,
        posPoint,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    _addAxisMarksTo(_ImmediateSink(canvas), size, focalLength);
  }

  /// Put every axis annotation into [sink] at its own depth: the numbers,
  /// their ticks, the arrowheads and the axis names.
  ///
  /// Into the same order as the surfaces wherever there is one, so a surface
  /// nearer the camera covers the numbers behind it — the same way it already
  /// covers the axis lines.
  void _addAxisMarksTo(_LineSink sink, Size size, double focalLength) {
    if (!showAxes) return;
    final theme = plotTheme;

    // The ground the labels are haloed in: dark under light ink, light under
    // dark ink, so the halo always parts a label from what is behind it.
    final bool lightInk = theme.label.computeLuminance() > 0.5;
    final Color ground = lightInk ? Colors.black : Colors.white;

    // How far back the box reaches, so a label can fade with its depth. A
    // number on the far side of the box is the least connected to what you
    // are looking at, and at full strength it competes with the near ones.
    double nearest = double.infinity;
    double farthest = double.negativeInfinity;
    for (final double sx in const <double>[-1, 1]) {
      for (final double sy in const <double>[-1, 1]) {
        for (final double sz in const <double>[-1, 1]) {
          final double d =
              Point3D(
                sx * rangeX * scaleX,
                sy * rangeY * scaleY,
                sz * rangeZ * scaleZ,
              ).rotateZ(rotationZ).rotateX(rotationX).y;
          nearest = min(nearest, d);
          farthest = max(farthest, d);
        }
      }
    }
    double fadeAt(double depth) {
      final double span = farthest - nearest;
      if (!(span > 0)) return 1;
      // Full strength at the front, two fifths at the back — in eighths, so
      // a label keeps the same few colours as the plot turns and its laid-out
      // text can be reused (see [_laidOut]).
      final double fade = 1 - 0.6 * ((depth - nearest) / span).clamp(0.0, 1.0);
      return (fade * 8).round() / 8;
    }

    final List<Rect> keepOut = _annotationKeepOut(size);
    bool blocked(Rect r) => keepOut.any((Rect k) => k.overlaps(r));
    final Rect canvasRect = Offset.zero & size;

    final axes = [
      (theme.axisX, 'X', Point3D(1, 0, 0), rangeX, scaleX),
      (theme.axisY, 'Y', Point3D(0, 1, 0), rangeY, scaleY),
      (theme.axisZ, 'Z', Point3D(0, 0, 1), rangeZ, scaleZ),
    ];

    for (final axis in axes) {
      final color = axis.$1;
      final label = axis.$2;
      final dir = axis.$3;
      final range = axis.$4;
      final scale = axis.$5;

      // Just beyond the plotted box, which is where the axis stops meaning
      // anything. Not at 0.9 of the range, which put the head inside the box
      // with the line running on past it; and not at the line's true end at
      // twice the range, which is off screen for the vertical axis.
      const double arrowAt = Plot3DPainter.axisArrowOvershoot;
      final arrowPos = Point3D(
        dir.x * range * arrowAt * scale,
        dir.y * range * arrowAt * scale,
        dir.z * range * arrowAt * scale,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final arrowProj = arrowPos.project(focalLength, size, _panX, _panY);

      if (_isPointInRect(
        arrowProj,
        Rect.fromLTWH(-20, -20, size.width + 40, size.height + 40),
      )) {
        final origin = const Point3D(
          0,
          0,
          0,
        ).rotateZ(rotationZ).rotateX(rotationX);
        final originProj = origin.project(focalLength, size, _panX, _panY);
        final direction = Offset(
          arrowProj.dx - originProj.dx,
          arrowProj.dy - originProj.dy,
        );
        final length = direction.distance;

        if (length > 0) {
          final normalized = direction / length;
          final perpendicular = Offset(-normalized.dy, normalized.dx);
          // A solid cone rather than an open V: longer than it is wide, and
          // closed, so it reads as the head of the axis rather than two
          // strokes near it.
          const double arrowLength = 16.0;
          const double arrowHalfWidth = 5.5;
          final Offset base = arrowProj - normalized * arrowLength;
          final Path head =
              Path()
                ..moveTo(arrowProj.dx, arrowProj.dy)
                ..lineTo(
                  base.dx + perpendicular.dx * arrowHalfWidth,
                  base.dy + perpendicular.dy * arrowHalfWidth,
                )
                ..lineTo(
                  base.dx - perpendicular.dx * arrowHalfWidth,
                  base.dy - perpendicular.dy * arrowHalfWidth,
                )
                ..close();
          final Paint headPaint =
              Paint()
                ..color = color
                ..style = PaintingStyle.fill;
          sink.addMark(
            (Canvas canvas) => canvas.drawPath(head, headPaint),
            arrowPos.y,
          );
        }

        final TextStyle nameStyle = TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        );
        final TextPainter name = Plot3DPainter._laidOut(label, nameStyle);
        final Offset nameAt = Offset(
          arrowProj.dx + 8 + name.width / 2,
          arrowProj.dy - 8 + name.height / 2,
        );
        if (!blocked(
          Rect.fromCenter(
            center: nameAt,
            width: name.width,
            height: name.height,
          ),
        )) {
          final Color halo = ground.withValues(alpha: 0.55);
          sink.addMark(
            (Canvas canvas) =>
                _paintHaloed(canvas, name, label, nameStyle, nameAt, halo),
            arrowPos.y,
          );
        }
      }

      final double step = Plot3DPainter._tickStep(range);
      for (final double t in Plot3DPainter._ticksWithin(range, step)) {
        final Point3D tickPos = Point3D(
          dir.x * t * scale,
          dir.y * t * scale,
          dir.z * t * scale,
        ).rotateZ(rotationZ).rotateX(rotationX);
        final Offset tickProj = tickPos.project(
          focalLength,
          size,
          _panX,
          _panY,
        );
        if (!_isPointInRect(tickProj, canvasRect)) continue;

        const tickLen = 5.0;
        final Point3D tick1End = switch (label) {
          'X' => Point3D(t * scale, tickLen, 0),
          'Y' => Point3D(tickLen, t * scale, 0),
          _ => Point3D(tickLen, 0, t * scale),
        }.rotateZ(rotationZ).rotateX(rotationX);

        final Point3D labelPos = switch (label) {
          'X' => Point3D(t * scale, -15, -10),
          'Y' => Point3D(-15, t * scale, -10),
          _ => Point3D(-15, -15, t * scale),
        }.rotateZ(rotationZ).rotateX(rotationX);
        final Offset labelProj = labelPos.project(
          focalLength,
          size,
          _panX,
          _panY,
        );

        final double fade = fadeAt(labelPos.y);
        final String text = _formatNumber(t);
        final TextStyle style = TextStyle(
          color: theme.label.withValues(alpha: theme.label.a * fade),
          fontSize: 10,
        );
        final TextPainter fill = Plot3DPainter._laidOut(text, style);
        final Rect labelRect = Rect.fromCenter(
          center: labelProj,
          width: fill.width + 6,
          height: fill.height + 4,
        );
        // Under a control, or over the colorbar, the tick goes with its
        // number: a mark with no value beside it says nothing.
        if (blocked(labelRect) || blocked(tickProj & const Size(1, 1))) {
          continue;
        }

        // One mark straight through the axis. Two marks at right angles read
        // as a small corner sitting beside the line rather than a division
        // of it.
        final Offset tick1 = tick1End.project(focalLength, size, _panX, _panY);
        final Paint tickPaint =
            Paint()
              ..color = theme.tick.withValues(alpha: theme.tick.a * fade)
              ..strokeWidth = 1;
        sink.addMark(
          (Canvas canvas) =>
              canvas.drawLine(tickProj + (tickProj - tick1), tick1, tickPaint),
          tickPos.y,
        );

        if (!canvasRect.contains(labelProj)) continue;
        final Color halo = ground.withValues(alpha: 0.55 * fade);
        sink.addMark(
          (Canvas canvas) =>
              _paintHaloed(canvas, fill, text, style, labelProj, halo),
          labelPos.y,
        );
      }
    }
  }

  String _formatNumber(double n) {
    // toInt() throws on a non-finite label rather than producing one.
    if (!n.isFinite) return '';
    if (n.abs() < 0.001) return '0';
    if (n == n.roundToDouble() && n.abs() < 1000) return n.toInt().toString();
    if (n.abs() >= 100) return n.toInt().toString();
    if (n.abs() >= 10) return n.toStringAsFixed(1);
    return n.toStringAsFixed(2);
  }

  (Offset, Offset)? _clipLineToRect(Offset p1, Offset p2, Rect rect) {
    double x1 = p1.dx, y1 = p1.dy, x2 = p2.dx, y2 = p2.dy;
    const inside = 0, left = 1, right = 2, bottom = 4, top = 8;

    int computeCode(double x, double y) {
      int code = inside;
      if (x < rect.left) {
        code |= left;
      } else if (x > rect.right) {
        code |= right;
      }
      if (y < rect.top) {
        code |= top;
      } else if (y > rect.bottom) {
        code |= bottom;
      }
      return code;
    }

    int code1 = computeCode(x1, y1), code2 = computeCode(x2, y2);

    while (true) {
      if ((code1 | code2) == 0) return (Offset(x1, y1), Offset(x2, y2));
      if ((code1 & code2) != 0) return null;

      int codeOut = code1 != 0 ? code1 : code2;
      double x = 0, y = 0;

      if ((codeOut & top) != 0) {
        x = x1 + (x2 - x1) * (rect.top - y1) / (y2 - y1);
        y = rect.top;
      } else if ((codeOut & bottom) != 0) {
        x = x1 + (x2 - x1) * (rect.bottom - y1) / (y2 - y1);
        y = rect.bottom;
      } else if ((codeOut & right) != 0) {
        y = y1 + (y2 - y1) * (rect.right - x1) / (x2 - x1);
        x = rect.right;
      } else if ((codeOut & left) != 0) {
        y = y1 + (y2 - y1) * (rect.left - x1) / (x2 - x1);
        x = rect.left;
      }

      if (codeOut == code1) {
        x1 = x;
        y1 = y;
        code1 = computeCode(x1, y1);
      } else {
        x2 = x;
        y2 = y;
        code2 = computeCode(x2, y2);
      }
    }
  }

  bool _isPointInRect(Offset point, Rect rect) =>
      point.dx >= rect.left &&
      point.dx <= rect.right &&
      point.dy >= rect.top &&
      point.dy <= rect.bottom;
}
