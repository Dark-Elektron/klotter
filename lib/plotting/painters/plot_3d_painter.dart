import 'dart:typed_data';
import 'dart:ui' show Vertices, VertexMode;
import 'dart:math';
import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../models/enums.dart';
import '../models/point_3d.dart';
import '../models/view_fit.dart';
import '../parsers/plot_expression.dart';
import '../utils/parametric.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/colormap.dart';
import '../utils/level_set.dart';
import '../utils/plot_cache.dart';
import '../utils/plot_theme.dart';
import '../utils/readout_box.dart';
import '../utils/surface_pick.dart';

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

  void addTriangle(Offset a, Offset b, Offset c, Color ca, Color cb, Color cc) {
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
/// Somewhere depth-tagged line segments can be sent.
///
/// The floor grid and axis chrome are built the same way whoever is drawing
/// them; only what happens next differs. [_DepthScene] interleaves them with
/// batched triangles, while a level surface keeps its own packed vertex
/// buffers and merges the lines against those instead.
abstract class _LineSink {
  void addLine(Offset a, Offset b, Paint paint, double depth);
}

/// Just keeps the lines, for a caller that does its own merging.
class _LineCollector implements _LineSink {
  final List<Offset> a = <Offset>[];
  final List<Offset> b = <Offset>[];
  final List<Paint> paints = <Paint>[];
  final List<double> depths = <double>[];

  @override
  void addLine(Offset from, Offset to, Paint paint, double depth) {
    a.add(from);
    b.add(to);
    paints.add(paint);
    depths.add(depth);
  }

  int get length => depths.length;

  /// Indices ordered far to near, matching how triangles are sorted.
  List<int> get farToNear =>
      List<int>.generate(length, (i) => i)
        ..sort((x, y) => depths[y].compareTo(depths[x]));
}

class _DepthScene implements _LineSink {
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

  @override
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

  /// One surface per line of the cell, exactly as 2D draws one curve per line.
  /// [function] stays the primary entry and still drives the single-function
  /// views — vector fields, scalar fields and contours.
  final List<PlotExpression> functions;

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

  /// True when the cell is a sweep rather than something sampled over space.
  bool get _isParametric => vectorParser?.isParametric ?? false;

  /// The spans u and v are swept over when the expression is parametric.
  final ParameterRange uRange;
  final ParameterRange vRange;

  /// Where the trace marker sits, in data coordinates, or null when the plot
  /// is not being traced.
  final SurfaceHit? tracePoint;

  /// True while the plot is being dragged, pinched or spinning.
  ///
  /// A surface is sampled more finely when it is still. At rest the mesh is
  /// built once and then only redrawn, so the extra cells cost a single frame;
  /// in motion every frame pays for them, and a 50-cell surface already takes
  /// most of a 60 Hz frame.
  final bool interacting;

  Plot3DPainter({
    required this.function,
    this.functions = const <PlotExpression>[],
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
    this.uRange = defaultParameterRange,
    this.vRange = defaultParameterRange,
    this.tracePoint,
    this.interacting = false,
  });

  // Remove the getter since rangeZ is now a parameter
  // double get rangeZ => (rangeX + rangeY) / 2;

  // double get rangeZ => (rangeX + rangeY) / 2;
  /// Half-extent of the world box, in logical pixels, fitted to the viewport
  /// at the start of each paint.
  ///
  /// This was a fixed 200 whatever the canvas size. On a phone-sized panel the
  /// box then projected wider than the canvas, so the surface filled the frame
  /// edge to edge and there was no visible scene for the floor plane to sit
  /// in — which reads as the plane not overlaying in 3D, though the depth
  /// order was fine.
  double _viewExtentXY = 200.0;
  double _viewExtentZ = 200.0;

  /// Where the fitted drawing has to move to sit in the middle of the panel.
  /// Added to the user's pan, so panning still works from there.
  double _fitOffsetX = 0;
  double _fitOffsetY = 0;

  double get _panX => panX + _fitOffsetX;
  double get _panY => panY + _fitOffsetY;

  /// Distance from the eye to the projection plane.
  ///
  /// Public because picking a point out of the scene has to invert exactly the
  /// projection that drew it. Two copies of this number would drift apart and
  /// put the marker somewhere the surface is not.
  /// Scaled with the panel rather than fixed.
  ///
  /// It was a flat 500, which on a phone panel is less than the depth of the
  /// box itself — so the front-top corner sat almost at the eye, projected
  /// several times its true size, and was the first thing to run off the
  /// canvas. That corner, not the height, was what capped how big the box
  /// could be. Tying the focal length to the panel keeps the strength of the
  /// perspective the same whatever size the plot is drawn at, and leaves the
  /// near corner somewhere the fit can work with.
  static double focalLengthFor(Size size) =>
      max(size.width, size.height) * 1.15;

  /// How far past the box an axis arrow reaches, as a fraction of the range.
  ///
  /// The real edge of the drawing: the box corners are not what runs off the
  /// canvas first, the arrowheads are.
  static const double axisArrowOvershoot = 1.18;

  /// How much of the viewport the drawing is allowed to reach across.
  static const double _fitMargin = 0.96;

  /// The tilt the box is fitted at.
  ///
  /// A reference angle rather than the live one. Fitting to the current tilt
  /// would keep the box perfectly framed, but then tilting would also zoom —
  /// the plot would swell and shrink under a finger that only meant to turn
  /// it. This is the default view, which is where a plot spends most of its
  /// life.
  static const double _fitTilt = 0.6;

  /// Cached per viewport: the search below is cheap but runs on every paint
  /// and every pick, and the size rarely changes.
  /// What the fit has to keep on the canvas: the box corners and the axis
  /// arrow tips, the latter reaching further than any corner.
  static List<(double, double, double)> _fitPoints(
    double planar,
    double vertical,
  ) {
    const double reach = axisArrowOvershoot;
    return <(double, double, double)>[
      for (final double sx in <double>[-1, 1])
        for (final double sy in <double>[-1, 1])
          for (final double sz in <double>[-1, 1])
            (sx * planar, sy * planar, sz * vertical),
      (planar * reach, 0, 0),
      (-planar * reach, 0, 0),
      (0, planar * reach, 0),
      (0, -planar * reach, 0),
      (0, 0, vertical * reach),
      (0, 0, -vertical * reach),
    ];
  }

  static Size? _fitSize;
  static ViewFit? _fitResult;

  /// Half-extents of the world box for a viewport of [size], with the shift
  /// that centres what they draw.
  ///
  /// Solved against the real projection rather than in closed form, because
  /// perspective is what actually decides this and it is not linear in the
  /// extent. Two things follow from that and neither survives a flat estimate:
  ///
  /// The drawing is not centred on the world origin. The near-bottom corner
  /// projects far below it while the top projects only a little above, so a
  /// box centred on the origin hangs low in the panel with the z axis
  /// stopping well short of the top — which is exactly what it looked like.
  /// The fit measures the real bounding box and returns the offset that
  /// centres it.
  ///
  /// And the shape is worth searching for. Stretching z fills more height,
  /// but a taller box brings its front-top corner nearer the eye, where
  /// perspective spreads it sideways until the *width* runs out instead. The
  /// best cuboid is the one that fills the panel in both directions, so that
  /// is what is scored.
  static ViewFit viewExtentsFor(Size size) {
    if (_fitSize == size && _fitResult != null) return _fitResult!;

    final double focalLength = focalLengthFor(size);
    final double limitX = size.width * _fitMargin;
    final double limitY = size.height * _fitMargin;
    final double ct = cos(_fitTilt), st = sin(_fitTilt);

    /// The projected bounding box of the drawing, over a full turn of azimuth.
    ///
    /// Null when the box reaches the eye, where the projection stops meaning
    /// anything.
    ({double left, double right, double top, double bottom})? boundsOf(
      double planar,
      double vertical,
    ) {
      double left = double.infinity, right = double.negativeInfinity;
      double top = double.negativeInfinity, bottom = double.infinity;
      final List<(double, double, double)> points = _fitPoints(
        planar,
        vertical,
      );
      for (int a = 0; a < 12; a++) {
        final double az = a * pi / 6;
        final double ca = cos(az), sa = sin(az);
        for (final (double x, double y, double z) in points) {
          final double vx = x * ca - y * sa;
          final double planeY = x * sa + y * ca;
          final double depth = planeY * ct - z * st;
          final double vz = planeY * st + z * ct;
          final double d = focalLength + depth;
          if (d <= focalLength * 0.05) return null;
          final double k = focalLength / d;
          left = min(left, vx * k);
          right = max(right, vx * k);
          // Screen y runs downwards, so the largest vz is the top.
          top = max(top, vz * k);
          bottom = min(bottom, vz * k);
        }
      }
      return (left: left, right: right, top: top, bottom: bottom);
    }

    /// The largest box of a given shape that still fits.
    double largestAt(double aspect) {
      double lo = 1, hi = 4000;
      for (int i = 0; i < 22; i++) {
        final double mid = (lo + hi) / 2;
        final b = boundsOf(mid, mid * aspect);
        final bool ok =
            b != null &&
            b.right - b.left <= limitX &&
            b.top - b.bottom <= limitY;
        if (ok) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    double planar = 1, vertical = 1, best = -1;
    for (int i = 0; i <= 24; i++) {
      final double aspect = 1.0 + i * 3.0 / 24;
      final double p = largestAt(aspect);
      final b = boundsOf(p, p * aspect);
      if (b == null) continue;
      // Scored on the tighter of the two, so a spike that fills the height by
      // giving up the width does not win.
      final double score = min(
        (b.right - b.left) / size.width,
        (b.top - b.bottom) / size.height,
      );
      if (score > best) {
        best = score;
        planar = p;
        vertical = p * aspect;
      }
    }

    // Centre what is actually drawn, not the origin it is drawn around.
    final b = boundsOf(planar, vertical);
    final ViewFit fit = ViewFit(
      planar: planar,
      vertical: vertical,
      offsetX: b == null ? 0 : -(b.left + b.right) / 2,
      offsetY: b == null ? 0 : (b.top + b.bottom) / 2,
    );
    _fitSize = size;
    _fitResult = fit;
    return fit;
  }

  double get scaleX => _viewExtentXY / rangeX;
  double get scaleY => _viewExtentXY / rangeY;
  double get scaleZ => _viewExtentZ / rangeZ;
  PlotThemeData get _theme => plotTheme;

  /// Every function to draw, falling back to the single [function] so callers
  /// that predate multi-surface support keep working unchanged.
  List<PlotExpression> get _curves =>
      functions.isEmpty ? <PlotExpression>[function] : functions;

  /// Lines that are a height, z = f(x, y), rather than an equation to solve.
  List<PlotExpression> get _heightCurves =>
      _curves.where((PlotExpression e) => !e.isLevelSet).toList();

  bool get _hasHeightSurface =>
      _curves.any((PlotExpression e) => !e.isLevelSet);

  /// Lines drawn as a sheet, because they vary in both x and y.
  List<PlotExpression> get _sheetCurves =>
      _heightCurves.where((PlotExpression e) => e.isSurface).toList();

  /// Lines drawn as a single curve standing in the box, because they vary in
  /// only one direction. A cell can hold both kinds at once.
  List<PlotExpression> get _lineCurves =>
      _heightCurves.where((PlotExpression e) => !e.isSurface).toList();

  @override
  void paint(Canvas canvas, Size size) {
    final double focalLength = focalLengthFor(size);
    final ViewFit fit = viewExtentsFor(size);
    _viewExtentXY = fit.planar;
    _viewExtentZ = fit.vertical;
    _fitOffsetX = fit.offsetX;
    _fitOffsetY = fit.offsetY;

    final bool showSurface = surfaceMode != SurfaceMode.none;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // A scalar height surface draws the floor itself, interleaved by depth.
    // Drawing it here as well would put an un-occluded copy underneath.
    // Both height-surface paths interleave the floor themselves. Note there
    // are two: _drawSurfaceWithJetColormap runs when a surface mode is
    // selected, _drawSurface when it is not — and surfaceMode defaults to
    // none, so the plain one is what an ordinary z = f(x, y) actually uses.
    // _drawHeightSurfaces builds the floor into its own depth scene, for
    // curves as well as sheets, so drawing it here too would put an
    // un-occluded copy underneath.
    // A parametric sweep goes through the same depth scene as a height
    // surface, so it owns the floor too — drawing it here as well would leave
    // an un-occluded copy underneath.
    final bool floorDrawnBySurface =
        _isParametric ||
        (fieldType == FieldType.scalar &&
            plotMode != PlotMode.field &&
            (_hasHeightSurface ||
                _curves.any((PlotExpression e) => e.isLevelSet)));

    if (!floorDrawnBySurface) {
      _drawFloorGrid(canvas, size, focalLength);
      _drawAxes(canvas, size, focalLength);
      _drawFloorBoundary(canvas, size, focalLength);
    }

    // Handle different visualization modes
    if (_isParametric) {
      // Ahead of the field branch for the same reason as in 2D: the notation
      // is shared, and only the variables say whether this is an arrow at
      // every point or one point swept into a curve.
      _drawHeightSurfaces(canvas, size, focalLength);
    } else if (fieldType == FieldType.vector && vectorParser != null) {
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
      // Scalar field visualization.
      //
      // A cell can hold both kinds at once — z = x²+y² on one line and
      // x²+y²+z²=4 on the next — so the two are not exclusive. Each renderer
      // takes the lines that belong to it.
      if (_curves.any((PlotExpression e) => e.isLevelSet)) {
        // An equation defines a surface, not a height: there is no z = f(x,y)
        // to sample, so it is contoured rather than sampled.
        // The height renderer owns the floor when there is one; otherwise
        // this is the only thing that can draw it in the right order.
        _drawLevelSurface(
          canvas,
          size,
          focalLength,
          withFloor: !_hasHeightSurface,
        );
      }
      if (_hasHeightSurface) {
        if (is3DFunction && plotMode == PlotMode.field) {
          _drawScalarField3D(canvas, size, focalLength);
          if (showContour) _drawContourLines3D(canvas, size, focalLength);
        } else {
          // Sheets and curves are not exclusive either. sin(x) on one line and
          // x²+y² on the next is a curve standing beside a surface; both go
          // into the one depth-ordered scene this builds.
          _drawHeightSurfaces(canvas, size, focalLength);

          if (showContour && _sheetCurves.isNotEmpty) {
            _drawSurfaceContours(canvas, size, focalLength);
          }
        }
      }
    }

    _drawTrace3D(canvas, size);

    canvas.restore();
  }

  /// Draw the surface where an equation is satisfied — a sphere for
  /// x²+y²+z²=1, a plane for x+y+z=0, and so on.
  ///
  /// Contoured with marching tetrahedra: a level set has no height to sample,
  /// and may close on itself or come in several pieces, so it has to be found
  /// by looking for sign changes through the volume.
  void _drawLevelSurface(
    Canvas canvas,
    Size size,
    double focalLength, {
    required bool withFloor,
  }) {
    final List<PlotExpression> equations =
        _curves.where((PlotExpression e) => e.isLevelSet).toList();
    if (equations.isEmpty) return;

    final List<LevelMesh> meshes = <LevelMesh>[
      for (int i = 0; i < equations.length; i++)
        _levelMeshFor(equations[i], i, equations.length),
    ];

    // Every equation's triangles go into one buffer and are sorted together,
    // so two surfaces that pass through each other interleave instead of one
    // being drawn wholly in front of the other.
    final int count = meshes.fold<int>(
      0,
      (int sum, LevelMesh m) => sum + m.triangleCount,
    );
    if (count == 0) return;

    final Float32List world;
    final Int32List meshColors;
    if (meshes.length == 1) {
      world = meshes.first.world;
      meshColors = meshes.first.colors;
    } else {
      world = Float32List(count * 9);
      meshColors = Int32List(count * 3);
      int wAt = 0;
      int cAt = 0;
      for (final LevelMesh m in meshes) {
        world.setRange(wAt, wAt + m.triangleCount * 9, m.world);
        meshColors.setRange(cAt, cAt + m.triangleCount * 3, m.colors);
        wAt += m.triangleCount * 9;
        cAt += m.triangleCount * 3;
      }
    }

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
      colors.setRange(i * 3, i * 3 + 3, meshColors, src * 3);
    }

    // The floor and axes are merged into the same back-to-front order as the
    // triangles, so the plane cuts through the surface where it should instead
    // of the whole surface being painted over a finished floor. That is what
    // made a sphere sit on top of its own axes.
    //
    // Deliberately not _DepthScene: it holds a few doubles and an Offset per
    // vertex, which is fine for the 5,000 triangles a height surface makes and
    // not for the 33,000 a hyperboloid marches to. The packed buffers stay,
    // and runs of consecutive triangles are drawn as views into them.
    final _LineCollector chrome = _LineCollector();
    if (withFloor) {
      _addFloorGridTo(chrome, size, focalLength);
      _addAxisChromeTo(chrome, size, focalLength);
    }

    void drawRun(int startTriangle, int endTriangle) {
      if (endTriangle <= startTriangle) return;
      final Vertices vertices = Vertices.raw(
        VertexMode.triangles,
        positions.sublist(startTriangle * 6, endTriangle * 6),
        colors: colors.sublist(startTriangle * 3, endTriangle * 3),
      );
      canvas.drawVertices(vertices, BlendMode.dst, Paint());
      vertices.dispose();
    }

    // Lines go out in batches, not one at a time. Splitting the surface at
    // every single grid segment costs a drawVertices per segment — about 940
    // of them — and that, not the vertex data, is what dominates: a 1,700
    // triangle sphere cost the same as a 33,000 triangle hyperboloid. A
    // height surface never showed this because it sits above the floor, so
    // its grid lines fall into a handful of runs; a level surface straddles
    // the floor and interleaves with almost every line.
    //
    // The error this trades for is confined to one batch: lines inside a
    // batch are drawn at the depth of the first of them, so a line can sit in
    // front of triangles within that narrow depth band. At this batch count
    // the band is a fraction of the box, and the lines are one pixel wide.
    const int maxRuns = 24;
    final List<int> lineOrder = chrome.farToNear;
    final int batch =
        lineOrder.isEmpty ? 1 : (lineOrder.length / maxRuns).ceil();

    int runStart = 0;
    int drawn = 0;
    for (int b = 0; b < lineOrder.length; b += batch) {
      final double cut = chrome.depths[lineOrder[b]];
      // Everything further away than this batch is already behind it.
      while (drawn < count && depth[order[drawn]] > cut) {
        drawn++;
      }
      drawRun(runStart, drawn);
      runStart = drawn;

      final int end = min(b + batch, lineOrder.length);
      for (int k = b; k < end; k++) {
        final int l = lineOrder[k];
        canvas.drawLine(chrome.a[l], chrome.b[l], chrome.paints[l]);
      }
    }
    drawRun(runStart, count);

    _drawAxes(canvas, size, focalLength, skipLines: true);

    if (equations.length == 1) {
      _drawColorbar3D(canvas, size, -rangeZ, rangeZ);
    } else {
      _drawSurfaceLegend(canvas, size, equations.length);
    }
  }

  /// March one equation into a coloured mesh.
  ///
  /// Geometry and colour are cached: neither depends on the camera, and a
  /// hyperboloid marches to ~33,000 triangles, so rebuilding per frame was the
  /// whole cost of a drag.
  LevelMesh _levelMeshFor(PlotExpression equation, int index, int of) {
    final Color Function(double) ramp = surfaceColormap(index, of: of);
    return cachedLevelMesh(
      equation,
      <double>[-rangeX, rangeX, -rangeY, rangeY, -rangeZ, rangeZ],
      40,
      () => <
        ({
          double ax,
          double ay,
          double az,
          double bx,
          double by,
          double bz,
          double cx,
          double cy,
          double cz,
        })
      >[
        for (final LevelTriangle t in marchingTetrahedra(
          equation,
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
      //
      // An inequality bounds a solid rather than tracing a shell, so its
      // surface is drawn see-through: the triangles are already sorted back
      // to front, which is exactly the order alpha blending needs, so the far
      // wall shows through the near one and the shape reads as a body with an
      // inside. A strict inequality, whose own boundary is excluded, is
      // fainter still — the 3D counterpart of the dashed edge in 2D.
      (double z) {
        final Color base = ramp(((z + rangeZ) / (2 * rangeZ)).clamp(0.0, 1.0));
        if (!equation.relation.isRegion) return base.toARGB32();
        return base
            .withValues(alpha: equation.relation.includesBoundary ? 0.55 : 0.34)
            .toARGB32();
      },
    );
  }

  /// Sample one z = f(x, y) over the floor grid and build its cells.
  ///
  /// [minV] and [maxV] cover only the corners actually drawn, so colour maps
  /// across what is on screen rather than across values clipped away.
  /// Cells on a side while still, and while moving.
  static const int _surfaceGridStill = 76;
  static const int _surfaceGridMoving = 50;

  ({List<Quad> quads, double minV, double maxV}) _surfaceQuads(
    PlotExpression parser, {
    int? gridSize,
  }) {
    gridSize ??= interacting ? _surfaceGridMoving : _surfaceGridStill;
    // Heights are cached: rotating changes where the camera sees the surface
    // from, not the surface, so re-walking the expression tree every frame was
    // wasted work.
    final List<List<double>> sampled = cachedHeightGrid(
      parser,
      rangeX,
      rangeY,
      gridSize,
    );

    final List<List<Point3D?>> points = <List<Point3D?>>[];
    final List<List<double>> zValues = <List<double>>[];
    double minZ = double.infinity;
    double maxZ = double.negativeInfinity;

    for (int i = 0; i <= gridSize; i++) {
      final List<Point3D?> row = <Point3D?>[];
      final List<double> zRow = <double>[];
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

    if (!minZ.isFinite || !maxZ.isFinite) {
      minZ = 0;
      maxZ = 1;
    }
    if (minZ == maxZ) maxZ = minZ + 1;

    final List<Quad> quads = <Quad>[];
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

    return (quads: quads, minV: minZ, maxV: maxZ);
  }

  /// Draw every z = f(x, y) in the cell on one set of axes.
  ///
  /// All surfaces and the floor go into a single depth-ordered scene, so they
  /// occlude one another properly: where one surface passes under another the
  /// nearer one covers it, instead of whichever was drawn last winning.
  ///
  /// This is the only height-surface renderer. There used to be two —
  /// `_drawSurfaceWithJetColormap` for when a surface mode is selected and
  /// `_drawSurface` for when it is not — which were near-identical copies, and
  /// since `surfaceMode` defaults to none it was the second that ran for an
  /// ordinary z = f(x, y). Three separate fixes were made to the first one and
  /// none of them ever appeared on screen.
  void _drawHeightSurfaces(Canvas canvas, Size size, double focalLength) {
    final List<PlotExpression> curves = _sheetCurves;
    if (curves.isEmpty && _lineCurves.isEmpty && !_isParametric) return;

    // The floor joins the same ordered list as the surfaces, so the two
    // occlude each other instead of the surfaces always winning.
    final _DepthScene scene = _DepthScene();
    _addFloorGridTo(scene, size, focalLength);
    _addAxisChromeTo(scene, size, focalLength);

    double? soleMin;
    double? soleMax;

    for (int c = 0; c < curves.length; c++) {
      final built = _surfaceQuads(curves[c]);
      if (built.quads.isEmpty) continue;

      // Each surface is coloured against its own range. Sharing one range
      // across all of them would flatten a shallow surface to a single colour
      // whenever a steeper one is on the same axes.
      final Color Function(double) ramp = surfaceColormap(c, of: curves.length);
      final double span = built.maxV - built.minV;
      int shade(double v) =>
          ramp(((v - built.minV) / span).clamp(0.0, 1.0)).toARGB32();

      if (curves.length == 1) {
        soleMin = built.minV;
        soleMax = built.maxV;
      }

      for (final quad in built.quads) {
        final o1 = quad.p1.project(focalLength, size, _panX, _panY);
        final o2 = quad.p2.project(focalLength, size, _panX, _panY);
        final o3 = quad.p3.project(focalLength, size, _panX, _panY);
        final o4 = quad.p4.project(focalLength, size, _panX, _panY);

        // Colour per corner, interpolated across the cell. A single colour
        // from the cell average makes each cell a flat block, which reads as
        // banding however fine the grid.
        final int c1 = shade(quad.v1);
        final int c2 = shade(quad.v2);
        final int c3 = shade(quad.v3);
        final int c4 = shade(quad.v4);

        // Two triangles sharing the p1-p3 diagonal, each carrying its own
        // depth so a cell can be sorted against a grid segment passing under
        // it — or against another surface threading between them.
        final double d1 = (quad.p1.y + quad.p2.y + quad.p3.y) / 3;
        final double d2 = (quad.p1.y + quad.p3.y + quad.p4.y) / 3;
        scene.addTriangle(o1, o2, o3, c1, c2, c3, d1);
        scene.addTriangle(o1, o3, o4, c1, c3, c4, d2);
      }
    }

    // Single-variable curves join the same list, so one passing behind a
    // surface is hidden by it. Drawn afterwards on top of a finished scene, a
    // curve floats in front of geometry it runs through — the same fault the
    // floor grid had against the surface.
    _addStandingCurvesTo(scene, size, focalLength);
    _addParametricSurfaceTo(scene, size, focalLength);
    _addParametricTo(scene, size, focalLength);

    scene.paint(canvas);

    // Tick labels and arrowheads go on last, unoccluded — the lines are
    // already in the scene, hence skipLines.
    //
    // Drawn over a surface as well as beside one. They were suppressed
    // whenever a sheet was present, on the grounds that numerals scattered
    // over a bright surface read as dirt — but that left every surface plot
    // with unlabelled axes and no way to tell what the box spans, which is
    // the worse of the two.
    _drawAxes(canvas, size, focalLength, skipLines: true);

    // A colorbar keys one ramp to one set of values, so it can only speak for
    // a lone surface. With several, each has its own ramp and its own range,
    // and a single bar would attach the wrong numbers to all but one of them.
    // A parametric mesh coloured by a value owns the bar: it is the only
    // surface on the axes, and its ramp is the one the numbers belong to.
    final (double, double)? parametric = _parametricValueRange;
    if (parametric != null) {
      _drawColorbar3D(canvas, size, parametric.$1, parametric.$2);
    } else if (curves.length == 1) {
      if (soleMin != null && soleMax != null) {
        _drawColorbar3D(canvas, size, soleMin, soleMax);
      }
    } else if (curves.length > 1) {
      _drawSurfaceLegend(canvas, size, curves.length);
    }
  }

  /// Swatches naming which ramp belongs to which line of the cell.
  ///
  /// Without it the ramps are just decoration — you can see there are three
  /// surfaces but not which is which, and the cell lists them in order.
  void _drawSurfaceLegend(Canvas canvas, Size size, int count) {
    const double swatchW = 26.0;
    const double swatchH = 9.0;
    const double gap = 6.0;
    const double margin = 10.0;

    final double totalH = count * swatchH + (count - 1) * gap;
    double top = margin;
    if (totalH < size.height) top = (size.height - totalH) / 2;

    for (int i = 0; i < count; i++) {
      final Color Function(double) ramp = surfaceColormap(i, of: count);
      final Rect r = Rect.fromLTWH(
        size.width - margin - swatchW,
        top + i * (swatchH + gap),
        swatchW,
        swatchH,
      );
      // The swatch is the ramp itself, not one colour from it, so it matches
      // what the surface actually looks like at every height.
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[ramp(0.0), ramp(0.5), ramp(1.0)],
          ).createShader(r),
      );

      final TextPainter label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(color: _theme.label, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(r.left - label.width - 4, r.center.dy - label.height / 2),
      );
    }
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
      final o1 = quad.p1.project(focalLength, size, _panX, _panY);
      final o2 = quad.p2.project(focalLength, size, _panX, _panY);
      final o3 = quad.p3.project(focalLength, size, _panX, _panY);
      final o4 = quad.p4.project(focalLength, size, _panX, _panY);

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
      final o1 = quad.p1.project(focalLength, size, _panX, _panY);
      final o2 = quad.p2.project(focalLength, size, _panX, _panY);
      final o3 = quad.p3.project(focalLength, size, _panX, _panY);
      final o4 = quad.p4.project(focalLength, size, _panX, _panY);

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

  double _calculateGridSpacing(double range) {
    // floor() throws on Infinity and NaN instead of returning a garbage
    // double, so an unusable range took the whole frame down — every frame,
    // since the range persists in the widget's state.
    final span = range * 2;
    if (!span.isFinite || span <= 0) return 1;
    final exponent = log(span) / ln10;
    if (!exponent.isFinite) return 1;
    final magnitude = pow(10, exponent.floor()).toDouble();
    if (!magnitude.isFinite || magnitude <= 0) return 1;
    final normalized = span / magnitude;
    if (normalized < 2) return magnitude / 5;
    if (normalized < 5) return magnitude / 2;
    return magnitude;
  }

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

    final double gridSpacingX = _calculateGridSpacing(rangeX);
    final double gridSpacingY = _calculateGridSpacing(rangeY);

    bool isMajor(double v, double spacing) =>
        (v / spacing - (v / spacing).roundToDouble()).abs() < 1e-6;

    for (double i = -rangeX; i <= rangeX + 1e-9; i += gridSpacingX / 5) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(i * scaleX, -rangeY * scaleY, 0),
        Point3D(i * scaleX, rangeY * scaleY, 0),
        isMajor(i, gridSpacingX) ? majorPaint : minorPaint,
      );
    }
    for (double i = -rangeY; i <= rangeY + 1e-9; i += gridSpacingY / 5) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(-rangeX * scaleX, i * scaleY, 0),
        Point3D(rangeX * scaleX, i * scaleY, 0),
        isMajor(i, gridSpacingY) ? majorPaint : minorPaint,
      );
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
    final startProj = start.project(focalLength, size, _panX, _panY);
    final endProj = end.project(focalLength, size, _panX, _panY);
    final clipped = _clipLineToRect(
      startProj,
      endProj,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    if (clipped != null) canvas.drawLine(clipped.$1, clipped.$2, paint);
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    double focalLength, {
    bool skipLines = false,
  }) {
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

      // The scene draws the axis line when it is interleaving with a surface,
      // so it can be occluded where the surface is nearer.
      if (!skipLines) {
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
      }

      // Just beyond the plotted box, which is where the axis stops meaning
      // anything. Not at 0.9 of the range, which put the head inside the box
      // with the line running on past it; and not at the line's true end at
      // twice the range, which is off screen for the vertical axis.
      const double arrowAt = axisArrowOvershoot;
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
          canvas.drawPath(
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
              ..close(),
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
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
        final tickProj = tickPos.project(focalLength, size, _panX, _panY);

        if (!_isPointInRect(
          tickProj,
          Rect.fromLTWH(0, 0, size.width, size.height),
        )) {
          continue;
        }

        const tickLen = 5.0;
        Point3D tick1End;

        if (label == 'X') {
          tick1End = Point3D(
            t * scale,
            tickLen,
            0,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else if (label == 'Y') {
          tick1End = Point3D(
            tickLen,
            t * scale,
            0,
          ).rotateZ(rotationZ).rotateX(rotationX);
        } else {
          tick1End = Point3D(
            tickLen,
            0,
            t * scale,
          ).rotateZ(rotationZ).rotateX(rotationX);
        }

        // One mark straight through the axis. Two marks at right angles read
        // as a small corner sitting beside the line rather than a division
        // of it.
        final Offset tick1 = tick1End.project(focalLength, size, _panX, _panY);
        canvas.drawLine(tickProj + (tickProj - tick1), tick1, tickPaint);

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

        final labelProj = labelPos.project(focalLength, size, _panX, _panY);
        if (_isPointInRect(
          labelProj,
          Rect.fromLTWH(0, 0, size.width, size.height),
        )) {
          final ltp = TextPainter(
            text: TextSpan(
              text: _formatNumber(t),
              style: TextStyle(color: theme.label, fontSize: 10),
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

  /// Add every single-variable curve to [scene], depth-ordered with whatever
  /// else is in it.
  ///
  /// Each curve runs along the axis its expression actually varies in: sin(x)
  /// along x, cos(y) along y. Both are curves, not sheets — see
  /// [PlotExpression.isSurface] for why an extruded cos(y) is the wrong
  /// picture even though it is a legitimate surface.
  /// The value range the parametric mesh was coloured over, or null when it
  /// is shaded by its own geometry instead. Read by the colorbar.
  static (double, double)? _parametricValueRange;

  /// Add the patch swept out by u and v.
  ///
  /// Normals are averaged at the corners rather than taken per cell, so the
  /// shading runs continuously across the mesh. Flat-shading a cell leaves it
  /// a facet however fine the grid is — the same reason the heatmap colours
  /// its corners and not its cells — and a sphere came out looking cut from
  /// gemstone.
  void _addParametricSurfaceTo(
    _DepthScene scene,
    Size size,
    double focalLength,
  ) {
    _parametricValueRange = null;
    final VectorFieldParser? field = vectorParser;
    if (field == null || !field.isParametricSurface) return;

    final List<List<ParametricPoint?>> grid = sampleParametricSurface(
      field,
      u: uRange,
      v: vRange,
      steps:
          interacting ? parametricSurfaceStepsMoving : parametricSurfaceSteps,
    );
    if (grid.length < 2 || grid.first.length < 2) return;
    final int rows = grid.length;
    final int cols = grid.first.length;

    // Every corner rotated once. Each is shared by up to four cells, and the
    // rotation is most of the per-cell cost.
    final List<List<Point3D?>> pts = <List<Point3D?>>[
      for (int i = 0; i < rows; i++)
        <Point3D?>[
          for (int j = 0; j < cols; j++)
            () {
              final ParametricPoint? p = grid[i][j];
              if (p == null ||
                  p.x.abs() > rangeX ||
                  p.y.abs() > rangeY ||
                  p.z.abs() > rangeZ) {
                return null;
              }
              return Point3D(
                p.x * scaleX,
                p.y * scaleY,
                p.z * scaleZ,
              ).rotateZ(rotationZ).rotateX(rotationX);
            }(),
        ],
    ];

    // What the colours mean. `none` shades by facing alone; the others read a
    // component of the swept position, which for a parametric surface is the
    // position vector itself — so Fz is height and the magnitude is distance
    // from the origin.
    final bool byValue = surfaceMode != SurfaceMode.none;
    double valueAt(ParametricPoint p) => switch (surfaceMode) {
      SurfaceMode.x => p.x,
      SurfaceMode.y => p.y,
      SurfaceMode.z => p.z,
      SurfaceMode.magnitude => sqrt(p.x * p.x + p.y * p.y + p.z * p.z),
      SurfaceMode.none => 0,
    };

    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    if (byValue) {
      for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
          if (pts[i][j] == null) continue;
          final double v = valueAt(grid[i][j]!);
          if (!v.isFinite) continue;
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
      if (minV > maxV) return; // nothing defined anywhere
      _parametricValueRange = (minV, maxV);
    }
    final double span = maxV > minV ? maxV - minV : 1.0;

    final Color base = _theme.seriesColor(0);

    /// The averaged normal's facing at a corner, 0 edge-on to 1 square on.
    ///
    /// Central differences where both neighbours exist, one-sided at the rim,
    /// so the edge of the sheet is shaded like the rest of it.
    double facingAt(int i, int j) {
      final Point3D? here = pts[i][j];
      if (here == null) return 0.5;
      final Point3D ua = (i > 0 ? pts[i - 1][j] : null) ?? here;
      final Point3D ub = (i < rows - 1 ? pts[i + 1][j] : null) ?? here;
      final Point3D va = (j > 0 ? pts[i][j - 1] : null) ?? here;
      final Point3D vb = (j < cols - 1 ? pts[i][j + 1] : null) ?? here;

      final double ux = ub.x - ua.x;
      final double uy = ub.y - ua.y;
      final double uz = ub.z - ua.z;
      final double vx = vb.x - va.x;
      final double vy = vb.y - va.y;
      final double vz = vb.z - va.z;
      final double nx = uy * vz - uz * vy;
      final double ny = uz * vx - ux * vz;
      final double nz = ux * vy - uy * vx;
      final double len = sqrt(nx * nx + ny * ny + nz * nz);
      // A degenerate corner has no facing; the mid tone is the honest answer.
      return len == 0 ? 0.5 : ny.abs() / len;
    }

    /// The colour at one corner.
    int shadeAt(int i, int j) {
      final double facing = facingAt(i, j);
      if (!byValue) {
        // Never fully dark: a corner seen edge-on is still surface, and
        // dropping it to nothing punches a hole along every silhouette.
        final double t = 0.45 + 0.55 * facing;
        return Color.from(
          alpha: 0.92,
          red: base.r * t,
          green: base.g * t,
          blue: base.b * t,
        ).toARGB32();
      }
      // The ramp carries the value; the shading on top is kept light so the
      // form still reads without the colour drifting far from the number it
      // stands for. Without any, a sphere coloured by magnitude is one flat
      // colour and reads as a disc.
      final Color ramp = plotColormap(
        ((valueAt(grid[i][j]!) - minV) / span).clamp(0.0, 1.0),
      );
      final double t = 0.82 + 0.18 * facing;
      return Color.from(
        alpha: 0.95,
        red: ramp.r * t,
        green: ramp.g * t,
        blue: ramp.b * t,
      ).toARGB32();
    }

    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < cols; j++) {
        final Point3D? a = pts[i - 1][j - 1];
        final Point3D? b = pts[i - 1][j];
        final Point3D? c = pts[i][j];
        final Point3D? d = pts[i][j - 1];
        // A cell missing a corner is a hole in the surface, and drawing it
        // would span the gap with a sheet the sweep never covers.
        if (a == null || b == null || c == null || d == null) continue;

        final int ca = shadeAt(i - 1, j - 1);
        final int cb = shadeAt(i - 1, j);
        final int cc = shadeAt(i, j);
        final int cd = shadeAt(i, j - 1);

        final Offset oa = a.project(focalLength, size, _panX, _panY);
        final Offset ob = b.project(focalLength, size, _panX, _panY);
        final Offset oc = c.project(focalLength, size, _panX, _panY);
        final Offset od = d.project(focalLength, size, _panX, _panY);

        // Two triangles sharing the a-c diagonal, each with its own depth so
        // a cell can sort against a grid segment passing under it.
        scene.addTriangle(oa, ob, oc, ca, cb, cc, (a.y + b.y + c.y) / 3);
        scene.addTriangle(oa, oc, od, ca, cc, cd, (a.y + c.y + d.y) / 3);
      }
    }
  }

  /// Add the path traced by sweeping u, in the same depth order as everything
  /// else in the scene.
  ///
  /// Unlike a standing curve, a parametric one already knows all three of its
  /// coordinates, so there is no axis to choose and no value to clip against:
  /// the sweep says where the point is, and the window only decides whether it
  /// is visible.
  void _addParametricTo(_DepthScene scene, Size size, double focalLength) {
    final VectorFieldParser? field = vectorParser;
    // A surface is not also a curve: sweeping u alone would trace one edge of
    // it and draw that line across the mesh.
    if (field == null || !field.isParametric || field.isParametricSurface) {
      return;
    }

    final Color curveColor = _theme.seriesColor(0);
    final paint =
        Paint()
          ..color = curveColor
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    Offset? prev;
    double? prevDepth;

    for (final ParametricPoint? p in sampleParametricCurve(field, u: uRange)) {
      // A point outside the box breaks the line rather than being clamped
      // onto the wall, which would draw an edge the curve does not have.
      if (p == null ||
          p.x.abs() > rangeX ||
          p.y.abs() > rangeY ||
          p.z.abs() > rangeZ) {
        prev = null;
        prevDepth = null;
        continue;
      }

      final point = Point3D(
        p.x * scaleX,
        p.y * scaleY,
        p.z * scaleZ,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final Offset proj = point.project(focalLength, size, _panX, _panY);

      if (prev != null) {
        scene.addLine(prev, proj, paint, (prevDepth! + point.y) / 2);
      }
      prev = proj;
      prevDepth = point.y;
    }
  }

  void _addStandingCurvesTo(_DepthScene scene, Size size, double focalLength) {
    final List<PlotExpression> curves = _lineCurves;
    for (int c = 0; c < curves.length; c++) {
      _addOneStandingCurveTo(scene, size, focalLength, curves[c], c, curves);
    }
  }

  /// Coloured from the theme's series palette, the same palette 2D uses, so a
  /// curve keeps its colour when the view is switched between 2D and 3D.
  void _addOneStandingCurveTo(
    _DepthScene scene,
    Size size,
    double focalLength,
    PlotExpression parser,
    int index,
    List<PlotExpression> curves,
  ) {
    const steps = 300;
    final String axis = parser.curveAxis;
    final bool alongY = axis == 'y';
    final bool alongZ = axis == 'z';

    // The parameter runs along the variable's own axis; the value is drawn
    // perpendicular to it, and is clipped against that axis's window.
    final double paramRange = alongZ ? rangeZ : (alongY ? rangeY : rangeX);
    final double paramScale = alongZ ? scaleZ : (alongY ? scaleY : scaleX);
    final double valueRange = alongZ ? rangeX : rangeZ;
    final double valueScale = alongZ ? scaleX : scaleZ;

    final Color curveColor =
        curves.length == 1 ? colors.accent : _theme.seriesColor(index);

    final paint =
        Paint()
          ..color = curveColor
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    final shadowPaint =
        Paint()
          ..color = curveColor.withValues(alpha: 0.2)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    final verticalPaint =
        Paint()
          ..color = curveColor.withValues(alpha: 0.12)
          ..strokeWidth = 1;

    // Previous point, or null after a break in the curve.
    Offset? prev;
    Offset? prevShadow;
    double? prevDepth;
    double? lastV;

    void breakCurve() {
      prev = null;
      prevShadow = null;
      prevDepth = null;
      lastV = null;
    }

    for (int i = 0; i <= steps; i++) {
      final t = -paramRange + (2 * paramRange * i / steps);
      double v;
      try {
        v =
            alongZ
                ? parser.evaluate(0, 0, t)
                : (alongY ? parser.evaluate(0, t) : parser.evaluate(t, 0));
      } catch (_) {
        breakCurve();
        continue;
      }
      if (!v.isFinite || v < -valueRange || v > valueRange) {
        breakCurve();
        continue;
      }

      // Each curve stands in its own plane: an x-curve in x-z, a y-curve in
      // y-z, a z-curve in x-z but running vertically. So sin(x), cos(y) and
      // sin(z) on the same axes meet at right angles rather than lying on top
      // of one another.
      final double wx = alongZ ? v * valueScale : (alongY ? 0.0 : t * scaleX);
      final double wy = alongY ? t * scaleY : 0.0;
      final double wz = alongZ ? t * paramScale : v * valueScale;

      final point = Point3D(wx, wy, wz).rotateZ(rotationZ).rotateX(rotationX);
      // The value flattened away, so the curve is cast onto its own axis.
      final shadowPoint = Point3D(
        alongZ ? 0.0 : wx,
        wy,
        alongZ ? wz : 0.0,
      ).rotateZ(rotationZ).rotateX(rotationX);
      final proj = point.project(focalLength, size, _panX, _panY);
      final shadowProj = shadowPoint.project(focalLength, size, _panX, _panY);

      // An asymptote jumps the full width of the box between two samples;
      // joining across it draws a straight line that is not part of the curve.
      final bool jumped =
          lastV != null && (v - lastV!).abs() > valueRange * 0.5;

      if (prev != null && !jumped) {
        scene.addLine(prev!, proj, paint, (prevDepth! + point.y) / 2);
        scene.addLine(
          prevShadow!,
          shadowProj,
          shadowPaint,
          (prevDepth! + shadowPoint.y) / 2,
        );
      }
      if (i % 15 == 0) {
        scene.addLine(proj, shadowProj, verticalPaint, point.y);
      }

      prev = proj;
      prevShadow = shadowProj;
      prevDepth = point.y;
      lastV = v;
    }
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
      final proj = fp.point.project(focalLength, size, _panX, _panY);
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
      final proj = fp.point.project(focalLength, size, _panX, _panY);
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
        .project(focalLengthFor(size), size, _panX, _panY);
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
    ], anchorX: at.dx);
  }

  /// The value scale, laid along the top of the plot.
  ///
  /// Horizontal and in the top right corner to match 2D, leaving the left
  /// edge to the parameter panels and the top left to the mode label. Ticks
  /// hang below the bar rather than beside it, which is the only arrangement
  /// that keeps five labels from colliding.
  void _drawColorbar3D(Canvas canvas, Size size, double minVal, double maxVal) {
    const double barHeight = 12.0;
    const double margin = 10.0;
    const int ticks = 4;
    final double barWidth = (size.width * 0.45).clamp(80.0, 220.0);

    final Rect barRect = Rect.fromLTWH(
      size.width - barWidth - margin,
      margin,
      barWidth,
      barHeight,
    );

    // Left end is the minimum, so it reads like the axis underneath it. Drawn
    // as one gradient rather than a line per pixel, which quantised the ramp
    // to the bar's width in steps and showed as bands.
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
      final double x = barRect.left + barWidth * t;
      final double value = minVal + (maxVal - minVal) * t;

      canvas.drawLine(
        Offset(x, barRect.bottom),
        Offset(x, barRect.bottom + 3),
        Paint()
          ..color = _theme.colorbarBorder
          ..strokeWidth = 1,
      );

      final TextPainter tp = TextPainter(
        text: TextSpan(text: _formatNumber(value), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Centred under its tick, and pulled inside the canvas at the ends so
      // the first and last labels are not half cut off.
      final double left = (x - tp.width / 2).clamp(
        2.0,
        size.width - tp.width - 2,
      );
      tp.paint(canvas, Offset(left, barRect.bottom + 5));
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
