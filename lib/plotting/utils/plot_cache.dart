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
  PlotCache(this.capacity);

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
  LevelMesh(this.world, this.colors) : triangleCount = colors.length ~/ 3;

  /// World-space vertices, nine floats per triangle: (x, y, z) x 3.
  /// Already scaled, since scale depends on the window rather than the camera.
  final Float32List world;

  /// One packed ARGB colour per vertex, three per triangle.
  ///
  /// Colour comes from the data height, which the camera does not change, so
  /// it is computed with the geometry rather than every frame.
  final Int32List colors;

  final int triangleCount;
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
  int Function(double dataZ) shade,
  int colouring,
) {
  return _meshCache.resolve(
    plotCacheKey(
      f,
      <double>[...bounds, scaleX, scaleY, scaleZ],
      // The colours are baked into the mesh, so what they were made from is
      // part of its identity.
      resolution * 16 + colouring,
    ),
    () {
      final tris = march();
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
        colors[c] = shade(t.az);
        colors[c + 1] = shade(t.bz);
        colors[c + 2] = shade(t.cz);
      }
      return LevelMesh(world, colors);
    },
  );
}
