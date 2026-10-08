import 'dart:typed_data';
import 'dart:ui' show Vertices, VertexMode;
import 'dart:math';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../math_engine/math_engine.dart';
import '../models/complex_view.dart';
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
part 'plot_3d_axes.dart';
part 'plot_3d_surfaces.dart';
part 'plot_3d_level_surfaces.dart';
part 'plot_3d_contours.dart';
part 'plot_3d_sweeps.dart';
part 'plot_3d_fields.dart';
part 'plot_3d_overlays.dart';

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

  /// How square each corner stands to the key light, 0 to 1 — see
  /// [keyLightOn]. Per corner for the same reason as the values: lit as one
  /// flat block, every cell of a surface shows as a facet.
  final double l1, l2, l3, l4;

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
    this.l1 = 1,
    this.l2 = 1,
    this.l3 = 1,
    this.l4 = 1,
  }) : v1 = v1 ?? avgValue,
       v2 = v2 ?? avgValue,
       v3 = v3 ?? avgValue,
       v4 = v4 ?? avgValue;
}

/// One end-to-end piece of a sampled surface's grid line, with the value and
/// the light at each end so whoever draws it can colour it as the surface is
/// coloured there.
typedef _GridPiece =
    ({Point3D a, Point3D b, double va, double vb, double la, double lb});

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

/// Stand-in for a surface drawn with its grid switched off.
final Float32List _noLines = Float32List(0);
final Int32List _noInks = Int32List(0);

/// How far into the shade a surface coloured by value may go, against 1 for a
/// solid one.
///
/// Its colour is a reading, so it has to stay close enough to the colorbar to
/// be read off it; half the shade still shows the form.
const double _valueShadeStrength = 0.5;

/// Indices into [depth] ordered far to near, for the painter's algorithm.
///
/// A counting sort over 4,096 depth buckets rather than a comparison sort.
/// `List.sort` with a closure over a `Float64List` costs 7.2 ms on the 38,000
/// triangles one of these surfaces marches to, and drawing the grid as
/// geometry roughly doubles what has to be ordered — which would have put the
/// sort alone over a frame. Bucketed it is 0.25 ms, and 0.68 ms at twice the
/// count.
///
/// The precision given up is nothing here. A bucket spans the box's depth over
/// 4,096, which against a marching cell is under two per cent of one, so the
/// arbitrary order inside a bucket can only swap primitives that are already
/// far closer together than the depth bias separating a grid line from its
/// surface.
List<int> _farToNear(Float64List depth, int count) {
  const int buckets = 4096;
  double lo = double.infinity;
  double hi = double.negativeInfinity;
  for (int i = 0; i < count; i++) {
    final double d = depth[i];
    if (d < lo) lo = d;
    if (d > hi) hi = d;
  }
  // Everything at one depth, or nothing finite to go on: any order will do.
  if (!(hi > lo)) return List<int>.generate(count, (int i) => i);

  final double scale = (buckets - 1) / (hi - lo);
  final Int32List bucket = Int32List(count);
  final Int32List starts = Int32List(buckets + 1);
  for (int i = 0; i < count; i++) {
    // Reversed on the way in, so bucket 0 is the furthest away.
    final int b = buckets - 1 - ((depth[i] - lo) * scale).toInt();
    bucket[i] = b;
    starts[b + 1]++;
  }
  for (int b = 0; b < buckets; b++) {
    starts[b + 1] += starts[b];
  }
  final Int32List out = Int32List(count);
  for (int i = 0; i < count; i++) {
    out[starts[bucket[i]]++] = i;
  }
  return out;
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

  /// An annotation — an axis number, its tick, an arrowhead — placed in depth
  /// with everything else, so a surface nearer the camera covers it.
  ///
  /// They were painted over the finished scene, which put every number on top
  /// of the shape: a label on the far side of a surface showed through it as
  /// if the surface were glass.
  void addMark(void Function(Canvas canvas) paint, double depth);
}

/// Paints everything the moment it arrives, for a plot with no surface to
/// sort against.
class _ImmediateSink implements _LineSink {
  _ImmediateSink(this.canvas);

  final Canvas canvas;

  @override
  void addLine(Offset a, Offset b, Paint paint, double depth) =>
      canvas.drawLine(a, b, paint);

  @override
  void addMark(void Function(Canvas canvas) paint, double depth) =>
      paint(canvas);
}

/// Just keeps the lines and marks, for a caller that does its own merging.
class _LineCollector implements _LineSink {
  final List<void Function(Canvas canvas)> painters =
      <void Function(Canvas canvas)>[];
  final List<double> depths = <double>[];

  /// Which entries are marks rather than lines. A mark is never batched with
  /// its neighbours: it is placed at exactly its own depth.
  final List<bool> isMark = <bool>[];

