import 'dart:ui' show Vertices, VertexMode;
import 'dart:math';
import '../../utils/app_colors.dart';
import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../parsers/plot_expression.dart';
import '../utils/parametric.dart';
import '../parsers/vector_field_parser.dart';
import '../../math_engine/math_engine.dart';
import '../utils/colormap.dart';
import '../utils/curve_features.dart';
import '../utils/level_set.dart';
import '../utils/plot_theme.dart';
import '../utils/readout_box.dart';

class Plot2DPainter extends CustomPainter {
  final PlotExpression function;

  /// One curve per line of the cell. `function` stays the primary entry and
  /// still drives surfaces, fields and contours, which are single-function
  /// views by nature.
  final List<PlotExpression> functions;

  /// x of the trace crosshair in data space, or null when not tracing.
  final double? traceX;

  /// The root or turning point the trace snapped to, if any.
  final CurveFeature? traceFeature;
  final double xMin, xMax, yMin, yMax;
  final PlotMode plotMode;
  final FieldType fieldType;
  final VectorFieldParser? vectorParser;
  final bool showContour;
  final SurfaceMode surfaceMode;
  final AppColors colors;

  /// True while a finger is on the plot. Sampling drops to a coarser grid for
  /// the duration, because a moving window misses the cache on every frame.
  final bool interacting;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  /// The spans u and v are swept over when the expression is parametric.
  ///
  /// Unused otherwise — a field is sampled over the window, so it has no
  /// parameter to sweep.
  final ParameterRange uRange;
  final ParameterRange vRange;

