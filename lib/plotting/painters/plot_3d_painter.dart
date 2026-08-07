import 'dart:typed_data';
import 'dart:ui' show Vertices, VertexMode;
import 'dart:math';
import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../models/enums.dart';
import '../models/point_3d.dart';
import '../parsers/plot_expression.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/colormap.dart';
import '../utils/level_set.dart';
import '../utils/plot_cache.dart';
import '../utils/plot_theme.dart';

// Helper classes for 3D rendering
class Quad {
  final Point3D p1, p2, p3, p4;
  final double avgDepth;
  final double avgValue;

  /// Value at each corner. Filling a cell with one colour taken from
  /// [avgValue] makes every grid cell a flat block, which reads as banding at
  /// any grid resolution; keeping the corners lets the colour be interpolated
  /// across the cell instead.
  final double v1, v2, v3, v4;

  Quad(
    this.p1,
    this.p2,
    this.p3,
    this.p4,
    this.avgDepth,
    this.avgValue, {
    double? v1,
    double? v2,
    double? v3,
    double? v4,
  }) : v1 = v1 ?? avgValue,
       v2 = v2 ?? avgValue,
       v3 = v3 ?? avgValue,
       v4 = v4 ?? avgValue;
}

class FieldPoint3D {
  final Point3D point;
  final double value;

  FieldPoint3D(this.point, this.value);
}

class Arrow3D {
  final Point3D start;
  final double dx, dy, dz;
  final double magnitude;
  final double surfaceValue;

  Arrow3D(
    this.start,
    this.dx,
    this.dy,
    this.dz,
    this.magnitude,
    this.surfaceValue,
  );
}

/// Accumulates triangles so a whole surface is one draw call.
///
/// Each quad used to be its own [Canvas.drawVertices]; a 50x50 surface is 2,500
/// of them per frame, which dominated rotation. Triangles are appended in the
/// order they should be painted, so the depth sort still holds, and the batch
/// is submitted once at the end.
class _VertexBatch {
  final List<Offset> _positions = <Offset>[];
  final List<Color> _colors = <Color>[];

  bool get isEmpty => _positions.isEmpty;

  void addTriangle(
    Offset a,
    Offset b,
    Offset c,
    Color ca,
    Color cb,
    Color cc,
  ) {
    _positions.addAll(<Offset>[a, b, c]);
    _colors.addAll(<Color>[ca, cb, cc]);
  }

  /// Two triangles sharing the o1-o3 diagonal, with matching corner colours so
  /// no seam shows along it.
  void addQuad(
    Offset o1,
    Offset o2,
    Offset o3,
    Offset o4,
    Color c1,
    Color c2,
    Color c3,
    Color c4,
  ) {
    _positions.addAll(<Offset>[o1, o2, o3, o1, o3, o4]);
    _colors.addAll(<Color>[c1, c2, c3, c1, c3, c4]);
  }

  void paint(Canvas canvas) {
    if (_positions.isEmpty) return;
    final Vertices vertices = Vertices(
      VertexMode.triangles,
      _positions,
      colors: _colors,
    );
    // BlendMode.dst keeps the vertex colours; the paint contributes nothing.
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }
}


/// A back-to-front drawing list holding both triangles and line segments.
///
/// The floor grid used to be painted before the surface, unconditionally, so
/// the surface always won — the floor never appeared in front of it even where
/// it was nearer the camera, and a surface dipping below the floor was drawn
/// over ground that should have hidden it. Sorting both kinds of primitive
/// together is what makes them occlude each other.
///
/// Consecutive triangles are still submitted as one `drawVertices`; the batch
/// is only flushed when a line has to be drawn between them, so a scene with a
/// few hundred grid segments costs a few hundred draw calls rather than one per
/// triangle.
class _DepthScene {
  final List<double> _depths = <double>[];
  final List<bool> _isLine = <bool>[];

  // Triangles: six screen floats and three packed colours each.
  final List<double> _triXY = <double>[];
  final List<int> _triColor = <int>[];

  // Lines: four screen floats each, plus a paint.
  final List<double> _lineXY = <double>[];
  final List<Paint> _linePaint = <Paint>[];

  void addTriangle(
    Offset a,
    Offset b,
    Offset c,
    int ca,
    int cb,
    int cc,
    double depth,
  ) {
    _depths.add(depth);
    _isLine.add(false);
    _triXY.addAll(<double>[a.dx, a.dy, b.dx, b.dy, c.dx, c.dy]);
    _triColor.addAll(<int>[ca, cb, cc]);
  }

  void addLine(Offset a, Offset b, Paint paint, double depth) {
    _depths.add(depth);
    _isLine.add(true);
    _lineXY.addAll(<double>[a.dx, a.dy, b.dx, b.dy]);
    _linePaint.add(paint);
  }

  void paint(Canvas canvas) {
    final int n = _depths.length;
    if (n == 0) return;

    final List<int> order = List<int>.generate(n, (i) => i);
    order.sort((a, b) => _depths[b].compareTo(_depths[a]));

    // Running indices into the per-kind buffers, so a primitive's data can be
    // found from its position among its own kind.
    final List<int> triIndex = List<int>.filled(n, -1);
    final List<int> lineIndex = List<int>.filled(n, -1);
    int t = 0;
    int l = 0;
    for (int i = 0; i < n; i++) {
      if (_isLine[i]) {
        lineIndex[i] = l++;
      } else {
        triIndex[i] = t++;
      }
    }

    final List<double> batchXY = <double>[];
    final List<int> batchColor = <int>[];

    void flush() {
      if (batchXY.isEmpty) return;
      final Vertices vertices = Vertices.raw(
        VertexMode.triangles,
        Float32List.fromList(batchXY),
        colors: Int32List.fromList(batchColor),
      );
      canvas.drawVertices(vertices, BlendMode.dst, Paint());
      vertices.dispose();
      batchXY.clear();
      batchColor.clear();
    }

    for (final int i in order) {
      if (_isLine[i]) {
        flush();
        final int o = lineIndex[i] * 4;
        canvas.drawLine(
          Offset(_lineXY[o], _lineXY[o + 1]),
          Offset(_lineXY[o + 2], _lineXY[o + 3]),
          _linePaint[lineIndex[i]],
        );
      } else {
        final int o = triIndex[i] * 6;
        final int c = triIndex[i] * 3;
        batchXY.addAll(_triXY.getRange(o, o + 6));
        batchColor.addAll(_triColor.getRange(c, c + 3));
      }
    }
    flush();
  }
}