  @override
  void addLine(Offset from, Offset to, Paint paint, double depth) {
    painters.add((Canvas canvas) => canvas.drawLine(from, to, paint));
    depths.add(depth);
    isMark.add(false);
  }

  @override
  void addMark(void Function(Canvas canvas) paint, double depth) {
    painters.add(paint);
    depths.add(depth);
    isMark.add(true);
  }

  int get length => depths.length;

  /// Indices ordered far to near, matching how triangles are sorted — and in
  /// the order they were added where two are at one depth. See
  /// [_DepthScene.paint].
  List<int> get farToNear => List<int>.generate(length, (i) => i)..sort((x, y) {
    final int byDepth = depths[y].compareTo(depths[x]);
    return byDepth != 0 ? byDepth : x.compareTo(y);
  });
}

/// What a [_DepthScene] entry is.
const int _sceneTriangle = 0;
const int _sceneLine = 1;
const int _sceneMark = 2;

class _DepthScene implements _LineSink {
  final List<double> _depths = <double>[];
  final List<int> _kind = <int>[];

  // Triangles: six screen floats and three packed colours each.
  final List<double> _triXY = <double>[];
  final List<int> _triColor = <int>[];

  // Lines: four screen floats each, plus a paint.
  final List<double> _lineXY = <double>[];
  final List<Paint> _linePaint = <Paint>[];