  Plot2DPainter({
    required this.function,
    this.functions = const <PlotExpression>[],
    this.traceX,
    this.traceFeature,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.plotMode,
    required this.fieldType,
    this.vectorParser,
    required this.showContour,
    required this.surfaceMode,
    required this.colors,
    this.interacting = false,
    required this.plotTheme,
    this.uRange = defaultParameterRange,
    this.vRange = defaultParameterRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double toScreenX(double x) => (x - xMin) / (xMax - xMin) * size.width;
    double toScreenY(double y) =>
        size.height - (y - yMin) / (yMax - yMin) * size.height;
    final bool showSurface = surfaceMode != SurfaceMode.none;

    _drawGrid(canvas, size, toScreenX, toScreenY);
    _drawAxes(canvas, size, toScreenX, toScreenY);

    // Draw surface (heatmap) if enabled
    if (showSurface) {
      if (fieldType == FieldType.vector && vectorParser != null) {
        if (surfaceMode == SurfaceMode.magnitude) {
          _drawVectorMagnitudeSurface(canvas, size, toScreenX, toScreenY);
        } else {
          _drawVectorComponentSurface(
            canvas,
            size,
            toScreenX,
            toScreenY,
            surfaceMode,
          );
        }
      } else if (fieldType == FieldType.scalar && !function.isLevelSet) {
        // A level set has no height to shade — F is only a means of locating
        // the curve, so shading it would colour the plot by "distance from the
        // answer" rather than by anything the user asked for.
        _drawScalarSurface(canvas, size, toScreenX, toScreenY);
      }
    }

    if (plotMode == PlotMode.field) {
      if (fieldType == FieldType.vector && vectorParser != null) {
        _drawVectorMagnitudeField(canvas, size, toScreenX, toScreenY);
      } else {
        _drawScalarField(canvas, size, toScreenX, toScreenY);
      }
    } else {
      // A parametric expression is checked before the field, because the two
      // are written the same way. Only the variables tell them apart: `y x̂ − x ŷ`
      // is an arrow at every point, `cos(u) x̂ + sin(u) ŷ` is one point swept
      // into a curve.
      if (function.isComplex) {
        // Before everything: a complex line is not a curve of x, and sampling
        // it as one gives NaN at every point.
        _drawDomainColouring(canvas, size);
      } else if (vectorParser != null && vectorParser!.isParametric) {
        _drawParametric(canvas, toScreenX, toScreenY);
      } else if (fieldType == FieldType.vector && vectorParser != null) {
        _drawVectorField(canvas, size, toScreenX, toScreenY);
      } else {
        _drawFunction(canvas, size, toScreenX, toScreenY);
      }
    }

    // Draw contour lines if enabled
    if (showContour) {
      if (fieldType == FieldType.scalar) {
        _drawContourLines(canvas, size, toScreenX, toScreenY);
      } else if (fieldType == FieldType.vector &&
          showSurface &&
          vectorParser != null) {
        if (surfaceMode == SurfaceMode.magnitude) {
          _drawVectorMagnitudeContours(canvas, size, toScreenX, toScreenY);
        } else {
          _drawVectorComponentContours(
            canvas,
            size,
            toScreenX,
            toScreenY,
            surfaceMode,
          );
        }
      }
    }

    _drawLabels(canvas, size, toScreenX, toScreenY);
    _drawTrace(canvas, size, toScreenX, toScreenY);
  }

  /// Resolution of the heatmap lattice. Samples are taken at cell *corners*,
  /// so this is `gridCount + 1` points across.
  static const int _heatmapGrid = 40;

  /// Sample [valueAt] on the corner lattice.
  ///
  /// Corners, not cell centres: a centre sample can only colour its cell flat,
  /// which is what made the heatmap a grid of blocks. Corners are shared
  /// between neighbouring cells, so colour can be interpolated across each.
  List<List<double>> _sampleHeatmap(double Function(double, double) valueAt) {
    return <List<double>>[
      for (int i = 0; i <= _heatmapGrid; i++)
        <double>[
          for (int j = 0; j <= _heatmapGrid; j++)
            () {
              final double x = xMin + (xMax - xMin) * i / _heatmapGrid;
              final double y = yMin + (yMax - yMin) * j / _heatmapGrid;
              try {
                return valueAt(x, y);
              } catch (_) {
                return double.nan;
              }
            }(),
        ],
    ];
  }

  /// Fill the plot with colour interpolated between the corner samples.
  ///
  /// One [Canvas.drawVertices] for the whole lattice rather than 1,600
  /// rectangles: fewer draw calls, and the colour is continuous within a cell
  /// instead of a flat block. Cells touching a non-finite sample are skipped,
  /// which leaves a hole where the function is undefined rather than painting
  /// a misleading colour there.
  void _fillSmoothHeatmap(
    Canvas canvas,
    Size size,
    List<List<double>> corners,
    double minVal,
    double maxVal,
  ) {
    final double span = maxVal > minVal ? maxVal - minVal : 1.0;
    final double cellWidth = size.width / _heatmapGrid;
    final double cellHeight = size.height / _heatmapGrid;

    Color shade(double v) =>
        plotColormap(((v - minVal) / span).clamp(0.0, 1.0));

    final List<Offset> positions = <Offset>[];
    final List<Color> colors = <Color>[];

    for (int i = 0; i < _heatmapGrid; i++) {
      for (int j = 0; j < _heatmapGrid; j++) {
        final double v00 = corners[i][j];
        final double v10 = corners[i + 1][j];
        final double v11 = corners[i + 1][j + 1];
        final double v01 = corners[i][j + 1];
        if (!v00.isFinite || !v10.isFinite || !v11.isFinite || !v01.isFinite) {
          continue;
        }

        final double left = i * cellWidth;
        final double right = (i + 1) * cellWidth;
        // y grows upward in data space and downward on screen.
        final double bottom = size.height - j * cellHeight;
        final double top = size.height - (j + 1) * cellHeight;

        final Offset p00 = Offset(left, bottom);
        final Offset p10 = Offset(right, bottom);
        final Offset p11 = Offset(right, top);
        final Offset p01 = Offset(left, top);

        final Color c00 = shade(v00);
        final Color c10 = shade(v10);
        final Color c11 = shade(v11);
        final Color c01 = shade(v01);

        // Both triangles share the p00-p11 diagonal with matching colours, so
        // no seam shows along it.
        positions.addAll(<Offset>[p00, p10, p11, p00, p11, p01]);
        colors.addAll(<Color>[c00, c10, c11, c00, c11, c01]);
      }
    }

    if (positions.isEmpty) return;

    final Vertices vertices = Vertices(
      VertexMode.triangles,
      positions,
      colors: colors,
    );
    // BlendMode.dst keeps the vertex colours; the paint contributes nothing.
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  void _drawScalarSurface(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final parser = function;
    if (!parser.usesY) return;

    final List<List<double>> corners = _sampleHeatmap(
      (x, y) => parser.evaluate(x, y),
    );

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    for (final List<double> column in corners) {
      for (final double v in column) {
        if (!v.isFinite) continue;
        minVal = min(minVal, v);
        maxVal = max(maxVal, v);
      }
    }
    if (!minVal.isFinite || !maxVal.isFinite) return;
    if (minVal == maxVal) maxVal = minVal + 1;

    _fillSmoothHeatmap(canvas, size, corners, minVal, maxVal);
    _drawColorbar(canvas, size, minVal, maxVal);
  }

  void _drawVectorMagnitudeSurface(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final VectorFieldParser? field = vectorParser;
    if (field == null) return;

    // Honour surfaceMode when sampling. The scale used to be computed from the
    // selected component while the fill always drew |F|, so choosing a
    // component rescaled the colours without changing what was drawn.
    double valueAt(double x, double y) {
      switch (surfaceMode) {
        case SurfaceMode.x:
        case SurfaceMode.y:
        case SurfaceMode.z:
          return field.componentValue(surfaceMode, x, y).abs();
        case SurfaceMode.magnitude:
        case SurfaceMode.none:
          return field.magnitude(x, y);
      }
    }

    final List<List<double>> corners = _sampleHeatmap(valueAt);

    double maxMag = 0;
    for (final List<double> column in corners) {
      for (final double v in column) {
        if (v.isFinite) maxMag = max(maxMag, v);
      }
    }
    if (maxMag == 0) maxMag = 1;

    _fillSmoothHeatmap(canvas, size, corners, 0, maxMag);
    _drawColorbar(canvas, size, 0, maxMag);
  }

  void _drawVectorComponentSurface(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    SurfaceMode mode,
  ) {
    final VectorFieldParser? field = vectorParser;
    if (field == null) return;

    final List<List<double>> corners = _sampleHeatmap(
      (x, y) => field.componentValue(mode, x, y),
    );

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    for (final List<double> column in corners) {
      for (final double v in column) {
        if (!v.isFinite) continue;
        minVal = min(minVal, v);
        maxVal = max(maxVal, v);
      }
    }
    if (!minVal.isFinite || !maxVal.isFinite) return;
    if (minVal == maxVal) maxVal = minVal + 1;

    _fillSmoothHeatmap(canvas, size, corners, minVal, maxVal);
    _drawColorbar(canvas, size, minVal, maxVal);
  }

  void _drawVectorMagnitudeContours(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    if (vectorParser == null) return;

    const gridSize = 60;
    const numContours = 15;

    // Build grid of magnitude values
    List<List<double>> grid = [];
    double maxMag = 0;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = xMin + (xMax - xMin) * i / gridSize;
        final y = yMin + (yMax - yMin) * j / gridSize;
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

    // Draw contour lines using marching squares
    for (int level = 0; level < numContours; level++) {
      final threshold = maxMag * (level + 1) / (numContours + 1);
      final normalizedLevel = threshold / maxMag;
      final color = plotColormap(normalizedLevel);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      _drawContourLevelGeneric(
        canvas,
        size,
        grid,
        threshold,
        paint,
        toScreenX,
        toScreenY,
        0,
        maxMag,
      );
    }
  }

  void _drawVectorComponentContours(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    SurfaceMode mode,
  ) {
    if (vectorParser == null) return;

    const gridSize = 60;
    const numContours = 15;

    List<List<double>> grid = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = xMin + (xMax - xMin) * i / gridSize;
        final y = yMin + (yMax - yMin) * j / gridSize;
        final val = vectorParser!.componentValue(mode, x, y);
        if (val.isFinite) {
          row.add(val);
          minVal = min(minVal, val);
          maxVal = max(maxVal, val);
        } else {
          row.add(0);
        }
      }
      grid.add(row);
    }

    if (minVal == maxVal) return;

    for (int level = 0; level < numContours; level++) {
      final threshold =
          minVal + (maxVal - minVal) * (level + 1) / (numContours + 1);
      final normalizedLevel = (threshold - minVal) / (maxVal - minVal);
      final color = plotColormap(normalizedLevel);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      _drawContourLevelGeneric(
        canvas,
        size,
        grid,
        threshold,
        paint,
        toScreenX,
        toScreenY,
        minVal,
        maxVal,
      );
    }
  }

