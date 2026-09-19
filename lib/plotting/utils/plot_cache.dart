import 'dart:math';
import 'dart:typed_data';

import '../parsers/plot_expression.dart';

/// A small most-recently-used cache.
///
/// Plot geometry depends on the expression, the window and the resolution —
/// never on the camera. Rotating or panning repaints continuously without
/// changing any of those, so recomputing per frame is pure waste. A few
/// entries is enough: a plot has one surface, and keeping the previous window
/// makes a zoom step cheap to undo.
class PlotCache<T> {
  PlotCache(this.capacity) {
    _live.add(this);
  }

  /// Every cache that has been made, so they can all be emptied at once.
  ///
  /// A registry rather than a list written out by hand in
  /// [releasePlotGeometry]: the caches are private top-level finals in two
  /// files already, and the next one added would silently not be released.
  static final List<PlotCache<dynamic>> _live = <PlotCache<dynamic>>[];

  final int capacity;
  final Map<Object, T> _entries = <Object, T>{};

  int get length => _entries.length;

  T resolve(Object key, T Function() compute) {
    final T? hit = _entries[key];
    if (hit != null) {
      // Refresh recency so the entry in active use is not the one evicted.
      _entries.remove(key);
      _entries[key] = hit;
      return hit;
    }
    final T value = compute();
    _entries[key] = value;
    if (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  void clear() => _entries.clear();
}

/// Empty every plot cache, returning how many entries went.
///
/// These caches hold the bulkiest thing the app keeps: a marched surface can
/// be 33,000 triangles, which is a 1.2 MB `Float32List` and a 0.4 MB
/// `Int32List`, and the mesh cache holds eight of them. They are top-level
/// finals, so nothing frees them while the process lives — the plot is still
/// on screen, so no widget has been disposed.
///
/// That matters when the app is backgrounded. Android picks what to kill by
/// how much a process is holding, and an app sitting on tens of megabytes of
/// geometry it is not drawing is an easy choice. Dropping it on the way out
/// costs a resample on return, which the plot does in single-digit
/// milliseconds.
int releasePlotGeometry() {
  int released = 0;
  for (final PlotCache<dynamic> cache in PlotCache._live) {
    released += cache.length;
    cache.clear();
  }
  return released;
}

/// Key for cached plot geometry.
///
/// The expression is compiled once per edit, so its identity is a sound key —
/// a new object means a new expression. Values are the window bounds and the
/// resolution, which is everything else the geometry depends on.
Object plotCacheKey(PlotExpression f, List<double> bounds, int resolution) =>
    Object.hash(identityHashCode(f), Object.hashAll(bounds), resolution);

final PlotCache<List<List<double>>> _heightCache =
    PlotCache<List<List<double>>>(4);

/// Height samples on a `(gridSize + 1)²` lattice over the given ranges.
///
/// Cached because rotating a surface does not change its heights — only where
/// the camera sees them from. Without this a 50x50 surface re-walked the
/// expression tree 2,601 times per frame while the user dragged.
///
/// Non-finite samples are kept as-is rather than dropped, so callers can tell
/// "undefined here" from "outside the z window" and leave a hole for the first
/// without inventing geometry.
List<List<double>> cachedHeightGrid(
  PlotExpression f,
  double rangeX,
  double rangeY,
  int gridSize,
) {
  return _heightCache.resolve(
    plotCacheKey(f, <double>[rangeX, rangeY], gridSize),
    () => <List<double>>[
      for (int i = 0; i <= gridSize; i++)
        <double>[
          for (int j = 0; j <= gridSize; j++)
            () {
              try {
                return f.evaluate(
                  -rangeX + (2 * rangeX * i / gridSize),
                  -rangeY + (2 * rangeY * j / gridSize),
                );
              } catch (_) {
                return double.nan;
              }
            }(),
        ],
    ],
  );
}

/// A marched surface, flattened for drawing.
///
/// Triangles are held as raw floats rather than objects: a hyperboloid marches
/// to 33,000 triangles, and one `Point3D` per rotation step plus an `Offset`
/// per projection plus a `Color` list per triangle came to roughly half a
/// million allocations per frame.
class LevelMesh {
  LevelMesh(this.world, this.colors, this.meshLines)
    : triangleCount = colors.length ~/ 3,
      meshLineCount = meshLines.length ~/ 6;

  /// World-space vertices, nine floats per triangle: (x, y, z) x 3.
  /// Already scaled, since scale depends on the window rather than the camera.
  final Float32List world;

  /// One packed ARGB colour per vertex, three per triangle.
  ///
  /// Colour comes from the data height, which the camera does not change, so
  /// it is computed with the geometry rather than every frame.
  final Int32List colors;

  final int triangleCount;

  /// The surface's grid lines, six floats per segment: (x, y, z) x 2, in the
  /// same view-scaled space as [world].
  ///
  /// Where the grid falls depends on the surface and the window and not on the
  /// camera, so it belongs here with the triangles rather than being rebuilt
  /// while they are projected. It was rebuilt per frame, which meant scanning
  /// every triangle against the slicing planes on all three axes on every
  /// frame of a rotation — on a 38,000 triangle surface, 115,000 span tests a
  /// frame to arrive at the same 19,000 segments as the frame before.
  final Float32List meshLines;

  final int meshLineCount;
}

/// Room for several surfaces at once plus a previous window, since a cell can
/// now hold more than one equation on the same axes.
final PlotCache<LevelMesh> _meshCache = PlotCache<LevelMesh>(8);

/// Flatten marched triangles into a [LevelMesh], cached per window.
LevelMesh cachedLevelMesh(
  PlotExpression f,
  List<double> bounds,
  int resolution,
  List<
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
  >
  Function()
  march,
  double scaleX,
  double scaleY,
  double scaleZ,
  Float32List Function() normals,
  int Function(double dataZ, double light) shade,
  int colouring, {
  List<double>? meshSteps,
}) {
  return _meshCache.resolve(
    plotCacheKey(
      f,
      <double>[...bounds, scaleX, scaleY, scaleZ, ...?meshSteps],
      // The colours are baked into the mesh, so what they were made from is
      // part of its identity. So is whether the grid was built: a mesh made
      // with the grid off has an empty [LevelMesh.meshLines], and handing that
      // back when the grid is switched on would draw no grid at all.
      (resolution * 16 + colouring) * 2 + (meshSteps == null ? 0 : 1),
    ),
    () {
      final tris = march();
      // Asked for only now. Both this and [march] come off the same cached
      // march, and neither runs at all unless this mesh is being rebuilt —
      // which is the point: the mesh cache holds eight surfaces and the march
      // cache three, so a plot with four surfaces on it would otherwise have
      // re-marched every one of them on every frame to fetch normals it
      // already had baked into the colours.
      final Float32List vertexNormals = normals();
      final Float32List world = Float32List(tris.length * 9);
      final Int32List colors = Int32List(tris.length * 3);
      for (int i = 0; i < tris.length; i++) {
        final t = tris[i];
        final int w = i * 9;
        world[w] = t.ax * scaleX;
        world[w + 1] = t.ay * scaleY;
        world[w + 2] = t.az * scaleZ;
        world[w + 3] = t.bx * scaleX;
        world[w + 4] = t.by * scaleY;
        world[w + 5] = t.bz * scaleZ;
        world[w + 6] = t.cx * scaleX;
        world[w + 7] = t.cy * scaleY;
        world[w + 8] = t.cz * scaleZ;

        final int c = i * 3;
        colors[c] = shade(
          t.az,
          _lightOn(vertexNormals, w, scaleX, scaleY, scaleZ),
        );
        colors[c + 1] = shade(
          t.bz,
          _lightOn(vertexNormals, w + 3, scaleX, scaleY, scaleZ),
        );
        colors[c + 2] = shade(
          t.cz,
          _lightOn(vertexNormals, w + 6, scaleX, scaleY, scaleZ),
        );
      }
      return LevelMesh(
        world,
        colors,
        meshSteps == null
            ? _noMeshLines
            : _sliceMeshLines(
              world,
              tris.length,
              meshSteps,
              vertexNormals,
              scaleX,
              scaleY,
              scaleZ,
            ),
      );
    },
  );
}

final Float32List _noMeshLines = Float32List(0);

/// Which way the light comes from, in the view's own space.
///
/// Fixed to the box rather than to the camera, because that is the only kind
/// of light whose effect can be worked out once and kept: the camera moves on
/// every frame of a rotation and the box does not. What the viewer sees is a
/// surface lit from over their left shoulder that keeps its lighting as it is
/// turned, which is how a held object behaves.
final Float64List _lightDirection = () {
  const double x = -0.35, y = -0.62, z = 0.70;
  final double len = sqrt(x * x + y * y + z * z);
  return Float64List.fromList(<double>[x / len, y / len, z / len]);
}();

/// How lit a surface facing away from the light still is.
///
/// Well short of black. The light is two-sided — see [_lightOn] — so what this
/// floor applies to is a band around the surface rather than a whole far side,
/// and the point of the shading is to let the eye read a fold, not to stage a
/// photograph. It also keeps a colour-mapped surface close enough to its
/// colorbar to still be read against it.
const double _ambientLight = 0.55;

/// How much light reaches the vertex whose normal starts at [at].
///
/// Two-sided: the brightness goes on `|n·l|`, not on `n·l`. Marching gives a
/// normal pointing the way f increases, and which side of the surface that is
/// depends on whether the equation was written `f = 0` or `-f = 0` — the same
/// sphere either way. A one-sided light would have lit one of those two and
/// left the other in the dark.
double _lightOn(
  Float32List normals,
  int at,
  double scaleX,
  double scaleY,
  double scaleZ,
) {
  if (at + 2 >= normals.length) return 1;
  // Into view space first. The box is squashed onto the screen by a different
  // factor on z than on x and y, and a direction does not carry over by being
  // multiplied by that — it takes the reciprocals. Skip this and a surface in
  // a tall thin window is lit as though it were in a cubic one.
  final double nx = normals[at] / scaleX;
  final double ny = normals[at + 1] / scaleY;
  final double nz = normals[at + 2] / scaleZ;
  final double len = sqrt(nx * nx + ny * ny + nz * nz);
  if (len == 0 || !len.isFinite) return 1;

  final double lambert =
      ((nx * _lightDirection[0] +
                  ny * _lightDirection[1] +
                  nz * _lightDirection[2]) /
              len)
          .abs();
  return _ambientLight + (1 - _ambientLight) * lambert;
}

/// Which of the three families to leave off this triangle: the one whose axis
/// points most nearly along the surface normal.
///
/// Two families make a grid; three make a thicket. A plane cuts the surface in
/// a contour running along `n × axis`, so three axis-aligned families give
/// three directions in the tangent plane — and wherever the surface faces a
/// diagonal those sit 60° apart rather than 90°, which is not a grid but a
/// triangular weave. Measured on `x⁴+y⁴+z⁴−2(x²+y²+z²)+8xyz+1`, two of the
/// three families crossed at under 40° over 68% of the surface, shallowest 6°.
/// Those shallow crossings are the long lens shapes and the X's.
///
/// The one to lose is the axis nearest the normal, because `n × axis` is
/// shortest there: that family already contributes least, and dropping it
/// leaves the two whose contours are most nearly square to each other. The
/// same measurement then reads 82° at the median and nothing at all under 40°.
///
/// It costs continuity, which is the honest price. The choice is made triangle
/// by triangle from a quantity that varies smoothly, so along the curve where
/// two axes are equally aligned it flips, and a line can stop there. Ends that
/// stop mid-surface go from 0.7% to 5.7% on that surface — 96.8% of segments
/// still join at both ends — and a line that stops reads as far less wrong
/// than a mesh that crosses itself at 6°.
int _weakestAxis(
  Float32List normals,
  int at,
  double scaleX,
  double scaleY,
  double scaleZ,
) {
  if (at + 8 >= normals.length) return -1;
  // The average of the three corners, so that neighbouring triangles across a
  // shared edge tend to agree and the flip stays on one curve instead of
  // speckling. In view space, as the light is: the box is squashed onto the
  // screen by a different factor on z, and the grid is seen after that.
  double nx = 0, ny = 0, nz = 0;
  for (int v = 0; v < 3; v++) {
    nx += normals[at + v * 3];
    ny += normals[at + v * 3 + 1];
    nz += normals[at + v * 3 + 2];
  }
  nx /= scaleX;
  ny /= scaleY;
  nz /= scaleZ;

  final double ax = nx.abs(), ay = ny.abs(), az = nz.abs();
  if (!(ax + ay + az).isFinite) return -1;
  if (ax >= ay && ax >= az) return 0;
  return ay >= az ? 1 : 2;
}

/// Cut the surface with evenly spaced planes on each axis.
///
/// A marched surface has no grid of its own, so its mesh is where it crosses
/// those planes — the lines you would get by slicing it, which is what a mesh
/// on a curved shape means. The triangles' own edges were tried first and were
/// the wrong idea: marching produces irregular triangles, so their edges read
/// as scribble rather than as a grid.
Float32List _sliceMeshLines(
  Float32List world,
  int triangleCount,
  List<double> steps,
  Float32List normals,
  double scaleX,
  double scaleY,
  double scaleZ,
) {
  final List<double> out = <double>[];
  final List<double> hits = <double>[];

  for (int t = 0; t < triangleCount; t++) {
    final int w = t * 9;
    final int skip = _weakestAxis(normals, w, scaleX, scaleY, scaleZ);

    for (int axis = 0; axis < 3; axis++) {
      if (axis == skip) continue;
      final double step = steps[axis];
      if (step <= 0) continue;

      // A triangle lying nearly parallel to this family of planes needs no
      // special case: it has almost no extent along the axis, so the span
      // below puts it between two planes and it contributes nothing.
      final double a0 = world[w + axis];
      final double a1 = world[w + 3 + axis];
      final double a2 = world[w + 6 + axis];
      final double lo = min(a0, min(a1, a2));
      final double hi = max(a0, max(a1, a2));

      for (int k = (lo / step).ceil(); k * step <= hi; k++) {
        final double cut = k * step;
        // Where each edge of the triangle meets the plane. A triangle crossing
        // a plane meets it in exactly two points, which is the piece of the
        // grid line lying on this triangle.
        hits.clear();
        for (int e = 0; e < 3; e++) {
          final int p = w + e * 3;
          final int q = w + ((e + 1) % 3) * 3;
          final double va = world[p + axis];
          final double vb = world[q + axis];
          if ((va < cut && vb < cut) || (va > cut && vb > cut)) continue;
          if (va == vb) continue;
          final double s = (cut - va) / (vb - va);
          for (int comp = 0; comp < 3; comp++) {
            hits.add(world[p + comp] + (world[q + comp] - world[p + comp]) * s);
          }
        }
        if (hits.length < 6) continue;
        // A plane clipping a corner meets the triangle twice in the same
        // place. Between a tenth and a sixth of the cuts come out this way,
        // and every one of them was kept: a segment with no length draws
        // nothing, but it still took a slot in the vertex buffer, an entry in
        // the depth sort and its share of the memory.
        if (hits[0] == hits[3] && hits[1] == hits[4] && hits[2] == hits[5]) {
          continue;
        }
        out.addAll(hits.getRange(0, 6));
      }
    }
  }

  return Float32List.fromList(out);
}