class Plot3DPainter extends CustomPainter {
  final PlotExpression function;
  final bool is3DFunction;
  final double rotationX, rotationZ;
  final double rangeX, rangeY, rangeZ; // Changed: rangeZ is now a parameter
  final double panX, panY;
  final PlotMode plotMode;
  final FieldType fieldType;
  final VectorFieldParser? vectorParser;
  final bool showContour;
  final SurfaceMode surfaceMode;
  final AppColors colors;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  Plot3DPainter({
    required this.function,
    required this.is3DFunction,
    required this.rotationX,
    required this.rotationZ,
    required this.rangeX,
    required this.rangeY,
    required this.rangeZ, // New: explicit rangeZ parameter
    required this.panX,
    required this.panY,
    required this.plotMode,
    required this.fieldType,
    this.vectorParser,
    required this.showContour,
    required this.surfaceMode,
    required this.colors,
    required this.plotTheme,
  });

  // Remove the getter since rangeZ is now a parameter
  // double get rangeZ => (rangeX + rangeY) / 2;

  // double get rangeZ => (rangeX + rangeY) / 2;
  double get scaleX => 200.0 / rangeX;
  double get scaleY => 200.0 / rangeY;
  double get scaleZ => 200.0 / rangeZ;
  PlotThemeData get _theme => plotTheme;

  @override
  void paint(Canvas canvas, Size size) {
    const focalLength = 500.0;
    final bool showSurface = surfaceMode != SurfaceMode.none;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // A scalar height surface draws the floor itself, interleaved by depth.
    // Drawing it here as well would put an un-occluded copy underneath.
    // Both height-surface paths interleave the floor themselves. Note there
    // are two: _drawSurfaceWithJetColormap runs when a surface mode is
    // selected, _drawSurface when it is not — and surfaceMode defaults to
    // none, so the plain one is what an ordinary z = f(x, y) actually uses.
    final bool floorDrawnBySurface =
        fieldType == FieldType.scalar &&
        !function.isLevelSet &&
        is3DFunction &&
        plotMode != PlotMode.field;

    if (!floorDrawnBySurface) {
      _drawFloorGrid(canvas, size, focalLength);
    }
    _drawAxes(canvas, size, focalLength);
    _drawFloorBoundary(canvas, size, focalLength);

    // Handle different visualization modes
    if (fieldType == FieldType.vector && vectorParser != null) {
      // Vector field visualization
      if (showSurface && !vectorParser!.is3D) {
        // Show magnitude surface for 2D vector fields
        if (surfaceMode == SurfaceMode.magnitude) {
          _drawVectorMagnitudeSurface3D(canvas, size, focalLength);
        } else {
          _drawVectorComponentSurface3D(canvas, size, focalLength, surfaceMode);
        }

        // Draw contours on the magnitude surface if enabled
        if (showContour) {
          if (surfaceMode == SurfaceMode.magnitude) {
            _drawVectorMagnitudeContours3D(canvas, size, focalLength);
          } else {
            _drawVectorComponentContours3D(
              canvas,
              size,
              focalLength,
              surfaceMode,
            );
          }
        }

        // Optionally draw vectors on top
        if (plotMode == PlotMode.function) {
          _drawVectorField3D(canvas, size, focalLength);
        }
      } else {
        // Default vector field visualization
        if (plotMode == PlotMode.field) {
          _drawVectorMagnitudeField3D(canvas, size, focalLength);
        } else {
          _drawVectorField3D(canvas, size, focalLength);
        }
      }
    } else {
      // Scalar field visualization
      if (function.isLevelSet) {
        // An equation defines a surface, not a height: there is no z = f(x,y)
        // to sample, so it is contoured rather than sampled.
        _drawLevelSurface(canvas, size, focalLength);
      } else if (is3DFunction) {
        if (showSurface) {
          // Show surface with jet colormap (magnitude coloring)
          _drawSurfaceWithJetColormap(canvas, size, focalLength);

          // Draw contours on the surface if enabled
          if (showContour) {
            _drawSurfaceContours(canvas, size, focalLength);
          }
        } else {
          // Default visualization
          if (plotMode == PlotMode.field) {
            _drawScalarField3D(canvas, size, focalLength);
          } else {
            _drawSurface(canvas, size, focalLength);
          }

          // Draw contours if enabled
          if (showContour) {
            if (plotMode == PlotMode.field) {
              _drawContourLines3D(canvas, size, focalLength);
            } else {
              _drawSurfaceContours(canvas, size, focalLength);
            }
          }
        }
      } else {
        // 1D function (f(x) only)
        _drawStandingCurve(canvas, size, focalLength);
      }
    }

    canvas.restore();
  }

