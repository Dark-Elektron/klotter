part of 'plot_3d_painter.dart';

/// Contour lines over surfaces and over the fields of a vector plot.
extension Plot3DContours on Plot3DPainter {
  void _drawVectorMagnitudeContours3D(
    Canvas canvas,
    Size size,
    double focalLength,
  ) {
    if (vectorParser == null || vectorParser!.is3D) return;

    const gridSize = 60;
    const numContours = 12;

    // Build grid of magnitude values
    List<List<double>> grid = [];
    double maxMag = 0;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        final mag = vectorParser!.magnitude(x, y);
        if (mag.isFinite) {
          row.add(mag);
          maxMag = max(maxMag, mag);
        } else {
          row.add(0);
        }
      }
      grid.add(row);
    }

    if (maxMag == 0) return;

    final zScale = rangeZ / maxMag;

    // Draw contour lines on the surface
    for (int level = 0; level < numContours; level++) {
      final threshold = maxMag * (level + 1) / (numContours + 1);
      final normalizedLevel = threshold / maxMag;
      final color = plotColormap(normalizedLevel, palette);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;

      _drawVectorMagnitudeContourLevel3D(
        canvas,
        size,
        focalLength,
        grid,
        threshold,
        paint,
        zScale,
      );
    }
  }

  void _drawVectorComponentContours3D(
    Canvas canvas,
    Size size,
    double focalLength,
    SurfaceMode mode,
  ) {
    if (vectorParser == null || vectorParser!.is3D) return;

    const gridSize = 60;
    const numContours = 12;

    List<List<double>> grid = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    double maxAbs = 0;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        final val = vectorParser!.componentValue(mode, x, y);
        if (val.isFinite) {
          row.add(val);
          minVal = min(minVal, val);
          maxVal = max(maxVal, val);
          maxAbs = max(maxAbs, val.abs());
        } else {
          row.add(0);
        }
      }
      grid.add(row);
    }

    if (minVal == maxVal || maxAbs == 0) return;

    final zScale = rangeZ / maxAbs;

    for (int level = 0; level < numContours; level++) {
      final threshold =
          minVal + (maxVal - minVal) * (level + 1) / (numContours + 1);
      final normalizedLevel = (threshold - minVal) / (maxVal - minVal);
      final color = plotColormap(normalizedLevel, palette);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;

      _drawVectorComponentContourLevel3D(
        canvas,
        size,
        focalLength,
        grid,
        threshold,
        paint,
        zScale,
      );
    }
  }

  void _drawVectorComponentContourLevel3D(
    Canvas canvas,
    Size size,
    double focalLength,
    List<List<double>> grid,
    double threshold,
    Paint paint,
    double zScale,
  ) {
    final gridSize = grid.length - 1;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final v0 = grid[i][j];
        final v1 = grid[i + 1][j];
        final v2 = grid[i + 1][j + 1];
        final v3 = grid[i][j + 1];

        int caseIndex = 0;
        if (v0 >= threshold) caseIndex |= 1;
        if (v1 >= threshold) caseIndex |= 2;
        if (v2 >= threshold) caseIndex |= 4;
        if (v3 >= threshold) caseIndex |= 8;

        if (caseIndex == 0 || caseIndex == 15) continue;

        final x0 = -rangeX + (2 * rangeX * i / gridSize);
        final x1 = -rangeX + (2 * rangeX * (i + 1) / gridSize);
        final y0 = -rangeY + (2 * rangeY * j / gridSize);
        final y1 = -rangeY + (2 * rangeY * (j + 1) / gridSize);

        final pz = threshold * zScale;

        List<Point3D> points3D = [];

        if ((v0 >= threshold) != (v1 >= threshold)) {
          final t = (threshold - v0) / (v1 - v0);
          final px = x0 + t * (x1 - x0);
          points3D.add(Point3D(px * scaleX, y0 * scaleY, pz * scaleZ));
        }
        if ((v1 >= threshold) != (v2 >= threshold)) {
          final t = (threshold - v1) / (v2 - v1);
          final py = y0 + t * (y1 - y0);
          points3D.add(Point3D(x1 * scaleX, py * scaleY, pz * scaleZ));
        }
        if ((v2 >= threshold) != (v3 >= threshold)) {
          final t = (threshold - v3) / (v2 - v3);
          final px = x0 + t * (x1 - x0);
          points3D.add(Point3D(px * scaleX, y1 * scaleY, pz * scaleZ));
        }
        if ((v3 >= threshold) != (v0 >= threshold)) {
          final t = (threshold - v0) / (v3 - v0);
          final py = y0 + t * (y1 - y0);
          points3D.add(Point3D(x0 * scaleX, py * scaleY, pz * scaleZ));
        }

        if (points3D.length >= 2) {
          final p1 = points3D[0].rotateZ(rotationZ).rotateX(rotationX);
          final p2 = points3D[1].rotateZ(rotationZ).rotateX(rotationX);
          final proj1 = p1.project(focalLength, size, _panX, _panY);
          final proj2 = p2.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, _panX, _panY);
          final proj4 = p4.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj3, proj4, paint);
        }
      }
    }
  }

  void _drawVectorMagnitudeContourLevel3D(
    Canvas canvas,
    Size size,
    double focalLength,
    List<List<double>> grid,
    double threshold,
    Paint paint,
    double zScale,
  ) {
    final gridSize = grid.length - 1;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final v0 = grid[i][j];
        final v1 = grid[i + 1][j];
        final v2 = grid[i + 1][j + 1];
        final v3 = grid[i][j + 1];

        if (v0 == 0 || v1 == 0 || v2 == 0 || v3 == 0) continue;

        int caseIndex = 0;
        if (v0 >= threshold) caseIndex |= 1;
        if (v1 >= threshold) caseIndex |= 2;
        if (v2 >= threshold) caseIndex |= 4;
        if (v3 >= threshold) caseIndex |= 8;

        if (caseIndex == 0 || caseIndex == 15) continue;

        final x0 = -rangeX + (2 * rangeX * i / gridSize);
        final x1 = -rangeX + (2 * rangeX * (i + 1) / gridSize);
        final y0 = -rangeY + (2 * rangeY * j / gridSize);
        final y1 = -rangeY + (2 * rangeY * (j + 1) / gridSize);

        final pz = threshold * zScale;

        List<Point3D> points3D = [];

        if ((v0 >= threshold) != (v1 >= threshold)) {
          final t = (threshold - v0) / (v1 - v0);
          final px = x0 + t * (x1 - x0);
          points3D.add(Point3D(px * scaleX, y0 * scaleY, pz * scaleZ));
        }
        if ((v1 >= threshold) != (v2 >= threshold)) {
          final t = (threshold - v1) / (v2 - v1);
          final py = y0 + t * (y1 - y0);
          points3D.add(Point3D(x1 * scaleX, py * scaleY, pz * scaleZ));
        }
        if ((v2 >= threshold) != (v3 >= threshold)) {
          final t = (threshold - v3) / (v2 - v3);
          final px = x0 + t * (x1 - x0);
          points3D.add(Point3D(px * scaleX, y1 * scaleY, pz * scaleZ));
        }
        if ((v3 >= threshold) != (v0 >= threshold)) {
          final t = (threshold - v0) / (v3 - v0);
          final py = y0 + t * (y1 - y0);
          points3D.add(Point3D(x0 * scaleX, py * scaleY, pz * scaleZ));
        }

        if (points3D.length >= 2) {
          final p1 = points3D[0].rotateZ(rotationZ).rotateX(rotationX);
          final p2 = points3D[1].rotateZ(rotationZ).rotateX(rotationX);
          final proj1 = p1.project(focalLength, size, _panX, _panY);
          final proj2 = p2.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, _panX, _panY);
          final proj4 = p4.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj3, proj4, paint);
        }
      }
    }
  }

  void _drawContourLines3D(Canvas canvas, Size size, double focalLength) {
    final parser = function;
    const gridSize = 60;
    const numContours = 12;

    List<List<double>> grid = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        double val;
        try {
          val = parser.evaluate(x, y);
          if (!val.isFinite) val = 0;
        } catch (e) {
          val = 0;
        }
        row.add(val);
        if (val.isFinite && val != 0) {
          minVal = min(minVal, val);
          maxVal = max(maxVal, val);
        }
      }
      grid.add(row);
    }

    if (minVal == maxVal) return;

    for (int level = 0; level < numContours; level++) {
      final threshold =
          minVal + (maxVal - minVal) * (level + 1) / (numContours + 1);
      final normalizedLevel = (threshold - minVal) / (maxVal - minVal);
      final color = plotColormap(normalizedLevel, palette);

      final paint =
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      _drawContourLevel3D(
        canvas,
        size,
        focalLength,
        grid,
        threshold,
        paint,
        onFloor: true,
      );
    }
  }

  /// Contours for every height surface on the axes, not just the first.
  ///
  /// It read `function` — the cell's first line — so a plot holding two
  /// surfaces drew contours on one of them and left the other bare, with no
  /// indication that anything was missing.
  void _drawSurfaceContours(Canvas canvas, Size size, double focalLength) {
    for (final PlotExpression curve in _sheetCurves) {
      // A hidden surface has no contours either.
      if (curve.hidden) continue;
      _drawContoursFor(canvas, size, focalLength, curve);
    }
  }

  void _drawContoursFor(
    Canvas canvas,
    Size size,
    double focalLength,
    PlotExpression parser,
  ) {
    const gridSize = 60;
    const numContours = 10;

    List<List<double>> grid = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        double val;
        try {
          val = parser.evaluate(x, y);
          if (!val.isFinite || val < -rangeZ || val > rangeZ) {
            val = double.nan;
          }
        } catch (e) {
          val = double.nan;
        }
        row.add(val);
        if (val.isFinite) {
          minVal = min(minVal, val);
          maxVal = max(maxVal, val);
        }
      }
      grid.add(row);
    }

    if (minVal == maxVal) return;

    for (int level = 0; level < numContours; level++) {
      final threshold =
          minVal + (maxVal - minVal) * (level + 1) / (numContours + 1);
      final normalizedLevel = (threshold - minVal) / (maxVal - minVal);
      final color = plotColormap(normalizedLevel, palette);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;

      _drawContourLevel3D(
        canvas,
        size,
        focalLength,
        grid,
        threshold,
        paint,
        onFloor: false,
      );
    }
  }

  void _drawContourLevel3D(
    Canvas canvas,
    Size size,
    double focalLength,
    List<List<double>> grid,
    double threshold,
    Paint paint, {
    required bool onFloor,
  }) {
    final gridSize = grid.length - 1;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final v0 = grid[i][j];
        final v1 = grid[i + 1][j];
        final v2 = grid[i + 1][j + 1];
        final v3 = grid[i][j + 1];

        if (!v0.isFinite || !v1.isFinite || !v2.isFinite || !v3.isFinite) {
          continue;
        }

        int caseIndex = 0;
        if (v0 >= threshold) caseIndex |= 1;
        if (v1 >= threshold) caseIndex |= 2;
        if (v2 >= threshold) caseIndex |= 4;
        if (v3 >= threshold) caseIndex |= 8;

        if (caseIndex == 0 || caseIndex == 15) continue;

        final x0 = -rangeX + (2 * rangeX * i / gridSize);
        final x1 = -rangeX + (2 * rangeX * (i + 1) / gridSize);
        final y0 = -rangeY + (2 * rangeY * j / gridSize);
        final y1 = -rangeY + (2 * rangeY * (j + 1) / gridSize);

        List<Point3D> points3D = [];

        if ((v0 >= threshold) != (v1 >= threshold)) {
          final t = (threshold - v0) / (v1 - v0);
          final px = x0 + t * (x1 - x0);
          final pz = onFloor ? 0.0 : threshold;
          points3D.add(Point3D(px * scaleX, y0 * scaleY, pz * scaleZ));
        }
        if ((v1 >= threshold) != (v2 >= threshold)) {
          final t = (threshold - v1) / (v2 - v1);
          final py = y0 + t * (y1 - y0);
          final pz = onFloor ? 0.0 : threshold;
          points3D.add(Point3D(x1 * scaleX, py * scaleY, pz * scaleZ));
        }
        if ((v2 >= threshold) != (v3 >= threshold)) {
          final t = (threshold - v3) / (v2 - v3);
          final px = x0 + t * (x1 - x0);
          final pz = onFloor ? 0.0 : threshold;
          points3D.add(Point3D(px * scaleX, y1 * scaleY, pz * scaleZ));
        }
        if ((v3 >= threshold) != (v0 >= threshold)) {
          final t = (threshold - v0) / (v3 - v0);
          final py = y0 + t * (y1 - y0);
          final pz = onFloor ? 0.0 : threshold;
          points3D.add(Point3D(x0 * scaleX, py * scaleY, pz * scaleZ));
        }

        if (points3D.length >= 2) {
          final p1 = points3D[0].rotateZ(rotationZ).rotateX(rotationX);
          final p2 = points3D[1].rotateZ(rotationZ).rotateX(rotationX);
          final proj1 = p1.project(focalLength, size, _panX, _panY);
          final proj2 = p2.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, _panX, _panY);
          final proj4 = p4.project(focalLength, size, _panX, _panY);
          canvas.drawLine(proj3, proj4, paint);
        }
      }
    }
  }
}