  // Marks: whatever paints them.
  final List<void Function(Canvas canvas)> _marks =
      <void Function(Canvas canvas)>[];

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
    _kind.add(_sceneTriangle);
    _triXY.addAll(<double>[a.dx, a.dy, b.dx, b.dy, c.dx, c.dy]);
    _triColor.addAll(<int>[ca, cb, cc]);
  }

  @override
  void addLine(Offset a, Offset b, Paint paint, double depth) {
    _depths.add(depth);
    _kind.add(_sceneLine);
    _lineXY.addAll(<double>[a.dx, a.dy, b.dx, b.dy]);
    _linePaint.add(paint);
  }

  @override
  void addMark(void Function(Canvas canvas) paint, double depth) {
    _depths.add(depth);
    _kind.add(_sceneMark);
    _marks.add(paint);
  }

  /// Draw everything far to near, the triangles washed towards [fog] with
  /// their distance (see [depthFog]).
  void paint(Canvas canvas, {int? fog}) {
    final int n = _depths.length;
    if (n == 0) return;

    // The triangles' own depth range: the fog runs from the nearest of them
    // to the farthest, whatever else is in the scene.
    double near = double.infinity, far = double.negativeInfinity;
    for (int i = 0; i < n; i++) {
      if (_kind[i] != _sceneTriangle) continue;
      final double d = _depths[i];
      if (d < near) near = d;
      if (d > far) far = d;
    }
    final double fogPerDepth =
        fog != null && far > near ? depthFog / (far - near) : 0;

    // Far to near, and in the order added where two are at one depth. The
    // sort is not stable on its own, and an axis name shares its arrowhead's
    // depth: which of the two came out on top depended on everything else in
    // the scene, so adding a curve somewhere else could put the arrowhead
    // over the name.
    final List<int> order = List<int>.generate(n, (i) => i);
    order.sort((a, b) {
      final int byDepth = _depths[b].compareTo(_depths[a]);
      return byDepth != 0 ? byDepth : a.compareTo(b);
    });

    // Running indices into the per-kind buffers, so a primitive's data can be
    // found from its position among its own kind.
    final List<int> kindIndex = List<int>.filled(n, -1);
    final List<int> counts = <int>[0, 0, 0];
    for (int i = 0; i < n; i++) {
      kindIndex[i] = counts[_kind[i]]++;
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
      switch (_kind[i]) {
        case _sceneLine:
          flush();
          final int o = kindIndex[i] * 4;
          canvas.drawLine(
            Offset(_lineXY[o], _lineXY[o + 1]),
            Offset(_lineXY[o + 2], _lineXY[o + 3]),
            _linePaint[kindIndex[i]],
          );
        case _sceneMark:
          flush();
          _marks[kindIndex[i]](canvas);
        default:
          final int o = kindIndex[i] * 6;
          final int c = kindIndex[i] * 3;
          batchXY.addAll(_triXY.getRange(o, o + 6));
          if (fogPerDepth == 0) {
            batchColor.addAll(_triColor.getRange(c, c + 3));
          } else {
            final double amount = (_depths[i] - near) * fogPerDepth;
            for (int v = 0; v < 3; v++) {
              batchColor.add(fogArgb(_triColor[c + v], amount, fog!));
            }
          }
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

  /// How much of the panel's lower edge is hidden behind the expression rows.
  ///
  /// Only affects where the box is centred, not how big it is: the canvas
  /// still fills the panel so the axes run on behind the rows.
  final double bottomInset;

  /// Every vector or parametric line in the cell, in the order written.
  /// [vectorParser] is the first of them, kept because most of what the
  /// painter does with a field wants exactly one.
  ///
  /// Empty means fall back to [vectorParser] alone, so callers written before
  /// a cell could hold several need not change.
  final List<VectorFieldParser> vectorFields;

  /// The series index of the first vector line.
  ///
  /// A cell numbers its plots in the order they are written, and a sweep is
  /// one of them. Colouring it from index 0 handed it the same colour as the
  /// first curve on the same axes.
  final int vectorSeriesBase;

  final bool showContour;

  /// How far towards the camera a mesh line is moved before depth sorting,
  /// as a fraction of the plan's on-screen size.
  ///
  /// It has to beat a whole cell, not a hair. A mesh line lies on the surface,
  /// so it competes with the triangles either side of it, and at 2% — less
  /// than one cell's depth — roughly two thirds of it was painted over and
  /// the grid came out as dashes. Measured on a hyperboloid, surviving mesh
  /// went from 458 pixels at 2% to 1,460 at 12%, where the gain has largely
  /// flattened.
  ///
  /// Bounded above by show-through: the bias is about 9% of a sphere's depth
  /// here, so a line on the far side stays behind the near one. At 80% the
  /// back of the sphere draws straight through the front.
  static const double _meshDepthBias = 0.12;

  /// How far towards the camera a level surface's grid line is moved before it
  /// is sorted, as a fraction of the plan's on-screen size.
  ///
  /// Much smaller than [_meshDepthBias], and for a reason that no longer
  /// applies here. That figure had to beat a whole batch of lines drawn at one
  /// depth; a level surface's grid is geometry now and sorts segment by
  /// segment, so the bias only has to beat the cell the segment lies in. One
  /// marching cell is `2 / 40` of the box, which is what this is — enough to
  /// keep the line off the triangles either side of it, small enough that a
  /// line on the far side of a fold stays hidden.
  static const double _levelMeshDepthBias = 0.05;

  /// How wide a mesh line is drawn, in logical pixels.
  ///
  /// Finer than when the line was black: a line that takes the surface's own
  /// colour needs less width to be read, and a thinner one reads as drawn on
  /// the shape rather than laid over it.
  static const double _meshStrokeWidth = 1.5;

  /// How many planes a level surface is sliced by on each axis.
  ///
  /// Fewer than [_meshLinesAcross], because a level surface is sliced on three
  /// axes where a sampled one is ruled on two: at the same count per axis it
  /// carries half as many lines again, and they cross each other rather than
  /// forming a quad grid. Measured on `x⁴+y⁴+z⁴−x²−y²−z²+0.4`, fourteen put
  /// 11.8% of the surface under black — about one pixel in eight — which reads
  /// as a net thrown over the shape rather than as a grid on it. Ten brings
  /// that to 5.9%.
  ///
  /// Chosen over drawing a thinner line, which was the other way to the same
  /// place: dropping the stroke from 1.8 px to 1.2 px only reached 8.2%, and a
  /// line that thin starts to break up over a bright colormap. Slicing less
  /// also costs less — there is less to cut, keep, project and sort — where a
  /// thinner line costs exactly the same.
  ///
  /// Twelve since the lines took the surface's colour. Ten was set against
  /// black ink, where every line was loud; a line in the surface's own deeper
  /// shade is quiet enough to carry two more per axis, and on a thin tube that
  /// is the difference between two rings and three.
  static const int _levelMeshLinesAcross = 12;

  /// How many cells apart the mesh lines are drawn.
  ///
  /// Aims for a fixed number of lines across the surface whatever the
  /// sampling grid is doing, so the mesh does not thin out and thicken again
  /// as the grid drops for a drag and comes back at rest.
  static const int _meshLinesAcross = 14;

  static int _meshStrideFor(int cells) =>
      cells <= _meshLinesAcross ? 1 : (cells / _meshLinesAcross).round();

  /// Draw the surface's own grid over it.
  ///
  /// The lines go into the same depth-sorted scene as the cells they belong
  /// to, so the far side of a fold is hidden by the near side rather than
  /// showing through — a wireframe painted on afterwards would read as a flat
  /// net lying over the picture.
  final bool showMesh;
  final SurfaceMode surfaceMode;
  final AppColors colors;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  /// True when the cell is a sweep rather than something sampled over space.
  bool get _isParametric => vectorParser?.isParametric ?? false;

  /// Which components of a complex line are on show.
  final ComplexView complexView;

  /// The spans u and v are swept over when the expression is parametric.
  final ParameterRange uRange;
  final ParameterRange vRange;

  /// Where the trace marker sits, in data coordinates, or null when the plot
  /// is not being traced.
  final SurfaceHit? tracePoint;

  /// True while the plot is being dragged, pinched or spinning.
  ///
  /// A surface is sampled more finely when it is still. At rest the mesh is
  /// built once and then only redrawn, so the extra gridSize cost a single frame;
  /// in motion every frame pays for them, and a 50-cell surface already takes
  /// most of a 60 Hz frame.
  final bool interacting;

  /// The panel size to fit the box to, when that is not the canvas.
  ///
  /// Set while the panel is still resizing — the keypad sliding away grows
  /// the plot on every frame — so the box keeps the size it had and only
  /// slides to stay on its floor line. Null fits to the canvas, as always.
  final Size? fitSize;

  /// Whether the axes are drawn: their lines, arrowheads, names, ticks and
  /// numbers. The floor and its outline stay either way — they are the
  /// ground the shape stands on, not a scale.
  final bool showAxes;

  /// Where no axis number may be drawn, in canvas coordinates: the controls
  /// floating over the plot. A number under a control cannot be read, so it
  /// is left out rather than drawn there.
  final List<Rect> labelKeepOut;

  /// The ramp values are coloured with: the theme's, so it repaints with it.
  PlotPalette get palette => plotTheme.palette;

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
    this.bottomInset = 0,
    this.vectorFields = const <VectorFieldParser>[],
    this.vectorSeriesBase = 0,
    required this.showContour,
    this.showMesh = false,
    required this.surfaceMode,
    required this.colors,
    required this.plotTheme,
    this.uRange = defaultParameterRange,
    this.vRange = defaultParameterRange,
    this.complexView = ComplexView.initial,
    this.tracePoint,
    this.interacting = false,
    this.fitSize,
    this.showAxes = true,
    this.labelKeepOut = const <Rect>[],
    BackgroundMarches? marches,
  }) : marches = marches ?? BackgroundMarches.shared,
       // A refined level surface made off the UI thread is drawn as soon as it
       // lands, however still the plot is.
       super(repaint: (marches ?? BackgroundMarches.shared).landed);

  /// Where refined level surfaces are made off the UI thread: the app's, or a
  /// test's own.
  final BackgroundMarches marches;

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

  /// The focal length this paint projects with, which is the fitted size's
  /// rather than the canvas's while a resize is settling.
  double _focalLength = 0;

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
      max(size.width, size.height) * _perspective;

  /// How strong the perspective is: the focal length as a multiple of the
  /// panel's longer side. Lower is more dramatic.
  ///
  /// **Lower this for a more three-dimensional look, at the cost of framing.**
  /// Strong perspective throws the top of the box sideways much further than
  /// its base, so a plot cannot be both wide at the floor and tall in z — at
  /// 1.15 the height stopped at three quarters of the panel whatever the
  /// other knobs said. This is high enough that the top and the base project
  /// to nearly the same width, which is what lets both fill.

  /// How far past the box an axis arrow reaches, as a fraction of the range.
  ///
  /// The real edge of the drawing: the box corners are not what runs off the
  /// canvas first, the arrowheads are.
  static const double axisArrowOvershoot = 1.18;

  /// How much of the viewport the drawing is allowed to reach across.
  /// Half-width of the floor plane, as a fraction of the panel width.
  ///
  /// **This is the knob for the size of the xy plane.** It sets the plane
  /// outright — nothing else reads it, so changing it moves the floor and
  /// leaves the z axis exactly where it was.
  ///
  /// The floor is drawn turned, so it covers rather more of the panel than
  /// this figure: its diagonal is what faces you, about 2.8 times the
  /// half-width. At 0.32 the grid spans roughly 90% of the width.
  static const double _planExtent = 0.32;

  /// Half-height of the z axis, as a fraction of the panel height.
  ///
  /// **This is the knob for the length of the z axis**, and it is
  /// independent of [_planExtent] in both directions: neither is fitted
  /// against the other, and neither is scaled to make room.
  ///
  /// Nothing shrinks to accommodate a large value here, which also means
  /// nothing stops it overrunning the panel. Measured on a 988 x 1210 panel,
  /// with _planExtent at 0.32:
  ///
  ///     _zExtent   z axis height   whole drawing
  ///         0.25             49%             83%
  ///         0.35             68%             98%
  ///         0.40             78%            108%   clipped
  ///         0.55            108%            133%   clipped
  ///
  /// One per shape of screen, split the same way the floor line is, because
  /// how long the axis can be depends on how much height there is to spend: a
  /// landscape tablet has little and a portrait one has plenty.
  ///
  /// Independent of the placement knobs in both directions. Changing one of
  /// these grows or shrinks the axis about the floor, which stays where
  /// [_floorLineFor] puts it; changing a floor line slides everything without
  /// altering any length.
  static const double _zExtentLandscape = 0.5;
  static const double _zExtentPortrait = 0.4;
  static const double _zExtentPhone = 0.45;

  /// Which of those applies, from the shape of the plot area.
  static double _zExtentFor(Size size) => switch (_formFactorOf(size)) {
    _Panel.phone => _zExtentPhone,
    _Panel.tabletLandscape => _zExtentLandscape,
    _Panel.tabletPortrait => _zExtentPortrait,
  };

  /// Where the floor plane sits, as a fraction of the panel height from the
  /// top, when the box is taller than the panel.
  ///
  /// **These are the knobs for vertical placement**, one per shape of screen,
  /// because the right answer genuinely differs: a landscape tablet wants the
  /// floor high, a portrait one wants it low, and a phone fits without any of
  /// this mattering.
  ///
  /// Anchored on the floor rather than on the top of the box, which is what
  /// decouples this from [_zExtent]. Hung from the box's top edge, making the
  /// z axis taller pushed everything down as a side effect — the same knob
  /// moved two things. The floor's own position depends on the plan and the
  /// tilt and nothing else, so lengthening z now grows the axis upward and
  /// leaves the plane where it was.
  static const double _floorLineLandscape = 1.0;
  static const double _floorLinePortrait = 0.86;
  static const double _floorLinePhone = 0.95;

  /// Which of those applies, from the shape of the plot area.
  ///
  /// Read from the panel rather than passed in, so nothing upstream has to
  /// know about it and a rotation is picked up on the next paint.
  static double _floorLineFor(Size size) => switch (_formFactorOf(size)) {
    _Panel.phone => _floorLinePhone,
    _Panel.tabletLandscape => _floorLineLandscape,
    _Panel.tabletPortrait => _floorLinePortrait,
  };

  /// The kind of screen a plot area of this shape belongs to.
  ///
  /// 600 is the same threshold the keypad uses to decide it is on a tablet.
  /// One rule for both sets of knobs, so the axis length and the floor line
  /// can never disagree about which device they are on.
  static _Panel _formFactorOf(Size size) {
    if (size.shortestSide < 600 && size.width < 600) return _Panel.phone;
    return size.width > size.height
        ? _Panel.tabletLandscape
        : _Panel.tabletPortrait;
  }

  /// The perspective strength, as a multiple of the panel's longer side.
  ///
  /// Lower is more dramatic. It also decides how independent the two extents
  /// really are on screen: the floor sits at the *bottom* of the box, so a
  /// longer z axis pushes it further away, and under strong perspective it
  /// then projects smaller. At 4 the floor lost four points of width as
  /// _zExtent went from 0.25 to 0.55; at 15 it holds to within one.
  ///
  /// The cost of a figure this high is depth: the box is drawn very nearly
  /// square-on, so near and far edges are close to the same size. Lower it
  /// for a more three-dimensional look and accept that z and the plan will
  /// pull on each other again.
  static const double _perspective = 1.15;

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
  /// Where the drawing sits vertically: centred when it fits, hung from the
  /// top when it does not.
  ///
  /// On a panel too short for the box — a tablet in landscape, where a floor
  /// spanning the width is deeper than the panel is tall — centring divides
  /// the loss between the top and the bottom, and the top is where the
  /// surface is. The bottom of the box is mostly the empty half below the
  /// floor, which is the part worth losing.
  ///
  /// Shrinking the box until it fits was the other way out and it wastes the
  /// width, which is the thing a wide screen has most of.
  static double _verticalPlacement(
    ({double left, double right, double top, double bottom, double floor}) b,
    double floorLine,
    Size size,
  ) {
    // Applied whether or not the box fits.
    //
    // This used to fall back to plain centring when the drawing fitted the
    // panel, which made _floorLinePhone dead code: a phone's box fits, so it
    // took that branch every time and the knob did nothing.
    // b.floor is in the same space as b.top: distance above the middle of the
    // canvas, before the offset. Wanting it at `floorLine` down the panel
    // means an offset of that minus where it would otherwise fall.
    //
    // Whatever runs off the panel as a result is the empty half below the
    // plane, and the tip of the z axis above it — which is the trade the knob
    // exists to let you make.
    return b.floor - size.height * (0.5 - floorLine);
  }

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
      // The centre of the floor plane, which is what the vertical placement
      // is measured from. On the axis, so no rotation moves it sideways.
      (0, 0, -vertical),
    ];
  }

  static String? _fitKey;
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
    // Keyed on the knobs as well as the size, so editing one and hot
    // reloading actually re-fits. Keyed on size alone, a changed constant
    // looked like it did nothing at all.
    final double floorLine = _floorLineFor(size);
    final String key =
        '$size|$_planExtent|${_zExtentFor(size)}|$floorLine|'
        '$_perspective|$_fitTilt';
    if (_fitKey == key && _fitResult != null) return _fitResult!;

    final double focalLength = focalLengthFor(size);
    final double ct = cos(_fitTilt), st = sin(_fitTilt);

    // The shape comes from the knobs; the size comes from the panel.
    //
    // _planExtent and _zExtent set the proportions of the box — how wide the
    // floor is against how tall the axis. That ratio is a matter of taste and
    // stays exactly as written. What cannot be written down in advance is how
    // big the result may be, because that depends on the panel: the same
    // proportions that fill a phone overflow a landscape tablet by half
    // again, since the floor is drawn tilted and a wide panel gives it a depth
    // the panel has no height for.
    //
    // So the pair is scaled together until the drawing fits, which leaves the
    // shape untouched and uses whatever room there is. Nothing is special
    // cased per device.
    final double shapePlanar = size.width * _planExtent;
    final double shapeVertical = size.height * _zExtentFor(size);

    /// Where the drawing lands, over a full turn of azimuth, so the centring
    /// holds at every rotation rather than only the one it was measured at.
    ///
    /// Null when the box reaches the eye, where the projection stops meaning
    /// anything.
    ({double left, double right, double top, double bottom, double floor})?
    boundsOf(double scale) {
      double left = double.infinity, right = double.negativeInfinity;
      double top = double.negativeInfinity, bottom = double.infinity;
      // Where the plane itself lands, which is what the placement is hung on.
      //
      // Its centre, not the average of its corners. Averaging let one corner
      // dominate: the near one sits closest to the eye, so its perspective
      // factor is the largest, and on a small panel that produced a "floor"
      // thousands of pixels from anything real. The centre is on the axis, so
      // no azimuth moves it and no corner can skew it.
      double floorCentre = 0;
      for (int a = 0; a < 36; a++) {
        final double az = a * pi / 18;
        final double ca = cos(az), sa = sin(az);
        for (final (double x, double y, double z) in _fitPoints(
          shapePlanar * scale,
          shapeVertical * scale,
        )) {
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
          if (x == 0 && y == 0 && z == -shapeVertical * scale) {
            floorCentre = vz * k;
          }
        }
      }
      return (
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        floor: floorCentre,
      );
    }

    // No scaling to fit. The shape is the shape, at full size, because on a
    // wide panel shrinking it until it fits is exactly what wastes the width
    // a tablet has most of.
    final double planar = shapePlanar;
    final double vertical = shapeVertical;

    // Centre what is actually drawn, not the origin it is drawn around.
    final b = boundsOf(1);
    final ViewFit fit = ViewFit(
      planar: planar,
      vertical: vertical,
      offsetX: b == null ? 0 : -(b.left + b.right) / 2,
      offsetY: b == null ? 0 : _verticalPlacement(b, floorLine, size),
    );
    _fitKey = key;
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
    final Size frame = fitSize ?? size;
    final double focalLength = focalLengthFor(frame);
    _focalLength = focalLength;
    final ViewFit fit = viewExtentsFor(frame);
    _viewExtentXY = fit.planar;
    _viewExtentZ = fit.vertical;
    _fitOffsetX = fit.offsetX;
    // Centre the box in the part of the panel that can actually be seen. The
    // expression rows float over the bottom now, so the panel is taller than
    // the visible area and a box centred in the whole of it sits too low —
    // badly so in 3D, where the floor plane ends up behind the rows. Half the
    // covered height is exactly the shift that re-centres it.
    //
    // Fitted to another size than the canvas, the floor is then moved to where
    // the canvas's own floor line is, so a box held at its old size during a
    // resize still rides with the panel rather than hanging where it was.
    _fitOffsetY =
        fit.offsetY -
        bottomInset / 2 +
        (size.height - frame.height) * (_floorLineFor(frame) - 0.5);

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
        function.isComplex ||
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
    if (function.isComplex) {
      // Sampled as a complex function over the plane, not as a height of x
      // and y — which would be NaN everywhere.
      _drawHeightSurfaces(canvas, size, focalLength);
    } else if (_isParametric) {
      // Ahead of the field branch for the same reason as in 2D: the notation
      // is shared, and only the variables say whether this is an arrow at
      // every point or one point swept into a curve.
      //
      // This draws the sweep together with any z = f(x, y) and standing curves
      // in the cell, because they all belong in one depth-ordered scene.
      _drawHeightSurfaces(canvas, size, focalLength);
      // Equations are contoured rather than sampled, so they have a renderer
      // of their own and it has to be asked. It only ran in the scalar branch,
      // so a cell holding a sweep and a circle drew the sweep alone — the
      // circle was compiled, framed and then never drawn.
      if (_curves.any((PlotExpression e) => e.isLevelSet)) {
        // The scene above already laid the floor down in depth order.
        _drawLevelSurface(canvas, size, focalLength, withFloor: false);
      }
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

  /// Lattice cells across the box for a level surface.
  static const int _levelResolution = levelResolution;

  /// The same, for anything outside the painter that has to find the surface
  /// that was drawn — a tap on a traced surface is tested against its
  /// triangles (see `pickSurface`).
  static const int levelResolution = 40;

  /// Lattice cells across the box for the stand-in drawn while the full march
  /// is made in the background (see [marches]).
  static const int _levelPlaceholderResolution = 20;

  /// Sample one z = f(x, y) over the floor grid and build its gridSize.
  ///
  /// [minV] and [maxV] cover only the corners actually drawn, so colour maps
  /// across what is on screen rather than across values clipped away.
  /// Cells on a side while still, and while moving.
  /// How finely a surface is sampled, still and while being moved.
  ///
  /// Cost is quadratic in these: every cell is clipped, rotated, projected and
  /// depth-sorted on every frame, and the sampling itself is cached but none of
  /// that is. Measured on a 400x900 panel, a still frame costs about 34 ms at
  /// 76 and a drag frame about 10 ms at 42 — it was 13.5 ms at 50.
  ///
  /// The moving figure is the one that is felt, since it is paid on every frame
  /// of a rotation; the still one is paid once on release. Lower the moving
  /// number for smoother dragging at the cost of a coarser surface while the
  /// finger is down.
  static const int _surfaceGridStill = 76;
  static const int _surfaceGridMoving = 42;

  /// How many labelled ticks each half of an axis may carry.
  ///
  /// Two: at most four numbers on an axis and twelve on the whole box. Every
  /// unit labelled put eighteen to thirty numbers over the plot, and they
  /// landed on the surface and under the controls.
  static const int _maxTicksPerSide = 2;

  /// The smallest round step — 1, 2 or 5 times a power of ten — that fits
  /// [extent] in at most [maxSteps] whole steps.
  static double _niceStep(double extent, int maxSteps) {
    // log() and floor() throw on Infinity and NaN rather than returning a
    // garbage double, and a range persists in the widget's state, so an
    // unusable one would take every frame down with it.
    if (!extent.isFinite || extent <= 0 || maxSteps <= 0) return 1;
    final double exponent = (log(extent / maxSteps) / ln10).floorToDouble();
    if (!exponent.isFinite) return 1;
    final double magnitude = pow(10, exponent).toDouble();
    if (!magnitude.isFinite || magnitude <= 0) return 1;
    for (final double m in const <double>[1, 2, 5, 10]) {
      final double step = m * magnitude;
      if ((extent / step + 1e-9).floor() <= maxSteps) return step;
    }
    return 10 * magnitude;
  }

  /// The step between labelled ticks on an axis running over ±[range].
  ///
  /// The ticks sit on its multiples, so they read 0.5, 1, 2 rather than
  /// wherever the edge of the box happened to fall. They used to be counted
  /// from the edge: a ±3.06 box was labelled −2.06, −1.06, 0.94, 1.94, 2.94.
  static double _tickStep(double range) => _niceStep(range, _maxTicksPerSide);

  /// The values an axis over ±[range] is labelled at, for tests.
  @visibleForTesting
  static List<double> axisTicksFor(double range) =>
      _ticksWithin(range, _tickStep(range)).toList();

  /// The multiples of [step] within ±[range], zero left out.
  static Iterable<double> _ticksWithin(double range, double step) sync* {
    if (!range.isFinite || !step.isFinite || step <= 0) return;
    final int last = (range / step + 1e-9).floor();
    for (int k = -last; k <= last; k++) {
      if (k != 0) yield k * step;
    }
  }

  /// Floor grid lines across ±[range]: every fifth one major, the majors on
  /// the labelled ticks, so a number on an axis always sits on a line.
  static Iterable<(double, bool)> _gridLinesWithin(double range) sync* {
    final double minor = _tickStep(range) / 5;
    if (!range.isFinite || !minor.isFinite || minor <= 0) return;
    final int last = (range / minor + 1e-9).floor();
    for (int k = -last; k <= last; k++) {
      yield (k * minor, k % 5 == 0);
    }
  }

  /// Paint [text] centred on [at], over a halo of the plot's own ground.
  ///
  /// The halo is what lets a number sit over a surface and still be read:
  /// without it a label crossing a bright colormap, or a line of the mesh,
  /// broke up into the picture behind it.
  /// Laid-out axis text, kept between frames.
  ///
  /// Every number on the axes was laid out afresh on every frame, twice over
  /// for its halo — a third of what a rotating frame cost. A plot shows a few
  /// dozen distinct labels in a handful of shades, so a small store holds all
  /// of them.
  static final Map<String, TextPainter> _labels = <String, TextPainter>{};
  static const int _labelsKept = 160;

  /// [text] in [style], or its outline in [halo] when that is given.
  static TextPainter _laidOut(String text, TextStyle style, {Color? halo}) {
    final String key =
        '$text|${style.fontSize}|${style.fontWeight?.value}|'
        '${style.color?.toARGB32()}|${halo?.toARGB32()}';
    final TextPainter? kept = _labels.remove(key);
    if (kept != null) {
      _labels[key] = kept;
      return kept;
    }
    final TextPainter made = TextPainter(
      text: TextSpan(
        text: text,
        style:
            halo == null
                ? style
                : TextStyle(
                  fontSize: style.fontSize,
                  fontWeight: style.fontWeight,
                  foreground:
                      Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..strokeJoin = StrokeJoin.round
                        ..color = halo,
                ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _labels[key] = made;
    if (_labels.length > _labelsKept) {
      _labels.remove(_labels.keys.first)?.dispose();
    }
    return made;
  }

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

  /// Which components of a complex line are drawn, and in which order.
  ///
  /// Ordered so the palette is stable: turning the real part off must not
  /// recolour the imaginary one, which is what a list built by filtering would
  /// do.
  List<({ComplexPart part, int series})> get _complexSurfaces {
    final List<({ComplexPart part, int series})> out =
        <({ComplexPart part, int series})>[];
    if (complexView.real) out.add((part: ComplexPart.real, series: 0));
    if (complexView.imaginary) {
      out.add((part: ComplexPart.imaginary, series: 1));
    }
    if (complexView.modulus) out.add((part: ComplexPart.modulus, series: 2));
    return out;
  }

  /// The colorbar's geometry, shared by the bar and by the axis labels that
  /// have to stay off it.
  ///
  /// Inset well clear of the corner: a phone's display is rounded there, and
  /// at ten pixels from the edge the last number of the scale was cut by the
  /// curve of the glass rather than by anything in the app.
  static const double _colorbarHeight = 12.0;
  static const double _colorbarMarginRight = 18.0;
  static const double _colorbarMarginTop = 12.0;

  /// From one bar to the next when several are stacked: the bar, the gap to
  /// its numbers, the numbers, and air. Rows used to step by the bar's height
  /// alone, so each bar was drawn over the numbers of the one above it.
  static const double _colorbarPitch = 36.0;

  static double _colorbarWidth(Size size) =>
      (size.width * 0.45).clamp(80.0, 220.0);

  /// Where the colorbar, with its numbers, can be: kept clear by the axes.
  static Rect _colorbarZone(Size size) {
    final double width = _colorbarWidth(size);
    return Rect.fromLTWH(
      size.width - width - _colorbarMarginRight - 4,
      0,
      width + _colorbarMarginRight + 4,
      _colorbarMarginTop + _colorbarPitch,
    );
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
      // Every input below changes the picture on its own, and a field left
      // out of this list is one the plot ignores until something else moves:
      // the trace marker did not appear on a long press, Re/Im/|f| did not
      // redraw, a new row's inset left the box where it was, and a surface
      // stayed at its coarse dragging grid after the finger lifted.
      !listEquals(old.functions, functions) ||
      old.is3DFunction != is3DFunction ||
      old.plotMode != plotMode ||
      old.fieldType != fieldType ||
      old.vectorParser != vectorParser ||
      !listEquals(old.vectorFields, vectorFields) ||
      old.vectorSeriesBase != vectorSeriesBase ||
      old.bottomInset != bottomInset ||
      old.showContour != showContour ||
      old.showMesh != showMesh ||
      old.surfaceMode != surfaceMode ||
      old.colors != colors ||
      old.plotTheme != plotTheme ||
      old.complexView != complexView ||
      old.uRange != uRange ||
      old.vRange != vRange ||
      old.tracePoint != tracePoint ||
      old.interacting != interacting ||
      old.fitSize != fitSize ||
      old.showAxes != showAxes ||
      !listEquals(old.labelKeepOut, labelKeepOut);
}

/// The shapes of screen the framing knobs are split across.
enum _Panel { phone, tabletLandscape, tabletPortrait }
