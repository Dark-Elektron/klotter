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

  /// The fields to draw, with [vectorParser] as the fallback.
  List<VectorFieldParser> get fieldsToDraw =>
      vectorFields.isNotEmpty
          ? vectorFields
          : (vectorParser == null
              ? const <VectorFieldParser>[]
              : <VectorFieldParser>[vectorParser!]);
  final bool showContour;

  /// Put a surface's grid lines into [scene].
  ///
  /// Shared by every surface built from a sampling grid — heights, complex
  /// components, sweeps — so they all mesh the same way rather than each
  /// growing its own copy.
  ///
  /// [inkAt] gives the colour each end is drawn in: the surface's own colour
  /// there, darkened — see [meshInkArgb].
  void _addMeshTo(
    _DepthScene scene,
    List<_GridPiece> mesh,
    Size size,
    double focalLength,
    int Function(double value, double light) inkAt,
  ) {
    if (!showMesh || mesh.isEmpty) return;
    // Nudged towards the camera before it is sorted: a mesh line lies exactly
    // on the surface, so its depth ties with the cell it belongs to, and the
    // sort would decide between them segment by segment — which drew the mesh
    // as a row of dashes rather than a line.
    final double bias = _viewExtentXY * _meshDepthBias;
    final double half = _meshStrokeWidth / 2;
    for (final _GridPiece piece in mesh) {
      final Offset a = piece.a.project(focalLength, size, _panX, _panY);
      final Offset b = piece.b.project(focalLength, size, _panX, _panY);
      final Offset along = b - a;
      final double len = along.distance;
      if (len < 1e-6) continue;
      // A thin quad rather than a stroke, as a level surface's grid is drawn:
      // two triangles that go into the batch with the cells, so a line no
      // longer breaks the batch, and that can be shaded from one end to the
      // other. Run on by half a width at each end so the pieces of one line
      // overlap at their joins instead of leaving a notch on every bend.
      final Offset unit = along / len;
      final Offset side = Offset(-unit.dy, unit.dx) * half;
      final Offset start = a - unit * half;
      final Offset end = b + unit * half;
      final int ca = inkAt(piece.va, piece.la);
      final int cb = inkAt(piece.vb, piece.lb);
      final double depth = (piece.a.y + piece.b.y) / 2 - bias;
      scene.addTriangle(
        start + side,
        start - side,
        end - side,
        ca,
        ca,
        cb,
        depth,
      );
      scene.addTriangle(
        start + side,
        end - side,
        end + side,
        ca,
        cb,
        cb,
        depth,
      );
    }
  }

  /// How far apart the slicing planes are on [axis], in world units.
  ///
  /// Aims for about the same number of lines across each direction as a
  /// height surface's grid, so every kind of surface meshes at one density.
  double _meshPlaneStep(int axis) {
    // In view units, not data units.
    //
    // A level surface's vertices are scaled on the way out of the marcher —
    // `scaleX` is `_viewExtentXY / rangeX` — so a spacing measured in x and y
    // is a spacing in the wrong space. Against a range of 3 it put the planes
    // 0.43 view units apart instead of about 20: some seven hundred of them
    // across the box, which cut the surface into confetti.
    final double extent = axis == 2 ? _viewExtentZ : _viewExtentXY;
    return extent <= 0 ? 0 : 2 * extent / _levelMeshLinesAcross;
  }

  /// Project a run of grid segments into [screen] as thin screen-space quads.
  ///
  /// Two triangles each, written after the surface's own triangles and sharing
  /// its depth buffer, so the sort that follows treats a grid line as just
  /// another piece of geometry lying on the surface.
  void _projectMeshLines(
    Float32List lines,
    Int32List from,
    Float32List reach,
    int segments,
    int firstTriangle,
    Float32List screen,
    Float64List depth,
    double cz,
    double sz,
    double cx,
    double sx,
    double focalLength,
    double halfW,
    double halfH,
  ) {
    if (segments == 0) return;
    final double bias = _viewExtentXY * _levelMeshDepthBias;
    final double half = _meshStrokeWidth / 2;

    for (int s = 0; s < segments; s++) {
      final int m = s * 6;
      double sxA = 0, syA = 0, dA = 0, sxB = 0, syB = 0, dB = 0;

      for (int end = 0; end < 2; end++) {
        final double x = lines[m + end * 3];
        final double y = lines[m + end * 3 + 1];
        final double z = lines[m + end * 3 + 2];
        // The same turntable and projection the triangles go through.
        final double x1 = x * cz - y * sz;
        final double y1 = x * sz + y * cz;
        final double y2 = y1 * cx - z * sx;
        final double z2 = y1 * sx + z * cx;
        final double scale = focalLength / (focalLength + y2);
        final double px = halfW + x1 * scale + _panX;
        final double py = halfH - z2 * scale + _panY;
        if (end == 0) {
          sxA = px;
          syA = py;
          dA = y2;
        } else {
          sxB = px;
          syB = py;
          dB = y2;
        }
      }

      final int t = firstTriangle + s * 2;
      // Lifted by the usual amount, a lattice cell, but never by more than
      // the triangle it was cut from. See [LevelMesh.meshLineTriangle].
      depth[t] = (dA + dB) / 2 - min(bias, reach[from[s]]);
      depth[t + 1] = depth[t];

      // Widened across the segment on screen rather than in world space: the
      // line has to come out the same weight wherever it is on the surface,
      // and a world-space ribbon would thin out with distance and vanish
      // edge-on to the camera.
      final double dx = sxB - sxA;
      final double dy = syB - syA;
      final double len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        // Nothing to draw, but the slots are already counted: leave two
        // degenerate triangles rather than shuffling everything down.
        for (int k = 0; k < 12; k++) {
          screen[t * 6 + k] = sxA;
        }
        continue;
      }
      final double ox = -dy / len * half;
      final double oy = dx / len * half;

      // Run each piece half a stroke width past both of its ends, so that
      // consecutive pieces overlap instead of meeting flush.
      //
      // A grid line is not one stroke, it is a chain of chords, one per
      // triangle the slicing plane crosses — and marching tetrahedra makes
      // small triangles, so the median chord is 3.3 px against the 1.8 px the
      // line is drawn at. Most joins are nearly straight, but a tenth of them
      // turn by 10 to 22 degrees and a hundredth by up to 68, and cut square
      // across the end every one of those left an open notch on the outside of
      // the bend. Thousands of notches along every line is the serration.
      // Half a width is exactly what closes a corner up to a right angle, and
      // the overhang past a line's true end is under a pixel.
      final double ex = dx / len * half;
      final double ey = dy / len * half;
      final double ax = sxA - ex, ay = syA - ey;
      final double bx = sxB + ex, by = syB + ey;

      final int o = t * 6;
      screen[o] = ax + ox;
      screen[o + 1] = ay + oy;
      screen[o + 2] = ax - ox;
      screen[o + 3] = ay - oy;
      screen[o + 4] = bx - ox;
      screen[o + 5] = by - oy;
      screen[o + 6] = ax + ox;
      screen[o + 7] = ay + oy;
      screen[o + 8] = bx - ox;
      screen[o + 9] = by - oy;
      screen[o + 10] = bx + ox;
      screen[o + 11] = by + oy;
    }
  }

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
    // Hidden equations are dropped before the ramp index is taken, so the ones
    // still showing keep telling themselves apart. Their solid colour comes
    // from the row number, so it does not move when a neighbour is hidden.
    final List<PlotExpression> equations =
        _curves.where((PlotExpression e) => e.isLevelSet && !e.hidden).toList();
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
    final Float32List reach;
    if (meshes.length == 1) {
      world = meshes.first.world;
      meshColors = meshes.first.colors;
      reach = meshes.first.reach;
    } else {
      world = Float32List(count * 9);
      meshColors = Int32List(count * 3);
      reach = Float32List(count);
      int at = 0;
      for (final LevelMesh m in meshes) {
        final int n = m.triangleCount;
        world.setRange(at * 9, (at + n) * 9, m.world);
        meshColors.setRange(at * 3, (at + n) * 3, m.colors);
        reach.setRange(at, at + n, m.reach);
        at += n;
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

    // The grid lines come ready-made off the cached meshes, in the same
    // view-scaled space as the triangles.
    final int segments =
        showMesh
            ? meshes.fold<int>(
              0,
              (int sum, LevelMesh m) => sum + m.meshLineCount,
            )
            : 0;
    final Float32List meshLines;
    final Int32List meshInks;
    final Int32List meshFrom;
    if (segments == 0) {
      meshLines = _noLines;
      meshInks = _noInks;
      meshFrom = _noInks;
    } else if (meshes.length == 1) {
      meshLines = meshes.first.meshLines;
      meshInks = meshes.first.meshLineColors;
      meshFrom = meshes.first.meshLineTriangle;
    } else {
      meshLines = Float32List(segments * 6);
      meshInks = Int32List(segments * 2);
      meshFrom = Int32List(segments);
      int at = 0;
      int firstTriangle = 0;
      for (final LevelMesh m in meshes) {
        final int n = m.meshLineCount;
        meshLines.setRange(at * 6, (at + n) * 6, m.meshLines);
        meshInks.setRange(at * 2, (at + n) * 2, m.meshLineColors);
        for (int s = 0; s < n; s++) {
          meshFrom[at + s] = firstTriangle + m.meshLineTriangle[s];
        }
        at += n;
        firstTriangle += m.triangleCount;
      }
    }

    // Grid lines are drawn as thin quads in the same buffer as the surface,
    // two triangles each, rather than as `drawLine` calls merged in afterwards.
    //
    // That merge was where the grid went wrong. Lines were batched into
    // twenty-four depth slabs and every line in a slab was drawn at the depth
    // of the first, which on these surfaces put five hundred to eight hundred
    // segments — spanning most of the box — at one depth. The grid from the far
    // side was painted over the near side, which is the scribble in the bug
    // report, and the bias that was needed to stop the near grid being painted
    // over in turn made the show-through worse. As geometry each segment
    // carries its own depth and sorts with the triangles it lies on, so the
    // back of a surface is hidden by its front for the same reason the
    // triangles are. It is also 5,000 to 19,000 fewer draw calls a frame.
    final int total = count + segments * 2;

    // Project every vertex once into flat buffers, keeping each triangle's
    // depth for the painter's algorithm.
    final Float32List screen = Float32List(total * 6);
    final Float64List depth = Float64List(total);

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

        // _panX and _panY, not panX and panY: the framing offset has to be
        // included here as it is everywhere else. This path projects by hand
        // rather than through Point3D.project, so it was missed when the
        // offset was added — the axes and the floor moved with the framing
        // and every level surface stayed where it was, which showed up as a
        // sphere sitting off its own origin.
        final double scale = focalLength / (focalLength + y2);
        screen[o + v * 2] = halfW + x1 * scale + _panX;
        screen[o + v * 2 + 1] = halfH - z2 * scale + _panY;
        depthSum += y2;
      }
      depth[t] = depthSum / 3;
    }

    _projectMeshLines(
      meshLines,
      meshFrom,
      reach,
      segments,
      count,
      screen,
      depth,
      cz,
      sz,
      cx,
      sx,
      focalLength,
      halfW,
      halfH,
    );

    // Sort indices, not triangles: moving an int is cheaper than moving nine
    // floats, and the vertex buffers stay put.
    final List<int> order = _farToNear(depth, total);

    // Washed towards the ground with distance (see [depthFog]), from the
    // nearest triangle to the farthest. Worked out here, per frame, because it
    // turns with the camera; the colours it starts from are cached.
    double near = double.infinity, far = double.negativeInfinity;
    for (int t = 0; t < count; t++) {
      final double d = depth[t];
      if (d < near) near = d;
      if (d > far) far = d;
    }
    // In 256ths, so the blend below is integers only.
    final double fogScale = !(far > near) ? 0 : depthFog * 256 / (far - near);
    final int fog = plotTheme.fog.toARGB32();

    final Float32List positions = Float32List(total * 6);
    final Int32List colors = Int32List(total * 3);
    for (int i = 0; i < total; i++) {
      final int src = order[i];
      // Six floats copied by hand: setRange's checks cost more than the copy.
      final int to = i * 6, from = src * 6;
      positions[to] = screen[from];
      positions[to + 1] = screen[from + 1];
      positions[to + 2] = screen[from + 2];
      positions[to + 3] = screen[from + 3];
      positions[to + 4] = screen[from + 4];
      positions[to + 5] = screen[from + 5];
      final int k =
          fogScale == 0
              ? 0
              : min(256, ((depth[src] - near) * fogScale).toInt());
      if (src < count) {
        final int c = i * 3;
        final int m = src * 3;
        colors[c] = fogBlend(meshColors[m], k, fog);
        colors[c + 1] = fogBlend(meshColors[m + 1], k, fog);
        colors[c + 2] = fogBlend(meshColors[m + 2], k, fog);
      } else {
        // A grid line's two triangles, laid out by [_projectMeshLines] as
        // (start, start, end) and (start, end, end): each corner takes the ink
        // of the end it belongs to, so the line shades along its length.
        final int line = (src - count) >> 1;
        final int start = meshInks[line * 2];
        final int end = meshInks[line * 2 + 1];
        final bool first = (src - count).isEven;
        final int c = i * 3;
        colors[c] = fogBlend(start, k, fog);
        colors[c + 1] = fogBlend(first ? start : end, k, fog);
        colors[c + 2] = fogBlend(end, k, fog);
      }
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
      _addAxisMarksTo(chrome, size, focalLength);
    }

    void drawRun(int startTriangle, int endTriangle) {
      if (endTriangle <= startTriangle) return;
      final Vertices vertices = Vertices.raw(
        VertexMode.triangles,
        // Views, not copies: the engine takes its own copy of what it is
        // given, and every mark splits the surface into another run.
        Float32List.sublistView(positions, startTriangle * 6, endTriangle * 6),
        colors: Int32List.sublistView(
          colors,
          startTriangle * 3,
          endTriangle * 3,
        ),
      );
      canvas.drawVertices(vertices, BlendMode.dst, Paint());
      vertices.dispose();
    }

    // Lines go out in batches, not one at a time: splitting the surface at
    // every line costs a drawVertices per line, and that, not the vertex data,
    // is what dominates.
    //
    // The error this trades for is confined to one batch — lines inside a
    // batch are drawn at the depth of the first of them, so a line can sit in
    // front of triangles within that narrow depth band. It is only the floor
    // and the axes that come through here now, a few dozen lines rather than
    // the thousands the grid used to add, so the batches are two or three
    // lines deep and the band is negligible.
    const int maxRuns = 64;
    final List<int> lineOrder = chrome.farToNear;
    final int batch =
        lineOrder.isEmpty ? 1 : (lineOrder.length / maxRuns).ceil();

    //
    // A mark — an axis number, a tick, an arrowhead — is never batched. It
    // starts a batch of its own, so it is placed at exactly its own depth: a
    // number drawn at the depth of a farther line would be covered by the
    // triangles between the two, which are behind it.
    int runStart = 0;
    int drawn = 0;
    int inBatch = 0;
    for (final int item in lineOrder) {
      final bool mark = chrome.isMark[item];
      if (mark || inBatch == 0) {
        final double cut = chrome.depths[item];
        // Everything further away than this is already behind it.
        while (drawn < total && depth[order[drawn]] > cut) {
          drawn++;
        }
        drawRun(runStart, drawn);
        runStart = drawn;
      }
      chrome.painters[item](canvas);
      inBatch = mark ? 0 : (inBatch + 1) % batch;
    }
    drawRun(runStart, total);

    // A solid surface has no ramp, so a bar of numbers beside it labels
    // nothing — and the swatches name ramps that are not on screen. Height
    // surfaces have always held this back; level surfaces drew the bar
    // regardless, which put a rainbow scale over a plain blue shape.
    if (surfaceMode == SurfaceMode.none) return;
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
    final Color Function(double) ramp = surfaceColormap(
      index,
      of: of,
      palette: palette,
    );
    // The ramp is chosen by position among the equations on screen — it only
    // has to tell them apart. The solid colour is the row's, so it matches the
    // swatch beside the expression and the same plot in 2D.
    final Color plain = _theme.seriesColor(equation.seriesIndex);
    final List<double> bounds = <double>[
      -rangeX,
      rangeX,
      -rangeY,
      rangeY,
      -rangeZ,
      rangeZ,
    ];
    // Where the grid falls depends on the surface and the window, not the
    // camera, so it is cut once here with the triangles rather than being
    // rebuilt on every frame of a rotation.
    final List<double>? meshSteps =
        showMesh
            ? <double>[_meshPlaneStep(0), _meshPlaneStep(1), _meshPlaneStep(2)]
            : null;
    // The colours are baked into the cached mesh, so what they were made
    // from — the mode and the ramp — is part of what identifies it.
    final int colouring = surfaceMode.index * 2 + palette.index;
    bool hasMesh(int resolution, {required bool refined}) => hasCachedLevelMesh(
      equation,
      bounds,
      resolution,
      scaleX,
      scaleY,
      scaleZ,
      colouring,
      meshSteps: meshSteps,
      refined: refined,
    );
    // The full lattice with its thin parts looked into, whenever that is to
    // hand — already made into a mesh, or marched and waiting to be.
    final bool refinedToHand =
        hasMesh(_levelResolution, refined: true) ||
        hasMarchedSurface(
          equation,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
          resolution: _levelResolution,
        );
    int resolution = _levelResolution;
    final bool refined;
    if (refinedToHand) {
      refined = true;
    } else if (!marches.enabled) {
      // Refined here and now, unless the box is changing under a pinch:
      // then every frame is a march of its own, and the plain one is used.
      refined = !interacting;
    } else {
      // A coarse march now, and the refined one asked for in the background.
      // The coarse one is an eighth of the work, so arriving at a plot or
      // pinching one no longer waits on the full lattice: arriving at the
      // touching paraboloids froze a Galaxy A54 for over a second, and a
      // pinch marched the whole lattice afresh on every frame.
      //
      // Asked for only for a box that is holding still, which a rotation is
      // and a pinch is not: a pinch would start a march for every frame of
      // itself, each out of date before it began. Once the coarse mesh for a
      // box has been made, the box has outlasted a frame.
      if (!interacting ||
          hasMesh(_levelPlaceholderResolution, refined: false)) {
        marches.march(
          equation,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
          resolution: _levelResolution,
        );
      }
      resolution = _levelPlaceholderResolution;
      refined = false;
    }
    // Marched at most once, and only if the mesh below has to be rebuilt.
    // Both the triangles and the normals are wanted, and both come from the
    // one march.
    LevelSurface? marched;
    LevelSurface march() =>
        marched ??= marchedSurface(
          equation,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
          resolution: resolution,
          refine: refined,
          // A stand-in is up for a moment; its crossings are interpolated.
          exact: resolution == _levelResolution,
        );
    return cachedLevelMesh(
      equation,
      bounds,
      resolution,
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
        for (final LevelTriangle t in march().triangles)
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
      () => march().normals,
      // Colour by height, so the surface carries a readable quantity even
      // though every point on it satisfies the same equation.
      //
      // An inequality bounds a solid rather than tracing a shell, so its
      // surface is drawn see-through: the triangles are already sorted back
      // to front, which is exactly the order alpha blending needs, so the far
      // wall shows through the near one and the shape reads as a body with an
      // inside. A strict inequality, whose own boundary is excluded, is
      // fainter still — the 3D counterpart of the dashed edge in 2D.
      //
      // Off means one colour instead, from the same series palette as every
      // other plot, so an implicit surface sits alongside a height surface
      // without changing scheme.
      // [light] is what makes the shape readable at all. A marched surface
      // has no grid of its own to shade it and every point on it satisfies the
      // same equation, so with one flat colour a fold, a neck and a flat sheet
      // all come out as the same block of blue and only the mesh says which is
      // which. It costs nothing to draw: the normal it is worked out from does
      // not depend on the camera, so the lit colour is baked in here with the
      // geometry and the frame does no lighting at all.
      (double z, double light) {
        final bool solid = surfaceMode == SurfaceMode.none;
        final Color base =
            solid ? plain : ramp(((z + rangeZ) / (2 * rangeZ)).clamp(0.0, 1.0));
        // Darkening only, never brightening: whatever faces the light keeps
        // the colour the colorbar and the row's swatch show, and the rest is
        // shaded down from it. Brightening instead would have put colours on
        // the surface that appear nowhere in the legend. A surface coloured by
        // height is shaded more gently, so its colours stay near enough to the
        // colorbar to be read off it.
        final int lit = litSurfaceArgb(
          base.toARGB32(),
          light,
          strength: solid ? 1 : _valueShadeStrength,
        );
        if (!equation.relation.isRegion) return lit;
        final int alpha =
            ((equation.relation.includesBoundary ? 0.55 : 0.34) * 255).round();
        return (alpha << 24) | (lit & 0x00FFFFFF);
      },
      // The mesh is cached, and its colours are baked into it, so the mode
      // has to be part of what identifies it. Without this, switching the
      // colouring redrew the same triangles in the colours they already had.
      colouring,
      meshSteps: meshSteps,
      refined: refined,
    );
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

  ({List<Quad> quads, double minV, double maxV, List<_GridPiece> mesh})
  _surfaceQuads(
    PlotExpression parser, {
    int? gridSize,
    double Function(double x, double y)? heightAt,
    int surfaces = 1,
    double Function(double x, double y)? valueAt,
  }) {
    // The budget is the whole scene, not one surface.
    //
    // Every surface used to get the full grid, so two surfaces did twice the
    // clipping, rotating, projecting and depth-sorting and a drag frame went
    // from 11 ms to 22 ms. Dividing by the square root keeps the total number
    // of cells roughly fixed however many surfaces share the axes — the same
    // reasoning as the parametric sampler's cell budget.
    final int base = interacting ? _surfaceGridMoving : _surfaceGridStill;
    final int cells =
        gridSize ??
        (surfaces <= 1 ? base : max(16, (base / sqrt(surfaces)).round()));
    // Heights are cached: rotating changes where the camera sees the surface
    // from, not the surface, so re-walking the expression tree every frame was
    // wasted work.
    //
    // [heightAt] steps around the cache as well as around `evaluate`, for the
    // complex surfaces: the cache is keyed on the expression, and one complex
    // line yields up to three different surfaces from it.
    final List<List<double>> sampled =
        heightAt == null
            ? cachedHeightGrid(parser, rangeX, rangeY, cells)
            : <List<double>>[
              for (int i = 0; i <= cells; i++)
                <double>[
                  for (int j = 0; j <= cells; j++)
                    heightAt(
                      -rangeX + (2 * rangeX * i / cells),
                      -rangeY + (2 * rangeY * j / cells),
                    ),
                ],
            ];

    // How square each sample stands to the key light, from the slope of the
    // surface there. Read off the lattice already sampled, so the light costs
    // no further evaluations: central where both neighbours exist, one-sided
    // at the rim and beside a hole.
    final double stepX = 2 * rangeX / cells;
    final double stepY = 2 * rangeY / cells;
    double lightAt(int i, int j) {
      final double here = sampled[i][j];
      double slope(double before, double after, double step) {
        final bool hasBefore = before.isFinite;
        final bool hasAfter = after.isFinite;
        if (hasBefore && hasAfter) return (after - before) / (2 * step);
        if (hasAfter) return (after - here) / step;
        if (hasBefore) return (here - before) / step;
        return 0;
      }

      final double fx = slope(
        i > 0 ? sampled[i - 1][j] : double.nan,
        i < cells ? sampled[i + 1][j] : double.nan,
        stepX,
      );
      final double fy = slope(
        j > 0 ? sampled[i][j - 1] : double.nan,
        j < cells ? sampled[i][j + 1] : double.nan,
        stepY,
      );
      // The normal of the surface as drawn, not as written: the box stretches
      // z by a different factor from x and y, so the slopes are taken in its
      // units — the same space the level surfaces are lit in.
      return keyLightOn(-fx * scaleZ / scaleX, -fy * scaleZ / scaleY, 1);
    }

    // Held in data coordinates until the cell is cut, because the cut is
    // against a plane in z and rotating first would hide where that is.
    final List<List<({double x, double y, double z, double v, double l})?>>
    points = <List<({double x, double y, double z, double v, double l})?>>[];
    final List<List<double>> zValues = <List<double>>[];
    double minZ = double.infinity;
    double maxZ = double.negativeInfinity;

    for (int i = 0; i <= cells; i++) {
      final List<({double x, double y, double z, double v, double l})?> row =
          <({double x, double y, double z, double v, double l})?>[];
      final List<double> zRow = <double>[];
      for (int j = 0; j <= cells; j++) {
        final x = -rangeX + (2 * rangeX * i / cells);
        final y = -rangeY + (2 * rangeY * j / cells);
        final double z = sampled[i][j];
        if (!z.isFinite) {
          row.add(null);
          zRow.add(double.nan);
          continue;
        }
        // The true height is kept, however far outside the window it is.
        // Where the surface leaves the box is decided per cell below, by
        // cutting it at the crossing — dropping whole cells left teeth the
        // size of the grid, and holding them at the wall turned the overflow
        // into a flat lid, which is worse: a cone came out with its point cut
        // off square.

        // What the cell is coloured by, which is the height unless told
        // otherwise. Gathered here, while x and y are still the data point:
        // the points below are rotated, so nothing downstream can recover
        // where a corner came from. Colouring a complex surface by reading
        // the rotated coordinates back gave a smooth wash unrelated to the
        // function.
        final double v = valueAt == null ? z : valueAt(x, y);
        // Only what is on screen counts toward the colour range, which is the
        // invariant this method's own doc states and which the clipping broke
        // by taking the range before the window was applied. |f| of (x+yi)²
        // reaches 50 at the corners of a ±5 floor while only the first 5 of
        // that is inside the box, so the whole visible surface landed in the
        // bottom tenth of the ramp and came out uniformly blue.
        if (v.isFinite && z >= -rangeZ && z <= rangeZ) {
          minZ = min(minZ, v);
          maxZ = max(maxZ, v);
        }

        row.add((x: x, y: y, z: z, v: v, l: lightAt(i, j)));
        zRow.add(v);
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

    /// One corner, ready to be cut against the walls.
    Point3D world(({double x, double y, double z, double v, double l}) c) =>
        Point3D(
          c.x * scaleX,
          c.y * scaleY,
          c.z * scaleZ,
        ).rotateZ(rotationZ).rotateX(rotationX);

    /// Sutherland–Hodgman against one wall, in data space.
    ///
    /// A corner outside is replaced by the point where its edge crosses, so
    /// the surface ends exactly where it leaves the box: no teeth, and no lid
    /// either. A convex cell stays convex, so the result fans safely.
    List<({double x, double y, double z, double v, double l})> clip(
      List<({double x, double y, double z, double v, double l})> poly,
      bool keepBelow,
      double limit,
    ) {
      if (poly.isEmpty) return poly;
      bool inside(({double x, double y, double z, double v, double l}) c) =>
          keepBelow ? c.z <= limit : c.z >= limit;

      final List<({double x, double y, double z, double v, double l})> out =
          <({double x, double y, double z, double v, double l})>[];
      for (int k = 0; k < poly.length; k++) {
        final a = poly[k];
        final b = poly[(k + 1) % poly.length];
        final bool aIn = inside(a);
        final bool bIn = inside(b);
        if (aIn) out.add(a);
        if (aIn != bIn) {
          final double t = (limit - a.z) / (b.z - a.z);
          out.add((
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            z: limit,
            v: a.v + (b.v - a.v) * t,
            l: a.l + (b.l - a.l) * t,
          ));
        }
      }
      return out;
    }

    // The mesh is taken from the cell corners, not from the triangles the
    // cell becomes.
    //
    // Clipping turns a cell into a polygon and the polygon into a fan of
    // triangles, so a triangle's edges are chords across the cell rather than
    // its sides. Drawing those gave a mesh of little zigzags instead of a
    // grid. These are the grid lines themselves.
    final List<_GridPiece> mesh = <_GridPiece>[];
    final int meshStride = _meshStrideFor(cells);

    for (int i = 0; i < cells; i++) {
      for (int j = 0; j < cells; j++) {
        final c1 = points[i][j];
        final c2 = points[i + 1][j];
        final c3 = points[i + 1][j + 1];
        final c4 = points[i][j + 1];

        // A missing corner is undefined, not merely out of view, so the cell
        // is dropped rather than cut — there is nothing to cut it against.
        if (c1 == null || c2 == null || c3 == null || c4 == null) continue;

        List<({double x, double y, double z, double v, double l})> poly =
            <({double x, double y, double z, double v, double l})>[
              c1,
              c2,
              c3,
              c4,
            ];

        // Only cut cells that actually straddle a wall; the vast majority do
        // not, and this keeps them on the cheap path.
        final bool straddles =
            poly.any((c) => c.z > rangeZ || c.z < -rangeZ) &&
            poly.any((c) => c.z <= rangeZ && c.z >= -rangeZ);
        if (poly.every((c) => c.z > rangeZ) ||
            poly.every((c) => c.z < -rangeZ)) {
          continue;
        }
        if (straddles) {
          poly = clip(poly, true, rangeZ);
          poly = clip(poly, false, -rangeZ);
          if (poly.length < 3) continue;
        }

        if (showMesh) {
          // Collected here, not before the tests above: a cell that is dropped
          // for running past the top of the box, or for having an undefined
          // corner, draws no surface — and a grid line over nothing is a mesh
          // hanging in the air past the edge of the plot, which is what a
          // complex surface showed.
          //
          // One segment per line rather than per side, so the cell next door
          // does not draw the same one again. Both ends are held inside the
          // box, so a line belonging to a cut cell stops where the surface
          // does instead of carrying on to where the corner would have been.
          double heldIn(double z) => z.clamp(-rangeZ, rangeZ);
          ({double x, double y, double z, double v, double l}) inBox(
            ({double x, double y, double z, double v, double l}) c,
          ) => (x: c.x, y: c.y, z: heldIn(c.z), v: c.v, l: c.l);

          if (j % meshStride == 0) {
            mesh.add((
              a: world(inBox(c1)),
              b: world(inBox(c2)),
              va: c1.v,
              vb: c2.v,
              la: c1.l,
              lb: c2.l,
            ));
          }
          if (i % meshStride == 0) {
            mesh.add((
              a: world(inBox(c1)),
              b: world(inBox(c4)),
              va: c1.v,
              vb: c4.v,
              la: c1.l,
              lb: c4.l,
            ));
          }
        }

        // Fanned from the first corner. A clipped cell has three to six
        // corners and is still convex, so a fan covers it without overlap.
        for (int k = 1; k + 1 < poly.length; k++) {
          final a = poly[0];
          final b = poly[k];
          final d = poly[k + 1];
          final Point3D pa = world(a);
          final Point3D pb = world(b);
          final Point3D pd = world(d);
          quads.add(
            Quad(
              pa,
              pb,
              pd,
              pd,
              (pa.y + pb.y + pd.y) / 3,
              (a.v + b.v + d.v) / 3,
              v1: a.v,
              v2: b.v,
              v3: d.v,
              v4: d.v,
              l1: a.l,
              l2: b.l,
              l3: d.l,
              l4: d.l,
            ),
          );
        }
      }
    }

    return (quads: quads, minV: minZ, maxV: maxZ, mesh: mesh);
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
    if (curves.isEmpty &&
        _lineCurves.isEmpty &&
        !_isParametric &&
        !function.isComplex) {
      return;
    }

    // The floor joins the same ordered list as the surfaces, so the two
    // occlude each other instead of the surfaces always winning.
    final _DepthScene scene = _DepthScene();
    _addFloorGridTo(scene, size, focalLength);
    _addAxisChromeTo(scene, size, focalLength);

    double? soleMin;
    double? soleMax;
    final List<(int, double, double)> ranges = <(int, double, double)>[];

    for (int c = 0; c < curves.length; c++) {
      if (curves[c].hidden) continue;
      final built = _surfaceQuads(curves[c], surfaces: curves.length);
      if (built.quads.isEmpty) continue;

      // Each surface is coloured against its own range. Sharing one range
      // across all of them would flatten a shallow surface to a single colour
      // whenever a steeper one is on the same axes.
      final Color Function(double) ramp = surfaceColormap(
        c,
        of: curves.length,
        palette: palette,
      );
      final double span = built.maxV - built.minV;

      // Off means one colour, not one ramp. The menu had offered this all
      // along and the painter ignored it, so a surface was always coloured by
      // its own height — which the shape already shows.
      final bool solid = surfaceMode == SurfaceMode.none;
      // The series palette, always — including for a lone surface. Falling
      // back to the accent when there was only one meant a surface was yellow
      // on its own and blue the moment a second was added, so adding a plot
      // recoloured the one already there.
      final Color plain = _theme.seriesColor(curves[c].seriesIndex);
      final int plainArgb = plain.toARGB32();

      // A corner's colour under the key light, the same light a level surface
      // is lit by. Solid used to be shaded by how squarely each cell faced the
      // camera, which lights whatever you look at straight on and so hides
      // the shape exactly where you are looking at it; coloured by value it
      // was not lit at all.
      int shade(double v, double light) =>
          solid
              ? litSurfaceArgb(plainArgb, light)
              : litSurfaceArgb(
                ramp(((v - built.minV) / span).clamp(0.0, 1.0)).toARGB32(),
                light,
                strength: _valueShadeStrength,
              );

      if (curves.length == 1) {
        soleMin = built.minV;
        soleMax = built.maxV;
      }
      // Every surface's own span, so each ramp can be given a scale rather
      // than a swatch. A swatch says which surface a colour belongs to; it
      // does not say what the colour means, which is the whole point of
      // colouring by value.
      ranges.add((c, built.minV, built.maxV));

      for (final quad in built.quads) {
        final o1 = quad.p1.project(focalLength, size, _panX, _panY);
        final o2 = quad.p2.project(focalLength, size, _panX, _panY);
        final o3 = quad.p3.project(focalLength, size, _panX, _panY);
        final o4 = quad.p4.project(focalLength, size, _panX, _panY);

        // Colour per corner, interpolated across the cell. A single colour
        // from the cell average makes each cell a flat block, which reads as
        // banding however fine the grid — for the light as for the value, so
        // the light is taken at each corner too, from the slope of the
        // sampled surface there.
        final int c1 = shade(quad.v1, quad.l1);
        final int c2 = shade(quad.v2, quad.l2);
        final int c3 = shade(quad.v3, quad.l3);
        final int c4 = shade(quad.v4, quad.l4);

        // Two triangles sharing the p1-p3 diagonal, each carrying its own
        // depth so a cell can be sorted against a grid segment passing under
        // it — or against another surface threading between them.
        final double d1 = (quad.p1.y + quad.p2.y + quad.p3.y) / 3;
        final double d2 = (quad.p1.y + quad.p3.y + quad.p4.y) / 3;
        scene.addTriangle(o1, o2, o3, c1, c2, c3, d1);
        scene.addTriangle(o1, o3, o4, c1, c3, c4, d2);
      }

      _addMeshTo(
        scene,
        built.mesh,
        size,
        focalLength,
        (double v, double light) => meshInkArgb(shade(v, light), 1),
      );
    }

    // Single-variable curves join the same list, so one passing behind a
    // surface is hidden by it. Drawn afterwards on top of a finished scene, a
    // curve floats in front of geometry it runs through — the same fault the
    // floor grid had against the surface.
    _addStandingCurvesTo(scene, size, focalLength);
    _addComplexSurfacesTo(scene, size, focalLength);
    _addParametricSurfaceTo(scene, size, focalLength);
    _addParametricTo(scene, size, focalLength);

    // Tick labels and arrowheads join the same order as the surfaces, so a
    // surface nearer the camera covers the numbers behind it. They were drawn
    // over the finished scene, which showed every number through the shape.
    //
    // Drawn over a surface as well as beside one. They were once suppressed
    // whenever a sheet was present, on the grounds that numerals scattered
    // over a bright surface read as dirt — but that left every surface plot
    // with unlabelled axes and no way to tell what the box spans, which is
    // the worse of the two.
    _addAxisMarksTo(scene, size, focalLength);

    scene.paint(canvas, fog: plotTheme.fog.toARGB32());

    // A colorbar keys one ramp to one set of values, so it can only speak for
    // a lone surface. With several, each has its own ramp and its own range,
    // and a single bar would attach the wrong numbers to all but one of them.
    // A parametric mesh coloured by a value owns the bar: it is the only
    // surface on the axes, and its ramp is the one the numbers belong to.
    final (double, double)? parametric = _parametricValueRange;
    // A solid surface has no ramp, so a bar of numbers beside it would be
    // labelling nothing.
    if (surfaceMode == SurfaceMode.none && parametric == null) {
      // Nothing to key.
    } else if (parametric != null) {
      _drawColorbar3D(canvas, size, parametric.$1, parametric.$2);
    } else if (curves.length == 1) {
      if (soleMin != null && soleMax != null) {
        _drawColorbar3D(canvas, size, soleMin, soleMax);
      }
    } else if (curves.length > 1) {
      // A scale per surface, stacked, each on that surface's own ramp and
      // labelled with its own range — the same treatment two vector fields
      // already get. The legend this replaced showed which ramp was which but
      // never what any of them meant.
      for (int i = 0; i < ranges.length; i++) {
        final (int index, double lo, double hi) = ranges[i];
        _drawColorbar3D(
          canvas,
          size,
          lo,
          hi,
          stops: surfaceRampStops(index, of: curves.length, palette: palette),
          row: i,
        );
      }
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
      final Color Function(double) ramp = surfaceColormap(
        i,
        of: count,
        palette: palette,
      );
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
      Color shade(double v) =>
          plotColormap((v / maxMag).clamp(0.0, 1.0), palette);

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
      Color shade(double v) => plotColormap(
        ((v - minVal) / (maxVal - minVal)).clamp(0.0, 1.0),
        palette,
      );

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
    for (final (double x, bool major) in _gridLinesWithin(rangeX)) {
      _addWorldLineTo(
        scene,
        size,
        focalLength,
        Point3D(x * scaleX, -rangeY * scaleY, 0),
        Point3D(x * scaleX, rangeY * scaleY, 0),
        major ? majorPaint : minorPaint,
      );
    }
    for (final (double y, bool major) in _gridLinesWithin(rangeY)) {
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

    for (final (double x, bool major) in _gridLinesWithin(rangeX)) {
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
    for (final (double y, bool major) in _gridLinesWithin(rangeY)) {
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
      _colorbarZone(size),
  ];

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

  void _paintHaloed(
    Canvas canvas,
    TextPainter fill,
    String text,
    TextStyle style,
    Offset at,
    Color halo,
  ) {
    final TextPainter outline = _laidOut(text, style, halo: halo);
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
        final TextPainter name = _laidOut(label, nameStyle);
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

      final double step = _tickStep(range);
      for (final double t in _ticksWithin(range, step)) {
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
        final TextPainter fill = _laidOut(text, style);
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

  /// Add a height surface for each selected component of a complex line.
  ///
  /// One complex function makes up to three surfaces on the same axes — the
  /// real part, the imaginary part and the modulus — which is why they go
  /// through the depth scene rather than being drawn one after another: with
  /// two of them showing, each has to be able to pass through the other.
  void _addComplexSurfacesTo(_DepthScene scene, Size size, double focalLength) {
    if (!function.isComplex) return;
    final List<({ComplexPart part, int series})> parts = _complexSurfaces;
    if (parts.isEmpty) return;

    for (final ({ComplexPart part, int series}) entry in parts) {
      final bool byValue = surfaceMode != SurfaceMode.none;
      final Color plain = _theme.seriesColor(entry.series);
      final bool byArgument = surfaceMode == SurfaceMode.z;

      // What the colours say: the reading chosen in the surface menu, which
      // need not be the one the height shows. So |f| can be coloured by the
      // real part, and where Re f vanishes shows up on the shape of the
      // modulus — something neither menu says on its own.
      double colourAt(double x, double y) {
        final Complex w = function.evaluateComplex(x, y);
        return switch (surfaceMode) {
          SurfaceMode.x => w.real,
          SurfaceMode.y => w.imag,
          SurfaceMode.magnitude => w.magnitude,
          SurfaceMode.z => w.phase,
          SurfaceMode.none => 0,
        };
      }

      final built = _surfaceQuads(
        function,
        heightAt: (double x, double y) {
          final Complex w = function.evaluateComplex(x, y);
          return switch (entry.part) {
            ComplexPart.real => w.real,
            ComplexPart.imaginary => w.imag,
            ComplexPart.modulus => w.magnitude,
          };
        },
        valueAt: byValue ? colourAt : null,
      );
      if (built.quads.isEmpty) continue;

      // The full colormap, not the per-series ramp the height surfaces use.
      // That ramp runs one hue light to dark, which is how a surface says
      // "I am the second one" — fine when the colour is an identity and
      // useless when it is a measurement. Coloured by |f| it came out as a
      // sheet of blue with no reading in it.
      Color ramp(double t) => plotColormap(t, palette);
      final double span =
          built.maxV > built.minV ? built.maxV - built.minV : 1.0;
      final int plainArgb = plain.toARGB32();

      int shade(double value, double light) {
        if (!byValue || !value.isFinite) {
          return litSurfaceArgb(plainArgb, light);
        }
        // Argument goes on the hue wheel, not a ramp. Phase wraps, and a
        // ramp with different colours at its ends would draw a seam across
        // the surface everywhere it passes pi — the same reason the 2D
        // colouring uses the wheel, and it keeps the two views agreeing. Not
        // lit: the wheel's lightness already says something, the modulus.
        if (byArgument) return domainColor(value, 1).toARGB32();
        return litSurfaceArgb(
          ramp(((value - built.minV) / span).clamp(0.0, 1.0)).toARGB32(),
          light,
          strength: _valueShadeStrength,
        );
      }

      for (final Quad quad in built.quads) {
        final o1 = quad.p1.project(focalLength, size, _panX, _panY);
        final o2 = quad.p2.project(focalLength, size, _panX, _panY);
        final o3 = quad.p3.project(focalLength, size, _panX, _panY);
        final o4 = quad.p4.project(focalLength, size, _panX, _panY);

        final int c1 = shade(quad.v1, quad.l1);
        final int c2 = shade(quad.v2, quad.l2);
        final int c3 = shade(quad.v3, quad.l3);
        final int c4 = shade(quad.v4, quad.l4);

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

      _addMeshTo(
        scene,
        built.mesh,
        size,
        focalLength,
        (double v, double light) => meshInkArgb(shade(v, light), 1),
      );
    }

    // The span the colour ramp was built over is not the height span, so the
    // bar the height surfaces would key is wrong here; suppressed rather than
    // shown with the wrong numbers.
    _parametricValueRange = null;
  }

  /// Add the patch swept out by u and v.
  ///
  /// Normals are averaged at the corners rather than taken per cell, so the
  /// shading runs continuously across the mesh. Flat-shading a cell leaves it
  /// a facet however fine the grid is — the same reason the heatmap colours
  /// its corners and not its gridSize — and a sphere came out looking cut from
  /// gemstone.
  void _addParametricSurfaceTo(
    _DepthScene scene,
    Size size,
    double focalLength,
  ) {
    _parametricValueRange = null;
    final VectorFieldParser? field = vectorParser;
    if (field == null || !field.isParametricSurface) return;

    // One resolution, moving or still. Thinning the mesh under a finger left
    // the surface coarse for as long as a spin carried on, which reads as the
    // plot degrading rather than as a frame rate being protected.
    //
    // Cached so that turning the plot re-projects the same points instead of
    // re-evaluating the expression 4,225 times a frame.
    final List<List<ParametricPoint?>> grid = cachedParametricSurface(
      field,
      u: uRange,
      v: vRange,
    );
    if (grid.length < 2 || grid.first.length < 2) return;
    final int rows = grid.length;
    final int cols = grid.first.length;

    // Every corner rotated once. Each is shared by up to four gridSize, and the
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

    final int baseArgb = _theme.seriesColor(vectorSeriesBase).toARGB32();

    /// How square a corner stands to the key light, 0 edge-on to 1 square on.
    ///
    /// Taken in the box's own space, before the camera turns it, so a sweep
    /// is lit by the same light as every other surface and keeps its lighting
    /// as it is turned. It was lit by how squarely it faced the camera, which
    /// lights whatever you look at straight on and hides the shape there.
    ///
    /// Central differences where both neighbours exist, one-sided at the rim,
    /// so the edge of the sheet is shaded like the rest of it.
    double lightAt(int i, int j) {
      final ParametricPoint? here = pts[i][j] == null ? null : grid[i][j];
      if (here == null) return 1;
      ParametricPoint at(int a, int b) =>
          (a >= 0 && a < rows && b >= 0 && b < cols && pts[a][b] != null)
              ? grid[a][b]!
              : here;
      final ParametricPoint ua = at(i - 1, j);
      final ParametricPoint ub = at(i + 1, j);
      final ParametricPoint va = at(i, j - 1);
      final ParametricPoint vb = at(i, j + 1);

      final double ux = (ub.x - ua.x) * scaleX;
      final double uy = (ub.y - ua.y) * scaleY;
      final double uz = (ub.z - ua.z) * scaleZ;
      final double vx = (vb.x - va.x) * scaleX;
      final double vy = (vb.y - va.y) * scaleY;
      final double vz = (vb.z - va.z) * scaleZ;
      return keyLightOn(
        uy * vz - uz * vy,
        uz * vx - ux * vz,
        ux * vy - uy * vx,
      );
    }

    /// The colour of the sheet where it reads [value] and is lit by [light].
    ///
    /// Solid, the light carries all of the form. Coloured by value it is kept
    /// gentler, so the colour stays near enough the number it stands for to be
    /// read off the colorbar — without any, a sphere coloured by magnitude is
    /// one flat colour and reads as a disc.
    int shadeFor(double value, double light) {
      if (!byValue) return litSurfaceArgb(baseArgb, light);
      return litSurfaceArgb(
        plotColormap(
          ((value - minV) / span).clamp(0.0, 1.0),
          palette,
        ).toARGB32(),
        light,
        strength: _valueShadeStrength,
      );
    }

    // Each vertex is shaded and projected once, not once per cell that
    // touches it. Every interior corner belongs to four gridSize, and doing this
    // work inside the cell loop did all of it four times over — on the two
    // most expensive operations there are here, a normal with its square root
    // and a colour lookup with its pack. Hoisting them is what pays for the
    // grid being fine enough not to show its corners.
    final List<List<Offset?>> screen = <List<Offset?>>[
      for (int i = 0; i < rows; i++)
        <Offset?>[
          for (int j = 0; j < cols; j++)
            pts[i][j]?.project(focalLength, size, _panX, _panY),
        ],
    ];
    final List<List<double>> values = <List<double>>[
      for (int i = 0; i < rows; i++)
        <double>[
          for (int j = 0; j < cols; j++)
            pts[i][j] == null || !byValue ? 0 : valueAt(grid[i][j]!),
        ],
    ];
    final List<List<double>> lights = <List<double>>[
      for (int i = 0; i < rows; i++)
        <double>[for (int j = 0; j < cols; j++) lightAt(i, j)],
    ];
    final List<List<int>> shades = <List<int>>[
      for (int i = 0; i < rows; i++)
        <int>[
          for (int j = 0; j < cols; j++)
            pts[i][j] == null ? 0 : shadeFor(values[i][j], lights[i][j]),
        ],
    ];

    // A sweep is a grid in u and v, so its mesh is those parameter lines —
    // the same idea as a height surface's grid, drawn on the same stride so
    // every kind of surface meshes at one density.
    final List<_GridPiece> mesh = <_GridPiece>[];
    final int meshStride = _meshStrideFor(max(rows, cols));

    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < cols; j++) {
        final Point3D? a = pts[i - 1][j - 1];
        final Point3D? b = pts[i - 1][j];
        final Point3D? c = pts[i][j];
        final Point3D? d = pts[i][j - 1];
        // A cell missing a corner is a hole in the surface, and drawing it
        // would span the gap with a sheet the sweep never covers.
        if (a == null || b == null || c == null || d == null) continue;

        // Two triangles sharing the a-c diagonal, each with its own depth so
        // a cell can sort against a grid segment passing under it.
        scene.addTriangle(
          screen[i - 1][j - 1]!,
          screen[i - 1][j]!,
          screen[i][j]!,
          shades[i - 1][j - 1],
          shades[i - 1][j],
          shades[i][j],
          (a.y + b.y + c.y) / 3,
        );
        scene.addTriangle(
          screen[i - 1][j - 1]!,
          screen[i][j]!,
          screen[i][j - 1]!,
          shades[i - 1][j - 1],
          shades[i][j],
          shades[i][j - 1],
          (a.y + c.y + d.y) / 3,
        );

        if (showMesh) {
          // One segment per line rather than per side, so the cell next door
          // does not draw the same one again.
          if ((i - 1) % meshStride == 0) {
            mesh.add((
              a: a,
              b: b,
              va: values[i - 1][j - 1],
              vb: values[i - 1][j],
              la: lights[i - 1][j - 1],
              lb: lights[i - 1][j],
            ));
          }
          if ((j - 1) % meshStride == 0) {
            mesh.add((
              a: a,
              b: d,
              va: values[i - 1][j - 1],
              vb: values[i][j - 1],
              la: lights[i - 1][j - 1],
              lb: lights[i][j - 1],
            ));
          }
        }
      }
    }

    _addMeshTo(
      scene,
      mesh,
      size,
      focalLength,
      (double v, double light) => meshInkArgb(shadeFor(v, light), 1),
    );
  }

  /// Add the path traced by sweeping u, in the same depth order as everything
  /// else in the scene.
  ///
  /// Unlike a standing curve, a parametric one already knows all three of its
  /// coordinates, so there is no axis to choose and no value to clip against:
  /// the sweep says where the point is, and the window only decides whether it
  /// is visible.
  void _addParametricTo(_DepthScene scene, Size size, double focalLength) {
    // A surface is not also a curve: sweeping u alone would trace one edge of
    // it and draw that line across the mesh.
    final List<VectorFieldParser> sweeps = fieldsToDraw
        .where(
          (VectorFieldParser f) => f.isParametric && !f.isParametricSurface,
        )
        .toList(growable: false);
    for (int n = 0; n < sweeps.length; n++) {
      _addOneParametricTo(scene, size, focalLength, sweeps[n], n);
    }
  }

  void _addOneParametricTo(
    _DepthScene scene,
    Size size,
    double focalLength,
    VectorFieldParser field,
    int nth,
  ) {
    // As in 2D: the sweep takes its place in the cell's colour cycle rather
    // than restarting it, so it does not arrive wearing the first curve's
    // colour.
    final Color curveColor = _theme.seriesColor(vectorSeriesBase + nth);
    final paint =
        Paint()
          ..color = curveColor
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    Offset? prev;
    double? prevDepth;

    for (final ParametricPoint? p in cachedParametricCurve(field, u: uRange)) {
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
    // A complex line is drawn as its component surfaces, not as a curve. Its
    // free variable is z, which every other path reads as the third
    // coordinate — so z̲ was drawn twice, once correctly as a surface and once
    // as a standing line up the z axis.
    if (function.isComplex) return;
    final List<PlotExpression> curves = _lineCurves;
    for (int c = 0; c < curves.length; c++) {
      if (curves[c].hidden) continue;
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

    // Always the palette, never the accent. A lone standing curve used to be
    // the app accent and a palette colour the moment a second line appeared, so
    // adding a plot recoloured the one already there — and no swatch could have
    // matched it.
    final Color curveColor = _theme.seriesColor(parser.seriesIndex);

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
    final double barWidth = _colorbarWidth(size);
    final Rect barRect = Rect.fromLTWH(
      size.width - barWidth - _colorbarMarginRight,
      _colorbarMarginTop + row * _colorbarPitch,
      barWidth,
      _colorbarHeight,
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
    final double step = _niceStep(span, 4);
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