  void _drawContourLevelGeneric(
    Canvas canvas,
    Size size,
    List<List<double>> grid,
    double threshold,
    Paint paint,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    double minVal,
    double maxVal,
  ) {
    final gridSize = grid.length - 1;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final v0 = grid[i][j];
        final v1 = grid[i + 1][j];
        final v2 = grid[i + 1][j + 1];
        final v3 = grid[i][j + 1];

        // Marching squares case
        int caseIndex = 0;
        if (v0 >= threshold) caseIndex |= 1;
        if (v1 >= threshold) caseIndex |= 2;
        if (v2 >= threshold) caseIndex |= 4;
        if (v3 >= threshold) caseIndex |= 8;

        if (caseIndex == 0 || caseIndex == 15) continue;

        final x0 = xMin + (xMax - xMin) * i / gridSize;
        final x1 = xMin + (xMax - xMin) * (i + 1) / gridSize;
        final y0 = yMin + (yMax - yMin) * j / gridSize;
        final y1 = yMin + (yMax - yMin) * (j + 1) / gridSize;

        // Interpolate edge crossings
        List<Offset> points = [];

        // Bottom edge (v0 - v1)
        if ((v0 >= threshold) != (v1 >= threshold)) {
          final t = (threshold - v0) / (v1 - v0);
          points.add(Offset(toScreenX(x0 + t * (x1 - x0)), toScreenY(y0)));
        }
        // Right edge (v1 - v2)
        if ((v1 >= threshold) != (v2 >= threshold)) {
          final t = (threshold - v1) / (v2 - v1);
          points.add(Offset(toScreenX(x1), toScreenY(y0 + t * (y1 - y0))));
        }
        // Top edge (v2 - v3)
        if ((v2 >= threshold) != (v3 >= threshold)) {
          final t = (threshold - v3) / (v2 - v3);
          points.add(Offset(toScreenX(x0 + t * (x1 - x0)), toScreenY(y1)));
        }
        // Left edge (v3 - v0)
        if ((v3 >= threshold) != (v0 >= threshold)) {
          final t = (threshold - v0) / (v3 - v0);
          points.add(Offset(toScreenX(x0), toScreenY(y0 + t * (y1 - y0))));
        }

        // Draw lines between pairs of points
        if (points.length >= 2) {
          canvas.drawLine(points[0], points[1], paint);
        }
        if (points.length >= 4) {
          canvas.drawLine(points[2], points[3], paint);
        }
      }
    }
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final theme = plotTheme;
    final gridPaint =
        Paint()
          ..color = theme.grid
          ..strokeWidth = 1.2;
    final subGridPaint =
        Paint()
          ..color = theme.subGrid
          ..strokeWidth = 0.8;
    final rangeX = (xMax - xMin).abs();
    final rangeY = (yMax - yMin).abs();
    final spacingX = _calculateGridSpacing(rangeX, 8);
    final spacingY = _calculateGridSpacing(rangeY, 8);
    final subSpacingX = spacingX / 5;
    final subSpacingY = spacingY / 5;
    final subXPixel = subSpacingX * size.width / rangeX;
    final subYPixel = subSpacingY * size.height / rangeY;

    for (
      double x = (xMin / spacingX).floor() * spacingX;
      x <= xMax;
      x += subSpacingX
    ) {
      if (subXPixel >= 12) {
        canvas.drawLine(
          Offset(toScreenX(x), 0),
          Offset(toScreenX(x), size.height),
          subGridPaint,
        );
      }
    }
    for (
      double y = (yMin / spacingY).floor() * spacingY;
      y <= yMax;
      y += subSpacingY
    ) {
      if (subYPixel >= 12) {
        canvas.drawLine(
          Offset(0, toScreenY(y)),
          Offset(size.width, toScreenY(y)),
          subGridPaint,
        );
      }
    }
    for (
      double x = (xMin / spacingX).floor() * spacingX;
      x <= xMax;
      x += spacingX
    ) {
      canvas.drawLine(
        Offset(toScreenX(x), 0),
        Offset(toScreenX(x), size.height),
        gridPaint,
      );
    }
    for (
      double y = (yMin / spacingY).floor() * spacingY;
      y <= yMax;
      y += spacingY
    ) {
      canvas.drawLine(
        Offset(0, toScreenY(y)),
        Offset(size.width, toScreenY(y)),
        gridPaint,
      );
    }
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final theme = plotTheme;
    final axisPaint =
        Paint()
          ..color = theme.axis
          ..strokeWidth = 2;
    final axisGlowPaint =
        Paint()
          ..color = theme.axis.withValues(alpha: 0.35)
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final tickPaint =
        Paint()
          ..color = theme.tick
          ..strokeWidth = 1;

    if (yMin <= 0 && yMax >= 0) {
      final y0 = toScreenY(0);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), axisGlowPaint);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), axisPaint);
    }
    if (xMin <= 0 && xMax >= 0) {
      final x0 = toScreenX(0);
      canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), axisGlowPaint);
      canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), axisPaint);
    }

    final rangeX = (xMax - xMin).abs();
    final rangeY = (yMax - yMin).abs();
    final spacingX = _calculateGridSpacing(rangeX, 8);
    final spacingY = _calculateGridSpacing(rangeY, 8);
    for (
      double x = (xMin / spacingX).ceil() * spacingX;
      x <= xMax;
      x += spacingX
    ) {
      if (x.abs() > 0.001 && yMin <= 0 && yMax >= 0) {
        final y0 = toScreenY(0).clamp(10.0, size.height - 10);
        canvas.drawLine(
          Offset(toScreenX(x), y0 - 5),
          Offset(toScreenX(x), y0 + 5),
          tickPaint,
        );
      }
    }
    for (
      double y = (yMin / spacingY).ceil() * spacingY;
      y <= yMax;
      y += spacingY
    ) {
      if (y.abs() > 0.001 && xMin <= 0 && xMax >= 0) {
        final x0 = toScreenX(0).clamp(10.0, size.width - 10);
        canvas.drawLine(
          Offset(x0 - 5, toScreenY(y)),
          Offset(x0 + 5, toScreenY(y)),
          tickPaint,
        );
      }
    }
  }

  /// Draw the path traced by sweeping u.
  ///
  /// A parametric curve is free to double back, cross itself or close, so it
  /// is drawn as the sequence of points it is rather than as a value per x.
  /// The one thing inherited from the ordinary curve path is how a gap is
  /// handled: a break lifts the pen instead of joining across it.
  void _drawParametric(
    Canvas canvas,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final VectorFieldParser? field = vectorParser;
    if (field == null) return;

    final paint =
        Paint()
          ..color = plotTheme.seriesColor(0)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool started = false;
    for (final ParametricPoint? p in sampleParametricCurve(field, u: uRange)) {
      if (p == null) {
        started = false;
        continue;
      }
      final Offset at = Offset(toScreenX(p.x), toScreenY(p.y));
      if (started) {
        path.lineTo(at.dx, at.dy);
      } else {
        path.moveTo(at.dx, at.dy);
        started = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Colour every point of the window by the value of f there.
  ///
  /// The whole plot is the picture, so this is drawn on the lattice the
  /// heatmap already uses: one `drawVertices` for the grid, colour
  /// interpolated across each cell rather than a flat block per cell, and any
  /// cell touching an undefined sample left out so a pole is a hole instead of
  /// a wrong colour.
  void _drawDomainColouring(Canvas canvas, Size size) {
    const int grid = _domainGrid;
    final double cellW = size.width / grid;
    final double cellH = size.height / grid;

    // Sampled at the corners, which are shared between neighbouring cells, so
    // the colour runs continuously across the picture.
    final List<List<Color?>> corner = <List<Color?>>[
      for (int i = 0; i <= grid; i++)
        <Color?>[
          for (int j = 0; j <= grid; j++)
            () {
              final double x = xMin + (xMax - xMin) * i / grid;
              final double y = yMin + (yMax - yMin) * j / grid;
              final Complex w = function.evaluateComplex(x, y);
              if (!w.real.isFinite || !w.imag.isFinite) return null;
              return domainColor(w.phase, w.magnitude);
            }(),
        ],
    ];

    final List<Offset> positions = <Offset>[];
    final List<Color> colors = <Color>[];
    for (int i = 0; i < grid; i++) {
      for (int j = 0; j < grid; j++) {
        final Color? a = corner[i][j];
        final Color? b = corner[i + 1][j];
        final Color? c = corner[i + 1][j + 1];
        final Color? d = corner[i][j + 1];
        if (a == null || b == null || c == null || d == null) continue;

        final double left = i * cellW;
        final double right = left + cellW;
        // Screen y runs down while the imaginary axis runs up.
        final double bottom = size.height - j * cellH;
        final double top = bottom - cellH;

        positions.addAll(<Offset>[
          Offset(left, bottom),
          Offset(right, bottom),
          Offset(right, top),
          Offset(left, bottom),
          Offset(right, top),
          Offset(left, top),
        ]);
        colors.addAll(<Color>[a, b, c, a, c, d]);
      }
    }
    if (positions.isEmpty) return;

    final Vertices vertices = Vertices(
      VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
    vertices.dispose();
  }

  /// Cells across the window for domain colouring.
  ///
  /// Finer than the heatmap's lattice because this *is* the plot rather than a
  /// backdrop for one — the eye reads the shape of the colour directly, so a
  /// coarse grid shows as blocky bands around a zero.
  static const int _domainGrid = 96;

  void _drawFunction(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final List<PlotExpression> curves =
        functions.isEmpty ? <PlotExpression>[function] : functions;

    for (int series = 0; series < curves.length; series++) {
      final parser = curves[series];
      if (!parser.isValid) continue;
      final Color color = plotTheme.seriesColor(series);
      if (parser.isLevelSet) {
        // An inequality is an area, so it is shaded first and the boundary
        // drawn over it.
        if (parser.relation.isRegion) {
          _drawRegion(canvas, size, toScreenX, toScreenY, parser, color);
        }
        _drawImplicitCurve(canvas, toScreenX, toScreenY, parser, color);
      } else {
        _drawOneCurve(canvas, toScreenX, toScreenY, parser, color);
      }
    }
  }

  /// Shade every point that satisfies an inequality.
  ///
  /// Sampled on its own lattice rather than reusing the heatmap grid: this is
  /// a yes/no test, so the only thing that matters is how closely the edge is
  /// followed, and the boundary curve is drawn over the top anyway.
  void _drawRegion(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    PlotExpression parser,
    Color color,
  ) {
    const int cells = 110;
    final double dx = (xMax - xMin) / cells;
    final double dy = (yMax - yMin) / cells;
    final double cellW = size.width / cells + 1;
    final double cellH = size.height / cells + 1;

    // One path of many small rectangles, filled once. A fill per cell would
    // be 22,500 draw calls a frame.
    final Path region = Path();
    for (int i = 0; i < cells; i++) {
      final double x = xMin + (i + 0.5) * dx;
      for (int j = 0; j < cells; j++) {
        final double y = yMin + (j + 0.5) * dy;
        if (!parser.relation.holds(parser.evaluate(x, y))) continue;
        region.addRect(
          Rect.fromLTWH(
            toScreenX(xMin + i * dx),
            toScreenY(yMin + (j + 1) * dy),
            cellW,
            cellH,
          ),
        );
      }
    }

    // Strong enough to read as a shaded region rather than a change of
    // background. An unbounded region like x² + y² ≥ 1 covers nearly the whole
    // plot, and at a light tint that is indistinguishable from no shading at
    // all — there is no unshaded area left to compare it against.
    canvas.drawPath(
      region,
      Paint()
        ..color = color.withValues(alpha: 0.38)
        ..style = PaintingStyle.fill,
    );
  }

  /// Trace an equation's solution set.
  ///
  /// An implicit curve cannot be walked left to right like y = f(x): it may
  /// double back, close on itself, or come in several pieces, so it is found
  /// by contouring where F changes sign rather than by sampling a height.
  void _drawImplicitCurve(
    Canvas canvas,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    PlotExpression parser,
    Color color,
  ) {
    final List<LevelSegment> segments = marchingSquares(
      parser,
      xMin,
      xMax,
      yMin,
      yMax,
      resolution:
          interacting
              ? marchingSquaresDraggingResolution
              : marchingSquaresDefaultResolution,
    );
    if (segments.isEmpty) return;

    final Paint paint =
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    // Loose segments, not one path: the curve may be several disjoint loops,
    // and joining them would draw lines across the gaps between.
    //
    // A strict inequality excludes its own boundary, which is drawn dashed to
    // say so — the convention every textbook uses for an open edge.
    //
    // Measured along the curve in screen pixels, not counted in segments:
    // marching squares emits sub-pixel pieces, so dropping every other one
    // left a line that was still solid to the eye.
    final bool dashed = !parser.relation.includesBoundary;
    // Long enough to read as a broken line at a glance. At 11 the gaps were
    // there but easy to miss, which defeats the point: the dashes are the only
    // thing saying the boundary is excluded.
    const double dashPeriod = 20.0;
    const double dashOn = 0.5;
    double travelled = 0;

    for (final LevelSegment s in segments) {
      final Offset a = Offset(toScreenX(s.x1), toScreenY(s.y1));
      final Offset b = Offset(toScreenX(s.x2), toScreenY(s.y2));
      if (dashed) {
        travelled += (b - a).distance;
        if (travelled % dashPeriod > dashPeriod * dashOn) continue;
      }
      canvas.drawLine(a, b, paint);
    }
  }

  void _drawOneCurve(
    Canvas canvas,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
    PlotExpression parser,
    Color color,
  ) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 1000;
    bool started = false;
    double? lastY;

    for (int i = 0; i <= steps; i++) {
      final x = xMin + i * (xMax - xMin) / steps;
      double y;
      try {
        y = parser.evaluate(x, 0);
      } catch (e) {
        started = false;
        lastY = null;
        continue;
      }

      if (y.isFinite && y.abs() < 1e6) {
        if (lastY != null && (y - lastY).abs() > (yMax - yMin) * 0.5) {
          started = false;
        }
        if (!started) {
          path.moveTo(toScreenX(x), toScreenY(y));
          started = true;
        } else {
          path.lineTo(toScreenX(x), toScreenY(y));
        }
        lastY = y;
      } else {
        started = false;
        lastY = null;
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Crosshair readout: "what is f(2.3)?".
  ///
  /// The most calculator-shaped thing a plot can do, and the reason it reads
  /// every curve rather than only the first — comparing two functions at the
  /// same x is most of why you would draw them together.
  void _drawTrace(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final double? tx = traceX;
    if (tx == null || tx < xMin || tx > xMax) return;
    if (fieldType != FieldType.scalar || plotMode != PlotMode.function) return;

    final List<PlotExpression> curves =
        functions.isEmpty ? <PlotExpression>[function] : functions;

    final double sx = toScreenX(tx);
    canvas.drawLine(
      Offset(sx, 0),
      Offset(sx, size.height),
      Paint()
        ..color = plotTheme.axis
        ..strokeWidth = 1,
    );

    final List<({Color color, double y})> hits = <({Color color, double y})>[];
    for (int i = 0; i < curves.length; i++) {
      final PlotExpression c = curves[i];
      if (!c.isValid) continue;
      final Color color = plotTheme.seriesColor(i);

      // An equation has to be solved for y, not evaluated. Evaluating it gives
      // F(x, 0) — how far (x, 0) is from satisfying the equation — which is
      // neither a point on the curve nor the y the reader is asking for, and
      // it produced a marker floating off the circle entirely.
      //
      // Solving can also return nothing, which is the right answer: the unit
      // circle simply has no y at x = 1.33.
      final List<double> ys =
          c.isLevelSet
              ? levelSetYAt(c, tx, yMin, yMax)
              : <double>[c.evaluate(tx, 0)];

      for (final double y in ys) {
        if (!y.isFinite) continue;
        hits.add((color: color, y: y));

        final double sy = toScreenY(y);
        if (sy < -20 || sy > size.height + 20) continue;
        // A ring rather than a dot so the curve stays visible underneath.
        canvas.drawCircle(Offset(sx, sy), 5, Paint()..color = color);
        canvas.drawCircle(
          Offset(sx, sy),
          5,
          Paint()
            ..color = plotTheme.label
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    final CurveFeature? feature = traceFeature;
    if (feature != null && feature.y.isFinite) {
      final double fy = toScreenY(feature.y);
      if (fy > -20 && fy < size.height + 20) {
        canvas.drawCircle(
          Offset(sx, fy),
          9,
          Paint()
            ..color = plotTheme.label
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    if (hits.isEmpty) return;
    _drawTraceLabel(canvas, size, sx, tx, hits, feature);
  }

  void _drawTraceLabel(
    Canvas canvas,
    Size size,
    double sx,
    double tx,
    List<({Color color, double y})> hits,
    CurveFeature? feature,
  ) {
    drawReadoutBox(canvas, size, plotTheme, <ReadoutLine>[
      (
        // Naming what was snapped to is the point: "root" answers the
        // question, where a bare coordinate only reports a position.
        color: feature == null ? plotTheme.label : plotTheme.axis,
        text:
            feature == null
                ? 'x = ${formatReadout(tx)}'
                : '${feature.label}  x = ${formatReadout(tx)}',
        bold: feature != null,
      ),
      for (final h in hits)
        (color: h.color, text: formatReadout(h.y), bold: false),
    ], anchorX: sx);
  }

  void _drawScalarField(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final parser = function;
    const gridCount = 25;
    final circleRadius = min(size.width, size.height) / gridCount / 3;

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;
        try {
          final val = parser.evaluate(x, y);
          if (val.isFinite) {
            minVal = min(minVal, val);
            maxVal = max(maxVal, val);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }

    if (minVal == maxVal) maxVal = minVal + 1;

    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;

        try {
          final val = parser.evaluate(x, y);
          if (!val.isFinite) continue;

          final normalized = (val - minVal) / (maxVal - minVal);
          final color = plotColormap(normalized);

          canvas.drawCircle(
            Offset(toScreenX(x), toScreenY(y)),
            circleRadius,
            Paint()..color = color.withValues(alpha: 0.8),
          );
          // ignore: empty_catches
        } catch (e) {}
      }
    }

    if (surfaceMode == SurfaceMode.none) {
      _drawColorbar(canvas, size, minVal, maxVal);
    }
  }

  void _drawContourLines(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final parser = function;
    const gridSize = 100;
    const numContours = 15;

    // Build grid of values
    List<List<double>> grid = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    for (int i = 0; i <= gridSize; i++) {
      List<double> row = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = xMin + (xMax - xMin) * i / gridSize;
        final y = yMin + (yMax - yMin) * j / gridSize;
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

    // Draw contour lines using marching squares
    for (int level = 0; level < numContours; level++) {
      final threshold =
          minVal + (maxVal - minVal) * (level + 1) / (numContours + 1);
      final normalizedLevel = (threshold - minVal) / (maxVal - minVal);
      final color = plotColormap(normalizedLevel);

      final paint =
          Paint()
            ..color = color
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      _drawContourLevel(
        canvas,
        size,
        grid,
        threshold,
        paint,
        toScreenX,
        toScreenY,
      );
    }
  }

  void _drawContourLevel(
    Canvas canvas,
    Size size,
    List<List<double>> grid,
    double threshold,
    Paint paint,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final gridSize = grid.length - 1;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final v0 = grid[i][j];
        final v1 = grid[i + 1][j];
        final v2 = grid[i + 1][j + 1];
        final v3 = grid[i][j + 1];

        // Marching squares case
        int caseIndex = 0;
        if (v0 >= threshold) caseIndex |= 1;
        if (v1 >= threshold) caseIndex |= 2;
        if (v2 >= threshold) caseIndex |= 4;
        if (v3 >= threshold) caseIndex |= 8;

        if (caseIndex == 0 || caseIndex == 15) continue;

        final x0 = xMin + (xMax - xMin) * i / gridSize;
        final x1 = xMin + (xMax - xMin) * (i + 1) / gridSize;
        final y0 = yMin + (yMax - yMin) * j / gridSize;
        final y1 = yMin + (yMax - yMin) * (j + 1) / gridSize;

        // Interpolate edge crossings
        List<Offset> points = [];

        // Bottom edge (v0 - v1)
        if ((v0 >= threshold) != (v1 >= threshold)) {
          final t = (threshold - v0) / (v1 - v0);
          points.add(Offset(toScreenX(x0 + t * (x1 - x0)), toScreenY(y0)));
        }
        // Right edge (v1 - v2)
        if ((v1 >= threshold) != (v2 >= threshold)) {
          final t = (threshold - v1) / (v2 - v1);
          points.add(Offset(toScreenX(x1), toScreenY(y0 + t * (y1 - y0))));
        }
        // Top edge (v2 - v3)
        if ((v2 >= threshold) != (v3 >= threshold)) {
          final t = (threshold - v3) / (v2 - v3);
          points.add(Offset(toScreenX(x0 + t * (x1 - x0)), toScreenY(y1)));
        }
        // Left edge (v3 - v0)
        if ((v3 >= threshold) != (v0 >= threshold)) {
          final t = (threshold - v0) / (v3 - v0);
          points.add(Offset(toScreenX(x0), toScreenY(y0 + t * (y1 - y0))));
        }

        // Draw lines between pairs of points
        if (points.length >= 2) {
          canvas.drawLine(points[0], points[1], paint);
        }
        if (points.length >= 4) {
          canvas.drawLine(points[2], points[3], paint);
        }
      }
    }
  }

  void _drawVectorField(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    if (vectorParser == null) return;

    const gridCount = 20;
    final arrowLength = min(size.width, size.height) / gridCount / 1.0;

    double maxMag = 0;
    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;
        final mag = vectorParser!.magnitude(x, y);
        if (mag.isFinite) maxMag = max(maxMag, mag);
      }
    }

    if (maxMag == 0) maxMag = 1;

    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;

        final (fx, fy, fz) = vectorParser!.evaluate(x, y);
        double vx = fx;
        double vy = fy;
        double mag = vectorParser!.magnitude(x, y);

        if (surfaceMode == SurfaceMode.x) {
          vx = fx;
          vy = 0;
          mag = fx.abs();
        } else if (surfaceMode == SurfaceMode.y) {
          vx = 0;
          vy = fy;
          mag = fy.abs();
        } else if (surfaceMode == SurfaceMode.z) {
          vx = 0;
          vy = 0;
          mag = fz.abs();
        }

        if (!mag.isFinite || mag < 1e-10) continue;

        final normalized = mag / maxMag;
        final color = plotColormap(normalized);

        final scale = mag == 0 ? 0 : 1 / mag;
        final nx = vx * scale;
        final ny = vy * scale;

        final startX = toScreenX(x);
        final startY = toScreenY(y);
        final endX = startX + nx * arrowLength;
        final endY = startY - ny * arrowLength;

        final paint =
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round;

        canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

        // Arrowhead
        final angle = atan2(-(endY - startY), endX - startX);
        const headLength = 6.0;
        const headAngle = 0.5;

        canvas.drawLine(
          Offset(endX, endY),
          Offset(
            endX - headLength * cos(angle - headAngle),
            endY + headLength * sin(angle - headAngle),
          ),
          paint,
        );
        canvas.drawLine(
          Offset(endX, endY),
          Offset(
            endX - headLength * cos(angle + headAngle),
            endY + headLength * sin(angle + headAngle),
          ),
          paint,
        );
      }
    }

    if (surfaceMode == SurfaceMode.none) {
      _drawColorbar(canvas, size, 0, maxMag);
    }
  }

  void _drawVectorMagnitudeField(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    if (vectorParser == null) return;

    const gridCount = 25;
    final circleRadius = min(size.width, size.height) / gridCount / 3;

    double maxMag = 0;
    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;
        final mag = vectorParser!.magnitude(x, y);
        if (mag.isFinite) maxMag = max(maxMag, mag);
      }
    }

    if (maxMag == 0) maxMag = 1;

    for (int i = 0; i <= gridCount; i++) {
      for (int j = 0; j <= gridCount; j++) {
        final x = xMin + (xMax - xMin) * i / gridCount;
        final y = yMin + (yMax - yMin) * j / gridCount;

        final mag = vectorParser!.magnitude(x, y);
        if (!mag.isFinite) continue;

        final normalized = mag / maxMag;
        final color = plotColormap(normalized);

        canvas.drawCircle(
          Offset(toScreenX(x), toScreenY(y)),
          circleRadius,
          Paint()..color = color.withValues(alpha: 0.8),
        );
      }
    }

    if (surfaceMode == SurfaceMode.none) {
      _drawColorbar(canvas, size, 0, maxMag);
    }
  }

  /// The scale for whatever the colours mean, across the top of the plot.
  ///
  /// Horizontal, in the top right corner. The left edge belongs to the
  /// parameter panels and the top left to the mode label, and a plot is wider
  /// than it is tall, so a bar laid along the width has room for its labels
  /// without taking a bite out of the drawing area.
  void _drawColorbar(Canvas canvas, Size size, double minVal, double maxVal) {
    final theme = plotTheme;
    const double barHeight = 12.0;
    const double margin = 10.0;
    // Bounded so it neither dominates a wide plot nor vanishes on a narrow
    // one, and always leaves room for a label at each end.
    final double barWidth = (size.width * 0.45).clamp(80.0, 220.0);

    final barRect = Rect.fromLTWH(
      size.width - barWidth - margin,
      margin,
      barWidth,
      barHeight,
    );

    // One gradient, not a line per pixel: sampling the ramp per column
    // quantises it to the bar's width in steps, which reads as banding.
    canvas.drawRect(
      barRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: plotColormapStops,
        ).createShader(barRect),
    );

    canvas.drawRect(
      barRect,
      Paint()
        ..color = theme.colorbarBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final textStyle = TextStyle(color: theme.colorbarText, fontSize: 10);
    TextPainter label(double v) => TextPainter(
      text: TextSpan(text: _formatNumber(v), style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    // Low at the left end, high at the right, each outside the bar so neither
    // sits on top of the ramp it is labelling.
    final minTp = label(minVal);
    minTp.paint(
      canvas,
      Offset(barRect.left - minTp.width - 4, barRect.center.dy - 6),
    );
    label(
      maxVal,
    ).paint(canvas, Offset(barRect.right + 4, barRect.center.dy - 6));
  }

  void _drawLabels(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final theme = plotTheme;
    final textStyle = TextStyle(color: theme.label, fontSize: 12);
    final rangeX = (xMax - xMin).abs();
    final rangeY = (yMax - yMin).abs();
    final spacingX = _calculateGridSpacing(rangeX, 8);
    final spacingY = _calculateGridSpacing(rangeY, 8);

    for (
      double x = (xMin / spacingX).ceil() * spacingX;
      x <= xMax;
      x += spacingX
    ) {
      if (x.abs() > 0.001 && yMin <= 0 && yMax >= 0) {
        final y0 = toScreenY(0).clamp(20.0, size.height - 20);
        final tp = TextPainter(
          text: TextSpan(text: _formatNumber(x), style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(toScreenX(x) - tp.width / 2, y0 + 8));
      }
    }
    for (
      double y = (yMin / spacingY).ceil() * spacingY;
      y <= yMax;
      y += spacingY
    ) {
      if (y.abs() > 0.001 && xMin <= 0 && xMax >= 0) {
        final x0 = toScreenX(0).clamp(30.0, size.width - 30);
        final tp = TextPainter(
          text: TextSpan(text: _formatNumber(y), style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x0 - tp.width - 8, toScreenY(y) - tp.height / 2),
        );
      }
    }
  }

  String _formatNumber(double n) {
    if (n.abs() < 0.001) return '0';
    if (n == n.roundToDouble() && n.abs() < 100) return n.toInt().toString();
    if (n.abs() >= 100) return n.toStringAsFixed(0);
    if (n.abs() >= 10) return n.toStringAsFixed(1);
    return n.toStringAsFixed(2);
  }

  double _calculateGridSpacing(double range, int maxLines) {
    // `range <= 0` is false for NaN, so this guard used to let a NaN window
    // through to floor(), which throws rather than returning a garbage double.
    // A window that bad is a bug upstream, but the painter should not take the
    // whole frame down over it.
    if (!range.isFinite || range <= 0 || maxLines <= 0) return 1;
    final roughStep = range / maxLines;
    if (!roughStep.isFinite || roughStep <= 0) return 1;
    final exponent = log(roughStep) / ln10;
    if (!exponent.isFinite) return 1;
    final magnitude = pow(10, exponent.floor()).toDouble();
    if (!magnitude.isFinite || magnitude <= 0) return 1;
    final normalized = roughStep / magnitude;
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  @override
  bool shouldRepaint(covariant Plot2DPainter old) =>
      old.xMin != xMin ||
      old.xMax != xMax ||
      old.yMin != yMin ||
      old.yMax != yMax ||
      old.function != function ||
      old.plotMode != plotMode ||
      old.fieldType != fieldType ||
      old.showContour != showContour ||
      old.surfaceMode != surfaceMode ||
      old.traceX != traceX ||
      old.traceFeature != traceFeature ||
      old.functions != functions ||
      old.colors != colors;
}