  /// Draw the surface where an equation is satisfied — a sphere for
  /// x²+y²+z²=1, a plane for x+y+z=0, and so on.
  ///
  /// Contoured with marching tetrahedra: a level set has no height to sample,
  /// and may close on itself or come in several pieces, so it has to be found
  /// by looking for sign changes through the volume.
  void _drawLevelSurface(Canvas canvas, Size size, double focalLength) {
    // Geometry and colour are cached: neither depends on the camera, and a
    // hyperboloid marches to ~33,000 triangles, so rebuilding per frame was
    // the whole cost of a drag.
    final LevelMesh mesh = cachedLevelMesh(
      function,
      <double>[-rangeX, rangeX, -rangeY, rangeY, -rangeZ, rangeZ],
      40,
      () => <({
        double ax,
        double ay,
        double az,
        double bx,
        double by,
        double bz,
        double cx,
        double cy,
        double cz,
      })>[
        for (final LevelTriangle t in marchingTetrahedra(
          function,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
        ))
          (
            ax: t.a.x,
            ay: t.a.y,
            az: t.a.z,
            bx: t.b.x,
            by: t.b.y,
            bz: t.b.z,
            cx: t.c.x,
            cy: t.c.y,
            cz: t.c.z,
          ),
      ],
      scaleX,
      scaleY,
      scaleZ,
      // Colour by height, so the surface carries a readable quantity even
      // though every point on it satisfies the same equation.
      (double z) =>
          plotColormap(
            ((z + rangeZ) / (2 * rangeZ)).clamp(0.0, 1.0),
          ).toARGB32(),
    );

    final int count = mesh.triangleCount;
    if (count == 0) return;

    // Rotation is four scalars per frame, not a cos/sin pair per vertex.
    // Point3D.rotateX and rotateZ each recompute both, which for 100,000
    // vertices came to ~200,000 trig calls a frame.
    final double cx = cos(rotationX);
    final double sx = sin(rotationX);
    final double cz = cos(rotationZ);
    final double sz = sin(rotationZ);
    final double halfW = size.width / 2;
    final double halfH = size.height / 2;

    // Project every vertex once into flat buffers, keeping each triangle's
    // depth for the painter's algorithm.
    final Float32List screen = Float32List(count * 6);
    final Float64List depth = Float64List(count);
    final Float32List world = mesh.world;

    for (int t = 0; t < count; t++) {
      final int w = t * 9;
      final int o = t * 6;
      double depthSum = 0;
      for (int v = 0; v < 3; v++) {
        final double x = world[w + v * 3];
        final double y = world[w + v * 3 + 1];
        final double z = world[w + v * 3 + 2];

        // Azimuth first, then elevation — a turntable. Spinning after the
        // tilt would turn the model about an axis that is no longer
        // screen-vertical, which reads as tumbling rather than rotating.
        final double x1 = x * cz - y * sz;
        final double y1 = x * sz + y * cz;
        final double y2 = y1 * cx - z * sx;
        final double z2 = y1 * sx + z * cx;

        final double scale = focalLength / (focalLength + y2);
        screen[o + v * 2] = halfW + x1 * scale + panX;
        screen[o + v * 2 + 1] = halfH - z2 * scale + panY;
        depthSum += y2;
      }
      depth[t] = depthSum / 3;
    }

    // Sort indices, not triangles: moving an int is cheaper than moving nine
    // floats, and the vertex buffers stay put.
    final List<int> order = List<int>.generate(count, (i) => i);
    order.sort((a, b) => depth[b].compareTo(depth[a]));

    final Float32List positions = Float32List(count * 6);
    final Int32List colors = Int32List(count * 3);
    for (int i = 0; i < count; i++) {
      final int src = order[i];
      positions.setRange(i * 6, i * 6 + 6, screen, src * 6);
      colors.setRange(i * 3, i * 3 + 3, mesh.colors, src * 3);
    }

    final Vertices vertices = Vertices.raw(
      VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();

    _drawColorbar3D(canvas, size, -rangeZ, rangeZ);
  }

  void _drawSurfaceWithJetColormap(
    Canvas canvas,
    Size size,
    double focalLength,
  ) {
    const gridSize = 50;
    final parser = function;

    List<List<Point3D?>> points = [];
    List<List<double>> zValues = [];

    double minZ = double.infinity;
    double maxZ = double.negativeInfinity;

    // Heights are cached: rotating changes where the camera sees the surface
    // from, not the surface, so re-walking the expression tree every frame was
    // wasted work.
    final List<List<double>> sampled = cachedHeightGrid(
      parser,
      rangeX,
      rangeY,
      gridSize,
    );

    for (int i = 0; i <= gridSize; i++) {
      List<Point3D?> row = [];
      List<double> zRow = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        final double z = sampled[i][j];
        if (!z.isFinite) {
          row.add(null);
          zRow.add(double.nan);
          continue;
        }
        // Outside the z window: keep the value so neighbouring cells still
        // know which way the surface left, but draw nothing here.
        if (z < -rangeZ || z > rangeZ) {
          row.add(null);
          zRow.add(z);
          continue;
        }

        minZ = min(minZ, z);
        maxZ = max(maxZ, z);

        row.add(
          Point3D(
            x * scaleX,
            y * scaleY,
            z * scaleZ,
          ).rotateZ(rotationZ).rotateX(rotationX),
        );
        zRow.add(z);
      }
      points.add(row);
      zValues.add(zRow);
    }

    if (minZ == maxZ) maxZ = minZ + 1;

    // Build quads
    List<Quad> quads = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final p1 = points[i][j];
        final p2 = points[i + 1][j];
        final p3 = points[i + 1][j + 1];
        final p4 = points[i][j + 1];

        if (p1 == null || p2 == null || p3 == null || p4 == null) continue;

        final avgY = (p1.y + p2.y + p3.y + p4.y) / 4;
        final avgValue =
            (zValues[i][j] +
                zValues[i + 1][j] +
                zValues[i + 1][j + 1] +
                zValues[i][j + 1]) /
            4;
        quads.add(
          Quad(
            p1,
            p2,
            p3,
            p4,
            avgY,
            avgValue,
            v1: zValues[i][j],
            v2: zValues[i + 1][j],
            v3: zValues[i + 1][j + 1],
            v4: zValues[i][j + 1],
          ),
        );
      }
    }

    // Sort by depth (painter's algorithm)
    // The floor joins the same ordered list as the surface, so the two
    // occlude each other instead of the surface always winning.
    final _DepthScene scene = _DepthScene();
    _addFloorGridTo(scene, size, focalLength);

    int shade(double v) =>
        plotColormap(
          ((v - minZ) / (maxZ - minZ)).clamp(0.0, 1.0),
        ).toARGB32();

    for (final quad in quads) {
      final o1 = quad.p1.project(focalLength, size, panX, panY);
      final o2 = quad.p2.project(focalLength, size, panX, panY);
      final o3 = quad.p3.project(focalLength, size, panX, panY);
      final o4 = quad.p4.project(focalLength, size, panX, panY);

      // Colour per corner, interpolated across the cell. A single colour from
      // the cell average makes each cell a flat block, which reads as banding
      // however fine the grid.
      final int c1 = shade(quad.v1);
      final int c2 = shade(quad.v2);
      final int c3 = shade(quad.v3);
      final int c4 = shade(quad.v4);

      // Two triangles sharing the p1-p3 diagonal, each carrying its own depth
      // so a cell can be sorted against a grid segment passing under it.
      final double d1 = (quad.p1.y + quad.p2.y + quad.p3.y) / 3;
      final double d2 = (quad.p1.y + quad.p3.y + quad.p4.y) / 3;
      scene.addTriangle(o1, o2, o3, c1, c2, c3, d1);
      scene.addTriangle(o1, o3, o4, c1, c3, c4, d2);
    }

    scene.paint(canvas);

    // Draw colorbar
    _drawColorbar3D(canvas, size, minZ, maxZ);
  }

  void _drawVectorMagnitudeSurface3D(
    Canvas canvas,
    Size size,
    double focalLength,
  ) {
    if (vectorParser == null || vectorParser!.is3D) return;

    const gridSize = 50;

    List<List<Point3D?>> points = [];
    List<List<double>> magValues = [];
    List<List<bool>> validMag = [];

    double maxMag = 0;

    // First pass: compute magnitudes and find max
    for (int i = 0; i <= gridSize; i++) {
      List<Point3D?> row = [];
      List<double> magRow = [];
      List<bool> validRow = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);

        final mag = vectorParser!.magnitude(x, y);

        if (!mag.isFinite) {
          row.add(null);
          magRow.add(0);
          validRow.add(false);
          continue;
        }

        maxMag = max(maxMag, mag);
        magRow.add(mag);
        row.add(null);
        validRow.add(true);
      }
      points.add(row);
      magValues.add(magRow);
      validMag.add(validRow);
    }

    if (maxMag == 0) maxMag = 1;

    // Scale factor to make surface height reasonable
    final zScale = rangeZ / maxMag;

    // Second pass: create 3D points
    for (int i = 0; i <= gridSize; i++) {
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        final mag = magValues[i][j];
        if (!validMag[i][j]) continue;

        final z = mag * zScale;
        if (z < -rangeZ || z > rangeZ) {
          points[i][j] = null;
          continue;
        }

        points[i][j] = Point3D(
          x * scaleX,
          y * scaleY,
          z * scaleZ,
        ).rotateZ(rotationZ).rotateX(rotationX);
      }
    }

    // Build quads for painter's algorithm
    List<Quad> quads = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final p1 = points[i][j];
        final p2 = points[i + 1][j];
        final p3 = points[i + 1][j + 1];
        final p4 = points[i][j + 1];

        if (p1 == null || p2 == null || p3 == null || p4 == null) continue;

        final avgY = (p1.y + p2.y + p3.y + p4.y) / 4;
        final avgValue =
            (magValues[i][j] +
                magValues[i + 1][j] +
                magValues[i + 1][j + 1] +
                magValues[i][j + 1]) /
            4;
        quads.add(
          Quad(
            p1,
            p2,
            p3,
            p4,
            avgY,
            avgValue,
            v1: magValues[i][j],
            v2: magValues[i + 1][j],
            v3: magValues[i + 1][j + 1],
            v4: magValues[i][j + 1],
          ),
        );
      }
    }

    // Sort by depth (painter's algorithm)
    quads.sort((a, b) => b.avgDepth.compareTo(a.avgDepth));

    // Draw quads
    final _VertexBatch batch = _VertexBatch();
    for (final quad in quads) {
      final o1 = quad.p1.project(focalLength, size, panX, panY);
      final o2 = quad.p2.project(focalLength, size, panX, panY);
      final o3 = quad.p3.project(focalLength, size, panX, panY);
      final o4 = quad.p4.project(focalLength, size, panX, panY);

      // Colour per corner, interpolated across the cell.
      Color shade(double v) => plotColormap((v / maxMag).clamp(0.0, 1.0));

      batch.addQuad(
        o1,
        o2,
        o3,
        o4,
        shade(quad.v1),
        shade(quad.v2),
        shade(quad.v3),
        shade(quad.v4),
      );
    }
    batch.paint(canvas);

    _drawColorbar3D(canvas, size, 0, maxMag);
  }

  void _drawVectorComponentSurface3D(
    Canvas canvas,
    Size size,
    double focalLength,
    SurfaceMode mode,
  ) {
    if (vectorParser == null || vectorParser!.is3D) return;

    const gridSize = 50;

    List<List<Point3D?>> points = [];
    List<List<double>> values = [];

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    double maxAbs = 0;

    for (int i = 0; i <= gridSize; i++) {
      List<Point3D?> row = [];
      List<double> valRow = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);

        final val = vectorParser!.componentValue(mode, x, y);
        if (!val.isFinite) {
          row.add(null);
          valRow.add(double.nan);
          continue;
        }

        minVal = min(minVal, val);
        maxVal = max(maxVal, val);
        maxAbs = max(maxAbs, val.abs());
        valRow.add(val);
        row.add(null);
      }
      points.add(row);
      values.add(valRow);
    }

    if (maxAbs == 0 || !minVal.isFinite || !maxVal.isFinite) return;

    final zScale = rangeZ / maxAbs;

    for (int i = 0; i <= gridSize; i++) {
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        final val = values[i][j];
        if (!val.isFinite) continue;

        final z = val * zScale;
        if (z < -rangeZ || z > rangeZ) {
          points[i][j] = null;
          continue;
        }

        points[i][j] = Point3D(
          x * scaleX,
          y * scaleY,
          z * scaleZ,
        ).rotateZ(rotationZ).rotateX(rotationX);
      }
    }

    List<Quad> quads = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final p1 = points[i][j];
        final p2 = points[i + 1][j];
        final p3 = points[i + 1][j + 1];
        final p4 = points[i][j + 1];

        if (p1 == null || p2 == null || p3 == null || p4 == null) continue;

        final avgY = (p1.y + p2.y + p3.y + p4.y) / 4;
        final avgValue =
            (values[i][j] +
                values[i + 1][j] +
                values[i + 1][j + 1] +
                values[i][j + 1]) /
            4;
        quads.add(
          Quad(
            p1,
            p2,
            p3,
            p4,
            avgY,
            avgValue,
            v1: values[i][j],
            v2: values[i + 1][j],
            v3: values[i + 1][j + 1],
            v4: values[i][j + 1],
          ),
        );
      }
    }

    quads.sort((a, b) => b.avgDepth.compareTo(a.avgDepth));

    final _VertexBatch batch = _VertexBatch();
    for (final quad in quads) {
      final o1 = quad.p1.project(focalLength, size, panX, panY);
      final o2 = quad.p2.project(focalLength, size, panX, panY);
      final o3 = quad.p3.project(focalLength, size, panX, panY);
      final o4 = quad.p4.project(focalLength, size, panX, panY);

      // Colour per corner, interpolated across the cell.
      Color shade(double v) =>
          plotColormap(((v - minVal) / (maxVal - minVal)).clamp(0.0, 1.0));

      batch.addQuad(
        o1,
        o2,
        o3,
        o4,
        shade(quad.v1),
        shade(quad.v2),
        shade(quad.v3),
        shade(quad.v4),
      );
    }
    batch.paint(canvas);

    _drawColorbar3D(canvas, size, minVal, maxVal);
  }

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
      final color = plotColormap(normalizedLevel);

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
      final color = plotColormap(normalizedLevel);

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
          final proj1 = p1.project(focalLength, size, panX, panY);
          final proj2 = p2.project(focalLength, size, panX, panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, panX, panY);
          final proj4 = p4.project(focalLength, size, panX, panY);
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
          final proj1 = p1.project(focalLength, size, panX, panY);
          final proj2 = p2.project(focalLength, size, panX, panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, panX, panY);
          final proj4 = p4.project(focalLength, size, panX, panY);
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
      final color = plotColormap(normalizedLevel);

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

  void _drawSurfaceContours(Canvas canvas, Size size, double focalLength) {
    final parser = function;
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
      final color = plotColormap(normalizedLevel);

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
          final proj1 = p1.project(focalLength, size, panX, panY);
          final proj2 = p2.project(focalLength, size, panX, panY);
          canvas.drawLine(proj1, proj2, paint);
        }
        if (points3D.length >= 4) {
          final p3 = points3D[2].rotateZ(rotationZ).rotateX(rotationX);
          final p4 = points3D[3].rotateZ(rotationZ).rotateX(rotationX);
          final proj3 = p3.project(focalLength, size, panX, panY);
          final proj4 = p4.project(focalLength, size, panX, panY);
          canvas.drawLine(proj3, proj4, paint);
        }
      }
    }
  }

  double _calculateGridSpacing(double range) {
    final magnitude = pow(10, (log(range * 2) / ln10).floor()).toDouble();
    final normalized = (range * 2) / magnitude;
    if (normalized < 2) return magnitude / 5;
    if (normalized < 5) return magnitude / 2;
    return magnitude;
  }

  /// Add the floor grid to [scene] as depth-sorted segments.
  ///
  /// Each grid line is cut into pieces because a single line spans the whole
  /// floor: its near end and far end have very different depths, so one depth
  /// per line cannot say whether the surface crosses in front of it.
  void _addFloorGridTo(_DepthScene scene, Size size, double focalLength) {
    final theme = plotTheme;
    final Paint gridPaint =
        Paint()
          ..color = theme.subGrid
          ..strokeWidth = 0.8;

    final double gridSpacingX = _calculateGridSpacing(rangeX);
    final double gridSpacingY = _calculateGridSpacing(rangeY);

    // Enough pieces that the depth varies smoothly along a line, few enough
    // that the sort stays cheap.
    const int pieces = 16;
    final Rect bounds = Rect.fromLTWH(0, 0, size.width, size.height);

    void addRun(double ax, double ay, double bx, double by) {
      for (int k = 0; k < pieces; k++) {
        final double t0 = k / pieces;
        final double t1 = (k + 1) / pieces;
        final Point3D p0 = Point3D(
          (ax + (bx - ax) * t0) * scaleX,
          (ay + (by - ay) * t0) * scaleY,
          0,
        ).rotateZ(rotationZ).rotateX(rotationX);
        final Point3D p1 = Point3D(
          (ax + (bx - ax) * t1) * scaleX,
          (ay + (by - ay) * t1) * scaleY,
          0,
        ).rotateZ(rotationZ).rotateX(rotationX);

        final clipped = _clipLineToRect(
          p0.project(focalLength, size, panX, panY),
          p1.project(focalLength, size, panX, panY),
          bounds,
        );
        if (clipped == null) continue;
        scene.addLine(clipped.$1, clipped.$2, gridPaint, (p0.y + p1.y) / 2);
      }
    }

    for (double i = -rangeX; i <= rangeX; i += gridSpacingX / 5) {
      addRun(i, -rangeY, i, rangeY);
    }
    for (double i = -rangeY; i <= rangeY; i += gridSpacingY / 5) {
      addRun(-rangeX, i, rangeX, i);
    }
  }

  void _drawFloorGrid(Canvas canvas, Size size, double focalLength) {
    final theme = plotTheme;
    final gridPaint =
        Paint()
          ..color = theme.grid
          ..strokeWidth = 1.2;
    final subGridPaint =
        Paint()
          ..color = theme.subGrid
          ..strokeWidth = 0.8;

    final gridSpacingX = _calculateGridSpacing(rangeX);
    final gridSpacingY = _calculateGridSpacing(rangeY);

    for (double i = -rangeX; i <= rangeX; i += gridSpacingX / 5) {
      var start = Point3D(
        i * scaleX,
        -rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      var end = Point3D(
        i * scaleX,
        rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(canvas, size, focalLength, start, end, subGridPaint);
    }
    for (double i = -rangeY; i <= rangeY; i += gridSpacingY / 5) {
      var start = Point3D(
        -rangeX * scaleX,
        i * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      var end = Point3D(
        rangeX * scaleX,
        i * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(canvas, size, focalLength, start, end, subGridPaint);
    }
    for (double i = -rangeX; i <= rangeX; i += gridSpacingX) {
      var start = Point3D(
        i * scaleX,
        -rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      var end = Point3D(
        i * scaleX,
        rangeY * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(canvas, size, focalLength, start, end, gridPaint);
    }
    for (double i = -rangeY; i <= rangeY; i += gridSpacingY) {
      var start = Point3D(
        -rangeX * scaleX,
        i * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      var end = Point3D(
        rangeX * scaleX,
        i * scaleY,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      _drawClippedLine(canvas, size, focalLength, start, end, gridPaint);
    }
  }

  void _drawFloorBoundary(Canvas canvas, Size size, double focalLength) {
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
    final startProj = start.project(focalLength, size, panX, panY);
    final endProj = end.project(focalLength, size, panX, panY);
    final clipped = _clipLineToRect(
      startProj,
      endProj,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    if (clipped != null) canvas.drawLine(clipped.$1, clipped.$2, paint);
  }

  void _drawAxes(Canvas canvas, Size size, double focalLength) {
    final theme = plotTheme;
    final gridSpacingX = _calculateGridSpacing(rangeX);
    final gridSpacingY = _calculateGridSpacing(rangeY);
    final gridSpacingZ = _calculateGridSpacing(rangeZ);

    final axes = [
      (theme.axisX, 'X', Point3D(1, 0, 0), gridSpacingX, rangeX, scaleX),
      (theme.axisY, 'Y', Point3D(0, 1, 0), gridSpacingY, rangeY, scaleY),
      (theme.axisZ, 'Z', Point3D(0, 0, 1), gridSpacingZ, rangeZ, scaleZ),
    ];

    for (final axis in axes) {
      final color = axis.$1;
      final label = axis.$2;
      final dir = axis.$3;
      final gridSpacing = axis.$4;
      final range = axis.$5;
      final scale = axis.$6;

      final axisPaint =
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;
      final axisGlowPaint =
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final negPoint = Point3D(
        -dir.x * range * 2 * scale,
        -dir.y * range * 2 * scale,
        -dir.z * range * 2 * scale,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final posPoint = Point3D(
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
          axisGlowPaint,
        );
        _drawClippedLine(
          canvas,
          size,
          focalLength,
          negPoint,
          posPoint,
          axisPaint,
        );

      final arrowPos = Point3D(
        dir.x * range * 0.9 * scale,
        dir.y * range * 0.9 * scale,
        dir.z * range * 0.9 * scale,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final arrowProj = arrowPos.project(focalLength, size, panX, panY);

      if (_isPointInRect(
        arrowProj,
        Rect.fromLTWH(-20, -20, size.width + 40, size.height + 40),
      )) {
        final origin = const Point3D(
          0,
          0,
          0,
        ).rotateZ(rotationZ).rotateX(rotationX);
        final originProj = origin.project(focalLength, size, panX, panY);
        final direction = Offset(
          arrowProj.dx - originProj.dx,
          arrowProj.dy - originProj.dy,
        );
        final length = direction.distance;

        if (length > 0) {
          final normalized = direction / length;
          final perpendicular = Offset(-normalized.dy, normalized.dx);
          const arrowSize = 10.0;
          canvas.drawPath(
            Path()
              ..moveTo(
                arrowProj.dx -
                    normalized.dx * arrowSize +
                    perpendicular.dx * arrowSize / 2,
                arrowProj.dy -
                    normalized.dy * arrowSize +
                    perpendicular.dy * arrowSize / 2,
              )
              ..lineTo(arrowProj.dx, arrowProj.dy)
              ..lineTo(
                arrowProj.dx -
                    normalized.dx * arrowSize -
                    perpendicular.dx * arrowSize / 2,
                arrowProj.dy -
                    normalized.dy * arrowSize -
                    perpendicular.dy * arrowSize / 2,
              ),
            axisPaint..style = PaintingStyle.stroke,
          );
        }

        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(arrowProj.dx + 8, arrowProj.dy - 8));
      }

        final tickPaint =
            Paint()
              ..color = theme.tick
              ..strokeWidth = 1;

      for (double t = -range; t <= range; t += gridSpacing) {
        if (t.abs() < gridSpacing * 0.1) continue;

        final tickPos = Point3D(
          dir.x * t * scale,
          dir.y * t * scale,
          dir.z * t * scale,
        ).rotateZ(rotationZ).rotateX(rotationX);
        final tickProj = tickPos.project(focalLength, size, panX, panY);

        if (!_isPointInRect(
          tickProj,
          Rect.fromLTWH(0, 0, size.width, size.height),
        )) {
          continue;
        }

        const tickLen = 5.0;
        Point3D tick1End, tick2End;

        if (label == 'X') {
          tick1End = Point3D(
            t * scale,
            tickLen,
            0,
          ).rotateZ(rotationZ).rotateX(rotationX);
          tick2End = Point3D(
            t * scale,
            0,
            tickLen,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else if (label == 'Y') {
          tick1End = Point3D(
            tickLen,
            t * scale,
            0,
          ).rotateZ(rotationZ).rotateX(rotationX);
          tick2End = Point3D(
            0,
            t * scale,
            tickLen,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else {
          tick1End = Point3D(
            tickLen,
            0,
            t * scale,
          ).rotateZ(rotationZ).rotateX(rotationX);
          tick2End = Point3D(
            0,
            tickLen,
            t * scale,
          ).rotateZ(rotationZ).rotateX(rotationX);
        }

        canvas.drawLine(
          tickProj,
          tick1End.project(focalLength, size, panX, panY),
          tickPaint,
        );
        canvas.drawLine(
          tickProj,
          tick2End.project(focalLength, size, panX, panY),
          tickPaint,
        );

        Point3D labelPos;
        if (label == 'X') {
          labelPos = Point3D(
            t * scale,
            -15,
            -10,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else if (label == 'Y') {
          labelPos = Point3D(
            -15,
            t * scale,
            -10,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else {
          labelPos = Point3D(
            -15,
            -15,
            t * scale,
          ).rotateZ(rotationZ).rotateX(rotationX);
        }

        final labelProj = labelPos.project(focalLength, size, panX, panY);
        if (_isPointInRect(
          labelProj,
          Rect.fromLTWH(0, 0, size.width, size.height),
        )) {
            final ltp = TextPainter(
              text: TextSpan(
                text: _formatNumber(t),
                style: TextStyle(
                  color: theme.label,
                  fontSize: 10,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
          ltp.paint(
            canvas,
            Offset(labelProj.dx - ltp.width / 2, labelProj.dy - ltp.height / 2),
          );
        }
      }
    }
  }

  String _formatNumber(double n) {
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

  void _drawSurface(Canvas canvas, Size size, double focalLength) {
    const gridSize = 50;
    final parser = function;

    List<List<Point3D?>> points = [];
    List<List<double>> zValues = [];

    for (int i = 0; i <= gridSize; i++) {
      List<Point3D?> row = [];
      List<double> zRow = [];
      for (int j = 0; j <= gridSize; j++) {
        final x = -rangeX + (2 * rangeX * i / gridSize);
        final y = -rangeY + (2 * rangeY * j / gridSize);
        double z;
        try {
          z = parser.evaluate(x, y);
          if (!z.isFinite) {
            row.add(null);
            zRow.add(0);
            continue;
          }
          if (z < -rangeZ || z > rangeZ) {
            row.add(null);
            zRow.add(z);
            continue;
          }
        } catch (e) {
          row.add(null);
          zRow.add(0);
          continue;
        }

        row.add(
          Point3D(
            x * scaleX,
            y * scaleY,
            z * scaleZ,
          ).rotateZ(rotationZ).rotateX(rotationX),
        );
        zRow.add(z);
      }
      points.add(row);
      zValues.add(zRow);
    }

    // Colour against the surface's own range, not the axis range. Normalising
    // by rangeZ assumes the data is symmetric about zero and fills the axis:
    // x²+y² is neither, so its values landed in the upper half of the ramp and
    // the surface came out nearly one colour regardless of magnitude.
    double surfaceMin = double.infinity;
    double surfaceMax = double.negativeInfinity;
    for (final List<double> zRow in zValues) {
      for (final double z in zRow) {
        if (!z.isFinite) continue;
        if (z < surfaceMin) surfaceMin = z;
        if (z > surfaceMax) surfaceMax = z;
      }
    }
    // A flat surface has no range to map; keep it mid-ramp rather than
    // dividing by zero.
    final double surfaceSpan =
        (surfaceMax - surfaceMin).isFinite && surfaceMax > surfaceMin
            ? surfaceMax - surfaceMin
            : 0.0;

    List<Quad> quads = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final p1 = points[i][j];
        final p2 = points[i + 1][j];
        final p3 = points[i + 1][j + 1];
        final p4 = points[i][j + 1];

        if (p1 == null || p2 == null || p3 == null || p4 == null) continue;

        final avgY = (p1.y + p2.y + p3.y + p4.y) / 4;
        final avgValue =
            (zValues[i][j] +
                zValues[i + 1][j] +
                zValues[i + 1][j + 1] +
                zValues[i][j + 1]) /
            4;
        quads.add(
          Quad(
            p1,
            p2,
            p3,
            p4,
            avgY,
            avgValue,
            v1: zValues[i][j],
            v2: zValues[i + 1][j],
            v3: zValues[i + 1][j + 1],
            v4: zValues[i][j + 1],
          ),
        );
      }
    }

    quads.sort((a, b) => b.avgDepth.compareTo(a.avgDepth));

    // The floor joins the same ordered list as the surface, so the two occlude
    // each other rather than the surface always winning.
    final _DepthScene scene = _DepthScene();
    _addFloorGridTo(scene, size, focalLength);

    int shade(double v) => plotColormap(
      surfaceSpan > 0 ? ((v - surfaceMin) / surfaceSpan).clamp(0.0, 1.0) : 0.5,
    ).toARGB32();

    for (final quad in quads) {
      final o1 = quad.p1.project(focalLength, size, panX, panY);
      final o2 = quad.p2.project(focalLength, size, panX, panY);
      final o3 = quad.p3.project(focalLength, size, panX, panY);
      final o4 = quad.p4.project(focalLength, size, panX, panY);

      final int c1 = shade(quad.v1);
      final int c2 = shade(quad.v2);
      final int c3 = shade(quad.v3);
      final int c4 = shade(quad.v4);

      // Each half carries its own depth, so a cell can be sorted against a
      // grid segment passing beneath it rather than as one unit.
      scene.addTriangle(
        o1,
        o2,
        o3,
        c1,
        c2,
        c3,
        (quad.p1.y + quad.p2.y + quad.p3.y) / 3,
      );
      scene.addTriangle(
        o1,
        o3,
        o4,
        c1,
        c3,
        c4,
        (quad.p1.y + quad.p3.y + quad.p4.y) / 3,
      );
    }

    scene.paint(canvas);

    // A magnitude ramp needs a key, or the colours mean nothing.
    if (surfaceSpan > 0) {
      _drawColorbar3D(canvas, size, surfaceMin, surfaceMax);
    }
  }

  void _drawStandingCurve(Canvas canvas, Size size, double focalLength) {
    final parser = function;
    const steps = 300;

    final paint =
        Paint()
          ..color = colors.accent
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    final shadowPaint =
        Paint()
          ..color = colors.accent.withValues(alpha: 0.2)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    final verticalPaint =
        Paint()
          ..color = colors.accent.withValues(alpha: 0.12)
          ..strokeWidth = 1;

    final path = Path();
    final shadowPath = Path();
    bool started = false, shadowStarted = false;
    double? lastZ;

    for (int i = 0; i <= steps; i++) {
      final x = -rangeX + (2 * rangeX * i / steps);
      double z;
      try {
        z = parser.evaluate(x, 0);
        if (!z.isFinite) {
          started = false;
          shadowStarted = false;
          lastZ = null;
          continue;
        }
        if (z < -rangeZ || z > rangeZ) {
          started = false;
          shadowStarted = false;
          lastZ = null;
          continue;
        }
      } catch (e) {
        started = false;
        shadowStarted = false;
        lastZ = null;
        continue;
      }

      final point = Point3D(
        x * scaleX,
        0,
        z * scaleZ,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final shadowPoint = Point3D(
        x * scaleX,
        0,
        0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final proj = point.project(focalLength, size, panX, panY);
      final shadowProj = shadowPoint.project(focalLength, size, panX, panY);

      if (lastZ != null && (z - lastZ).abs() > rangeZ * 0.5) started = false;

      if (!started) {
        path.moveTo(proj.dx, proj.dy);
        started = true;
      } else {
        path.lineTo(proj.dx, proj.dy);
      }
      if (!shadowStarted) {
        shadowPath.moveTo(shadowProj.dx, shadowProj.dy);
        shadowStarted = true;
      } else {
        shadowPath.lineTo(shadowProj.dx, shadowProj.dy);
      }
      lastZ = z;

      if (i % 15 == 0) canvas.drawLine(proj, shadowProj, verticalPaint);
    }

    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, paint);
  }

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
          } catch (e) {}
        }
      }
    }

    if (points.isEmpty) return;
    if (minVal == maxVal) maxVal = minVal + 1;

    points.sort((a, b) => b.point.y.compareTo(a.point.y));

    for (final fp in points) {
      final proj = fp.point.project(focalLength, size, panX, panY);
      if (!_isPointInRect(proj, Rect.fromLTWH(0, 0, size.width, size.height))) {
        continue;
      }

      final normalized = (fp.value - minVal) / (maxVal - minVal);
      final color = plotColormap(normalized);

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
    if (vectorParser == null) return;

    final bool showSurface = surfaceMode != SurfaceMode.none;
    const gridCount = 8;
    final bool is3DVector = vectorParser!.is3D;

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

              final (fx, fy, fz) = vectorParser!.evaluate(x, y, z);
              double vx = fx;
              double vy = fy;
              double vz = fz;
              double surfaceValue = 0;
              double mag = vectorParser!.magnitude(x, y, z);

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

            final (fx, fy, fz) = vectorParser!.evaluate(x, y, 0);
            double vx = fx;
            double vy = fy;
            double vz = 0;
            double surfaceValue = 0;
            double mag = vectorParser!.magnitude(x, y, 0);

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
      final startPoint = (showSurface && !is3DVector)
          ? Point3D(arrow.start.x, arrow.start.y, surfaceZ * scaleZ)
          : arrow.start;
      final startRotated = startPoint.rotateZ(rotationZ).rotateX(rotationX);
      final startProj = startRotated.project(focalLength, size, panX, panY);

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
      final endProj = endRotated.project(focalLength, size, panX, panY);

      final normalized = arrow.magnitude / maxMag;
      final color = plotColormap(normalized);

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
      _drawColorbar3D(canvas, size, 0, maxMag);
    }
  }

  void _drawVectorMagnitudeField3D(
    Canvas canvas,
    Size size,
    double focalLength,
  ) {
    if (vectorParser == null) return;

    const gridCount = 10;
    final bool is3DVector = vectorParser!.is3D;

    List<FieldPoint3D> points = [];
    double maxMag = 0;

    if (is3DVector) {
      for (int i = 0; i <= gridCount; i++) {
        for (int j = 0; j <= gridCount; j++) {
          for (int k = 0; k <= gridCount; k++) {
            final x = -rangeX + (2 * rangeX * i / gridCount);
            final y = -rangeY + (2 * rangeY * j / gridCount);
            final z = -rangeZ + (2 * rangeZ * k / gridCount);

            final mag = vectorParser!.magnitude(x, y, z);
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

          final mag = vectorParser!.magnitude(x, y, 0);
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
      final proj = fp.point.project(focalLength, size, panX, panY);
      if (!_isPointInRect(proj, Rect.fromLTWH(0, 0, size.width, size.height))) {
        continue;
      }

      final normalized = fp.value / maxMag;
      final color = plotColormap(normalized);

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

    _drawColorbar3D(canvas, size, 0, maxMag);
  }

  /// Smooth colorbar with labelled ticks.
  ///
  /// The strip matches the surface: both are the continuous ramp, so a colour
  /// on the plot can be read back against the bar directly. Ticks are spaced
  /// rather than min/max only, which is what makes an intermediate value
  /// readable without counting bands.
  void _drawColorbar3D(Canvas canvas, Size size, double minVal, double maxVal) {
    const double barWidth = 15.0;
    const double barHeight = 104.0;
    const double margin = 10.0;
    const int ticks = 4;

    final Rect barRect = Rect.fromLTWH(
      margin,
      size.height / 2 - barHeight / 2,
      barWidth,
      barHeight,
    );

    // Top of the bar is the maximum, so it reads like the axis.
    for (int i = 0; i < barHeight; i++) {
      canvas.drawLine(
        Offset(barRect.left, barRect.top + i),
        Offset(barRect.right, barRect.top + i),
        Paint()..color = plotColormap(1.0 - i / barHeight),
      );
    }

    canvas.drawRect(
      barRect,
      Paint()
        ..color = _theme.colorbarBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final TextStyle textStyle = TextStyle(
      color: _theme.colorbarText,
      fontSize: 9,
    );
    for (int i = 0; i <= ticks; i++) {
      final double t = i / ticks;
      final double y = barRect.top + barHeight * t;
      final double value = maxVal - (maxVal - minVal) * t;

      canvas.drawLine(
        Offset(barRect.right, y),
        Offset(barRect.right + 3, y),
        Paint()
          ..color = _theme.colorbarBorder
          ..strokeWidth = 1,
      );

      final TextPainter tp = TextPainter(
        text: TextSpan(text: _formatNumber(value), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(barRect.right + 6, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant Plot3DPainter old) =>
      old.rotationX != rotationX ||
      old.rotationZ != rotationZ ||
      old.rangeX != rangeX ||
      old.rangeY != rangeY ||
      old.rangeZ != rangeZ || // New: check rangeZ
      old.panX != panX ||
      old.panY != panY ||
      old.function != function ||
      old.is3DFunction != is3DFunction ||
      old.plotMode != plotMode ||
      old.fieldType != fieldType ||
      old.showContour != showContour ||
      old.surfaceMode != surfaceMode ||
      old.colors != colors;
}
