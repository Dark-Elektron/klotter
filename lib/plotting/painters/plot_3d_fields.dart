part of 'plot_3d_painter.dart';

/// Fields filling the box: scalar fields as points, vector fields as arrows,
/// and their magnitudes.
extension Plot3DFields on Plot3DPainter {
  /// The fields to draw, with [vectorParser] as the fallback.
  List<VectorFieldParser> get fieldsToDraw =>
      vectorFields.isNotEmpty
          ? vectorFields
          : (vectorParser == null
              ? const <VectorFieldParser>[]
              : <VectorFieldParser>[vectorParser!]);
  void _drawScalarField3D(Canvas canvas, Size size, double focalLength) {
    final parser = function;
    const gridCount = 12;

    List<FieldPoint3D> points = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        for (int k = 0; k <= gridCount; k++) {
          final x = -rangeX + (2 * rangeX * i / gridCount);
          final y = -rangeY + (2 * rangeY * j / gridCount);
          final z = -rangeZ + (2 * rangeZ * k / gridCount);

          try {
            final val = parser.evaluate(x, y, z);
            if (!val.isFinite) continue;

            minVal = min(minVal, val);
            maxVal = max(maxVal, val);

            final point3D = Point3D(
              x * scaleX,
              y * scaleY,
              z * scaleZ,
            ).rotateZ(rotationZ).rotateX(rotationX);

            points.add(FieldPoint3D(point3D, val));
          } catch (_) {
            // A point that cannot be evaluated is simply not drawn. evaluate()
            // already reports failure as NaN; this only guards the rest.
          }
        }
      }
    }

    if (points.isEmpty) return;
    if (minVal == maxVal) maxVal = minVal + 1;

    points.sort((a, b) => b.point.y.compareTo(a.point.y));

    for (final fp in points) {
      final proj = fp.point.project(focalLength, size, _panX, _panY);
      if (!_isPointInRect(proj, Rect.fromLTWH(0, 0, size.width, size.height))) {
        continue;
      }

      final normalized = (fp.value - minVal) / (maxVal - minVal);
      final color = plotColormap(normalized, palette);

      final depthScale = focalLength / (focalLength + fp.point.y);
      final radius = 6.0 * depthScale;

      canvas.drawCircle(
        proj,
        radius,
        Paint()..color = color.withValues(alpha: 0.8),
      );

      canvas.drawCircle(
        Offset(proj.dx - radius * 0.3, proj.dy - radius * 0.3),
        radius * 0.3,
        Paint()..color = _theme.label.withValues(alpha: 0.25),
      );
    }

    _drawColorbar3D(canvas, size, minVal, maxVal);
  }

  void _drawVectorField3D(Canvas canvas, Size size, double focalLength) {
    // One set of arrows per field, as in 2D. Two fields sharing the full
    // rainbow put every magnitude in both and neither can be followed, so each
    // takes a ramp and a scale of its own.
    final List<VectorFieldParser> fields = fieldsToDraw;
    for (int n = 0; n < fields.length; n++) {
      _drawOneVectorField3D(
        canvas,
        size,
        focalLength,
        fields[n],
        surfaceColormap(n, of: fields.length, palette: palette),
        surfaceRampStops(n, of: fields.length, palette: palette),
        n,
      );
    }
  }

  void _drawOneVectorField3D(
    Canvas canvas,
    Size size,
    double focalLength,
    VectorFieldParser field,
    Color Function(double) ramp,
    List<Color> rampStops,
    int row,
  ) {
    final bool showSurface = surfaceMode != SurfaceMode.none;
    const gridCount = 8;
    final bool is3DVector = field.is3D;

    List<Arrow3D> arrows = [];
    double maxMag = 0;
    double maxSurfaceAbs = 0;

    if (is3DVector) {
      for (int i = 0; i <= gridCount; i++) {
        for (int j = 0; j <= gridCount; j++) {
          for (int k = 0; k <= gridCount; k++) {
            final x = -rangeX + (2 * rangeX * i / gridCount);
            final y = -rangeY + (2 * rangeY * j / gridCount);
            final z = -rangeZ + (2 * rangeZ * k / gridCount);

            final (fx, fy, fz) = field.evaluate(x, y, z);
            double vx = fx;
            double vy = fy;
            double vz = fz;
            double surfaceValue = 0;
            double mag = field.magnitude(x, y, z);

            if (surfaceMode == SurfaceMode.x) {
              vx = fx;
              vy = 0;
              vz = 0;
              surfaceValue = fx;
              mag = fx.abs();
            } else if (surfaceMode == SurfaceMode.y) {
              vx = 0;
              vy = fy;
              vz = 0;
              surfaceValue = fy;
              mag = fy.abs();
            } else if (surfaceMode == SurfaceMode.z) {
              vx = 0;
              vy = 0;
              vz = fz;
              surfaceValue = fz;
              mag = fz.abs();
            } else {
              surfaceValue = mag;
            }

            if (!mag.isFinite || mag < 1e-10) continue;

            maxMag = max(maxMag, mag);
            maxSurfaceAbs = max(maxSurfaceAbs, surfaceValue.abs());

            final inv = mag == 0 ? 0.0 : 1 / mag;
            final nx = vx * inv;
            final ny = vy * inv;
            final nz = vz * inv;
            final startPoint = Point3D(x * scaleX, y * scaleY, z * scaleZ);

            arrows.add(Arrow3D(startPoint, nx, ny, nz, mag, surfaceValue));
          }
        }
      }
    } else {
      for (int i = 0; i <= gridCount * 2; i++) {
        for (int j = 0; j <= gridCount * 2; j++) {
          final x = -rangeX + (2 * rangeX * i / (gridCount * 2));
          final y = -rangeY + (2 * rangeY * j / (gridCount * 2));

          final (fx, fy, fz) = field.evaluate(x, y, 0);
          double vx = fx;
          double vy = fy;
          double vz = 0;
          double surfaceValue = 0;
          double mag = field.magnitude(x, y, 0);

          if (surfaceMode == SurfaceMode.x) {
            vx = fx;
            vy = 0;
            surfaceValue = fx;
            mag = fx.abs();
          } else if (surfaceMode == SurfaceMode.y) {
            vx = 0;
            vy = fy;
            surfaceValue = fy;
            mag = fy.abs();
          } else if (surfaceMode == SurfaceMode.z) {
            vx = 0;
            vy = 0;
            vz = fz;
            surfaceValue = fz;
            mag = fz.abs();
          } else {
            surfaceValue = mag;
          }

          if (!mag.isFinite || mag < 1e-10) continue;

          maxMag = max(maxMag, mag);
          maxSurfaceAbs = max(maxSurfaceAbs, surfaceValue.abs());

          final inv = mag == 0 ? 0.0 : 1 / mag;
          final nx = vx * inv;
          final ny = vy * inv;
          final nz = vz * inv;
          final startPoint = Point3D(x * scaleX, y * scaleY, 0);

          arrows.add(Arrow3D(startPoint, nx, ny, nz, mag, surfaceValue));
        }
      }
    }

    if (arrows.isEmpty || maxMag == 0) return;

    arrows.sort((a, b) {
      final aRotated = a.start.rotateZ(rotationZ).rotateX(rotationX);
      final bRotated = b.start.rotateZ(rotationZ).rotateX(rotationX);
      return bRotated.y.compareTo(aRotated.y);
    });

    const arrowLength = 15.0;
    final double zScale =
        (showSurface && !is3DVector && maxSurfaceAbs > 0)
            ? (rangeZ / maxSurfaceAbs)
            : 0.0;
    for (final arrow in arrows) {
      final double surfaceZ =
          (showSurface && !is3DVector) ? arrow.surfaceValue * zScale : 0.0;
      final startPoint =
          (showSurface && !is3DVector)
              ? Point3D(arrow.start.x, arrow.start.y, surfaceZ * scaleZ)
              : arrow.start;
      final startRotated = startPoint.rotateZ(rotationZ).rotateX(rotationX);
      final startProj = startRotated.project(focalLength, size, _panX, _panY);

      if (!_isPointInRect(
        startProj,
        Rect.fromLTWH(-50, -50, size.width + 100, size.height + 100),
      )) {
        continue;
      }

      final endPoint = Point3D(
        startPoint.x + arrow.dx * arrowLength,
        startPoint.y + arrow.dy * arrowLength,
        startPoint.z + arrow.dz * arrowLength,
      );
      final endRotated = endPoint.rotateZ(rotationZ).rotateX(rotationX);
      final endProj = endRotated.project(focalLength, size, _panX, _panY);

      final normalized = arrow.magnitude / maxMag;
      final color = ramp(normalized);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;

      canvas.drawLine(startProj, endProj, paint);

      final dx = endProj.dx - startProj.dx;
      final dy = endProj.dy - startProj.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len > 0) {
        final ux = dx / len;
        final uy = dy / len;
        const headLength = 5.0;
        const headAngle = 0.5;

        canvas.drawLine(
          endProj,
          Offset(
            endProj.dx -
                headLength * (ux * cos(headAngle) - uy * sin(headAngle)),
            endProj.dy -
                headLength * (ux * sin(headAngle) + uy * cos(headAngle)),
          ),
          paint,
        );
        canvas.drawLine(
          endProj,
          Offset(
            endProj.dx -
                headLength * (ux * cos(-headAngle) - uy * sin(-headAngle)),
            endProj.dy -
                headLength * (ux * sin(-headAngle) + uy * cos(-headAngle)),
          ),
          paint,
        );
      }
    }

    if (surfaceMode == SurfaceMode.none) {
      _drawColorbar3D(canvas, size, 0, maxMag, stops: rampStops, row: row);
    }
  }

  void _drawVectorMagnitudeField3D(
    Canvas canvas,
    Size size,
    double focalLength,
  ) {
    // One shaded lattice per field, each on its own ramp and with its own
    // scale — the last of the vector renderers to still draw a single field on
    // the full rainbow. Two fields sharing that rainbow put every magnitude in
    // both, which is unreadable however they are laid out.
    final List<VectorFieldParser> fields = fieldsToDraw;
    for (int n = 0; n < fields.length; n++) {
      _drawOneMagnitudeField3D(
        canvas,
        size,
        focalLength,
        fields[n],
        surfaceColormap(n, of: fields.length, palette: palette),
        surfaceRampStops(n, of: fields.length, palette: palette),
        n,
      );
    }
  }

  void _drawOneMagnitudeField3D(
    Canvas canvas,
    Size size,
    double focalLength,
    VectorFieldParser field,
    Color Function(double) ramp,
    List<Color> rampStops,
    int row,
  ) {
    const gridCount = 10;
    final bool is3DVector = field.is3D;

    List<FieldPoint3D> points = [];
    double maxMag = 0;

    if (is3DVector) {
      for (int i = 0; i <= gridCount; i++) {
        for (int j = 0; j <= gridCount; j++) {
          for (int k = 0; k <= gridCount; k++) {
            final x = -rangeX + (2 * rangeX * i / gridCount);
            final y = -rangeY + (2 * rangeY * j / gridCount);
            final z = -rangeZ + (2 * rangeZ * k / gridCount);

            final mag = field.magnitude(x, y, z);
            if (!mag.isFinite) continue;

            maxMag = max(maxMag, mag);

            final point3D = Point3D(
              x * scaleX,
              y * scaleY,
              z * scaleZ,
            ).rotateZ(rotationZ).rotateX(rotationX);

            points.add(FieldPoint3D(point3D, mag));
          }
        }
      }
    } else {
      for (int i = 0; i <= gridCount * 2; i++) {
        for (int j = 0; j <= gridCount * 2; j++) {
          final x = -rangeX + (2 * rangeX * i / (gridCount * 2));
          final y = -rangeY + (2 * rangeY * j / (gridCount * 2));

          final mag = field.magnitude(x, y, 0);
          if (!mag.isFinite) continue;

          maxMag = max(maxMag, mag);

          final point3D = Point3D(
            x * scaleX,
            y * scaleY,
            0,
          ).rotateZ(rotationZ).rotateX(rotationX);

          points.add(FieldPoint3D(point3D, mag));
        }
      }
    }

    if (points.isEmpty || maxMag == 0) return;

    points.sort((a, b) => b.point.y.compareTo(a.point.y));

    for (final fp in points) {
      final proj = fp.point.project(focalLength, size, _panX, _panY);
      if (!_isPointInRect(proj, Rect.fromLTWH(0, 0, size.width, size.height))) {
        continue;
      }

      final normalized = fp.value / maxMag;
      final color = ramp(normalized);

      final depthScale = focalLength / (focalLength + fp.point.y);
      final radius = 6.0 * depthScale;

      canvas.drawCircle(
        proj,
        radius,
        Paint()..color = color.withValues(alpha: 0.8),
      );

      canvas.drawCircle(
        Offset(proj.dx - radius * 0.3, proj.dy - radius * 0.3),
        radius * 0.3,
        Paint()..color = _theme.label.withValues(alpha: 0.25),
      );
    }

    _drawColorbar3D(canvas, size, 0, maxMag, stops: rampStops, row: row);
  }
}
