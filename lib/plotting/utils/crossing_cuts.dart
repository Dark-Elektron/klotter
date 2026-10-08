import 'dart:math' as math;
import 'dart:typed_data';

/// One surface's triangles, held as a level surface's mesh holds them: nine
/// floats each, the three corners in view-scaled world space, and a packed
/// colour for each corner. [sides] is null until the surface has been cut.
typedef SurfaceTriangles =
    ({Float32List world, Int32List colors, int count, CrossingSides? sides});

/// The pieces a surface was cut into where another surface crosses it: for
/// each, the other surface's plane there, the middle of the crossing, and the
/// side of it the piece lies on.
///
/// Cut, a piece lies to one side of the other surface — but beside the
/// crossing its depth all but ties with the other surface's pieces there, and
/// a sort by depth puts them either way round: hairline slivers all along the
/// crossing. Which side of the other surface faces the camera says which of
/// them is in front, whatever their depths say; the painter orders them by it
/// on every frame.
class CrossingSides {
  CrossingSides(this.pieces, this.planes, this.sides);

  /// The pieces, numbered as their surface numbers its triangles.
  final Int32List pieces;

  /// Seven floats per piece: the other surface's plane (nx, ny, nz, d), the
  /// normal of unit length, and the middle of the crossing (x, y, z).
  final Float32List planes;

  /// The side of the plane each piece lies on, 1 or -1.
  final Int8List sides;

  int get length => sides.length;
}

/// [surfaces], with every triangle that crosses another surface cut along
/// where it crosses.
///
/// The 3D view has no depth buffer. Triangles are painted far to near by the
/// depth of their centres, so where two surfaces cross, a triangle that
/// straddles the crossing is in front on one side of it and behind on the
/// other — and can only be drawn one way. Half of it came out wrong, once for
/// every cell along the crossing: the teeth where a rose's wall went through a
/// spiral's, and where both met a saddle.
///
/// A triangle crossed by another surface is cut once, along the chord the
/// crossing makes through it, so each piece lies to one side and the sort can
/// place it. Cutting it by the plane of every triangle it touched instead
/// turned 2,236 crossed triangles into 14,000 slivers — those planes are all
/// nearly the same plane — and doubled what a frame had to draw.
///
/// Where surfaces cross does not depend on the camera, so this is done once
/// for a set of shapes and kept, never per frame: a frame pays for two or
/// three pieces per crossed triangle, along the crossings only.
///
/// A surface with nothing to cut comes back exactly as given. So does
/// everything when the shapes are too many to sort out in reasonable time
/// (more than [maxEntries] triangle-cell overlaps): drawn uncut, as before.
List<SurfaceTriangles> cutAtCrossings(
  List<SurfaceTriangles> surfaces, {
  int maxEntries = 3000000,
}) {
  final int s = surfaces.length;
  if (s < 2) return surfaces;
  final Int32List start = Int32List(s + 1);
  for (int k = 0; k < s; k++) {
    start[k + 1] = start[k] + surfaces[k].count;
  }
  final int n = start[s];
  if (n == 0) return surfaces;

  // Every triangle numbered across all the surfaces, its corners widened to
  // doubles: cuts are made in this space and rounded back once at the end.
  final Int32List owner = Int32List(n);
  final Float64List p = Float64List(n * 9);
  for (int k = 0; k < s; k++) {
    final Float32List w = surfaces[k].world;
    final int from = start[k];
    owner.fillRange(from, start[k + 1], k);
    for (int i = 0; i < surfaces[k].count * 9; i++) {
      p[from * 9 + i] = w[i];
    }
  }

  // Each triangle's box and plane; the box of everything; how big triangles
  // run. A plane is (nx, ny, nz, d) with the normal of unit length, and NaN
  // for a triangle with no area, which has none to cut by.
  final Float64List box = Float64List(n * 6);
  final Float64List plane = Float64List(n * 4);
  final Uint8List usable = Uint8List(n);
  final Float64List lo = Float64List(3)..fillRange(0, 3, double.infinity);
  final Float64List hi = Float64List(3)
    ..fillRange(0, 3, double.negativeInfinity);
  double sizeSum = 0;
  int sized = 0;
  for (int t = 0; t < n; t++) {
    final int i = t * 9;
    double biggest = 0;
    bool finite = true;
    for (int axis = 0; axis < 3; axis++) {
      final double a = p[i + axis], b = p[i + 3 + axis], c = p[i + 6 + axis];
      final double low = math.min(a, math.min(b, c));
      final double high = math.max(a, math.max(b, c));
      if (!low.isFinite || !high.isFinite) {
        finite = false;
        break;
      }
      box[t * 6 + axis] = low;
      box[t * 6 + 3 + axis] = high;
      biggest = math.max(biggest, high - low);
    }
    if (!finite) continue;
    final double ux = p[i + 3] - p[i], uy = p[i + 4] - p[i + 1];
    final double uz = p[i + 5] - p[i + 2];
    final double vx = p[i + 6] - p[i], vy = p[i + 7] - p[i + 1];
    final double vz = p[i + 8] - p[i + 2];
    final double nx = uy * vz - uz * vy;
    final double ny = uz * vx - ux * vz;
    final double nz = ux * vy - uy * vx;
    final double len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (!(len > 1e-12)) continue;
    plane[t * 4] = nx / len;
    plane[t * 4 + 1] = ny / len;
    plane[t * 4 + 2] = nz / len;
    plane[t * 4 + 3] = -(nx * p[i] + ny * p[i + 1] + nz * p[i + 2]) / len;
    usable[t] = 1;
    for (int axis = 0; axis < 3; axis++) {
      lo[axis] = math.min(lo[axis], box[t * 6 + axis]);
      hi[axis] = math.max(hi[axis], box[t * 6 + 3 + axis]);
    }
    sizeSum += biggest;
    sized++;
  }
  if (sized == 0) return surfaces;
  final double extent = math.max(
    hi[0] - lo[0],
    math.max(hi[1] - lo[1], hi[2] - lo[2]),
  );
  // Closer than this is touching, not crossing: no cut is worth making that
  // thin, and the snapped sign keeps a shared corner from being cut through.
  final double eps = 1e-6 * extent;

  // A grid of cells about twice the size of a triangle, so a triangle covers
  // a few cells and a cell holds a few triangles of each surface.
  final double target = 2 * sizeSum / sized;
  if (!(target > 0)) return surfaces;
  final Int32List dims = Int32List(3);
  final Float64List cellSize = Float64List(3);
  for (int axis = 0; axis < 3; axis++) {
    final double span = hi[axis] - lo[axis];
    dims[axis] =
        span > 0 ? math.max(1, math.min(160, (span / target).ceil())) : 1;
    cellSize[axis] = span > 0 ? span / dims[axis] : 1;
  }
  int cellAt(int axis, double v) =>
      ((v - lo[axis]) / cellSize[axis]).floor().clamp(0, dims[axis] - 1);
  final int cells = dims[0] * dims[1] * dims[2];

  // Which triangles each cell holds, packed: counted, then filled.
  final Int32List cellStart = Int32List(cells + 1);
  int entries = 0;
  for (int t = 0; t < n; t++) {
    if (usable[t] == 0) continue;
    final int i0 = cellAt(0, box[t * 6]), i1 = cellAt(0, box[t * 6 + 3]);
    final int j0 = cellAt(1, box[t * 6 + 1]), j1 = cellAt(1, box[t * 6 + 4]);
    final int k0 = cellAt(2, box[t * 6 + 2]), k1 = cellAt(2, box[t * 6 + 5]);
    for (int k = k0; k <= k1; k++) {
      for (int j = j0; j <= j1; j++) {
        for (int i = i0; i <= i1; i++) {
          cellStart[i + dims[0] * (j + dims[1] * k) + 1]++;
          entries++;
        }
      }
    }
    if (entries > maxEntries) return surfaces;
  }
  for (int c = 0; c < cells; c++) {
    cellStart[c + 1] += cellStart[c];
  }
  final Int32List held = Int32List(entries);
  final Int32List fill = Int32List.fromList(cellStart);
  for (int t = 0; t < n; t++) {
    if (usable[t] == 0) continue;
    final int i0 = cellAt(0, box[t * 6]), i1 = cellAt(0, box[t * 6 + 3]);
    final int j0 = cellAt(1, box[t * 6 + 1]), j1 = cellAt(1, box[t * 6 + 4]);
    final int k0 = cellAt(2, box[t * 6 + 2]), k1 = cellAt(2, box[t * 6 + 5]);
    for (int k = k0; k <= k1; k++) {
      for (int j = j0; j <= j1; j++) {
        for (int i = i0; i <= i1; i++) {
          held[fill[i + dims[0] * (j + dims[1] * k)]++] = t;
        }
      }
    }
  }

  // The pairs that cross and the segment each crossing makes, every pair
  // found once: in the cell holding the low corner of where the two boxes
  // overlap.
  final List<int> pairs = <int>[];
  final List<double> segments = <double>[];
  final Float64List segment = Float64List(6);
  for (int c = 0; c < cells; c++) {
    final int from = cellStart[c], to = cellStart[c + 1];
    if (to - from < 2) continue;
    final int first = owner[held[from]];
    bool mixed = false;
    for (int e = from + 1; e < to && !mixed; e++) {
      mixed = owner[held[e]] != first;
    }
    if (!mixed) continue;
    for (int x = from; x < to; x++) {
      final int a = held[x];
      for (int y = x + 1; y < to; y++) {
        final int b = held[y];
        if (owner[a] == owner[b]) continue;
        final double ox = math.max(box[a * 6], box[b * 6]);
        final double oy = math.max(box[a * 6 + 1], box[b * 6 + 1]);
        final double oz = math.max(box[a * 6 + 2], box[b * 6 + 2]);
        if (ox > math.min(box[a * 6 + 3], box[b * 6 + 3]) ||
            oy > math.min(box[a * 6 + 4], box[b * 6 + 4]) ||
            oz > math.min(box[a * 6 + 5], box[b * 6 + 5])) {
          continue;
        }
        final int home =
            cellAt(0, ox) + dims[0] * (cellAt(1, oy) + dims[1] * cellAt(2, oz));
        if (home != c) continue;
        if (_crossing(p, plane, a, b, eps, segment)) {
          pairs
            ..add(a)
            ..add(b);
          segments.addAll(segment);
        }
      }
    }
  }
  if (pairs.isEmpty) return surfaces;

  // Each triangle's crossings, packed.
  final int crossings = pairs.length ~/ 2;
  final Int32List crossStart = Int32List(n + 1);
  for (final int t in pairs) {
    crossStart[t + 1]++;
  }
  for (int t = 0; t < n; t++) {
    crossStart[t + 1] += crossStart[t];
  }
  final Int32List crossedBy = Int32List(crossings * 2);
  final Int32List crossFill = Int32List.fromList(crossStart);
  for (int x = 0; x < crossings; x++) {
    crossedBy[crossFill[pairs[x * 2]]++] = x;
    crossedBy[crossFill[pairs[x * 2 + 1]]++] = x;
  }

  final List<SurfaceTriangles> out = <SurfaceTriangles>[];
  for (int k = 0; k < s; k++) {
    final SurfaceTriangles surface = surfaces[k];
    final int from = start[k], to = start[k + 1];
    if (crossStart[to] == crossStart[from]) {
      out.add(surface);
      continue;
    }
    final List<double> world = <double>[];
    final List<int> colors = <int>[];
    final List<int> sidePieces = <int>[];
    final List<double> sidePlanes = <double>[];
    final List<int> sideSigns = <int>[];
    for (int t = from; t < to; t++) {
      final int local = t - from;
      if (crossStart[t + 1] == crossStart[t]) {
        for (int i = 0; i < 9; i++) {
          world.add(surface.world[local * 9 + i]);
        }
        colors
          ..add(surface.colors[local * 3])
          ..add(surface.colors[local * 3 + 1])
          ..add(surface.colors[local * 3 + 2]);
        continue;
      }
      List<_Piece> pieces = <_Piece>[
        _Piece(
          Float64List.sublistView(p, t * 9, t * 9 + 9),
          Int32List.fromList(<int>[
            surface.colors[local * 3],
            surface.colors[local * 3 + 1],
            surface.colors[local * 3 + 2],
          ]),
        ),
      ];
      // One cut for each other surface crossing it, along the chord its
      // crossing makes from where it enters the triangle to where it leaves:
      // the two ends of all its segments here that lie farthest apart.
      final List<int> others = <int>[];
      for (int e = crossStart[t]; e < crossStart[t + 1]; e++) {
        final int x = crossedBy[e];
        final int other =
            owner[pairs[x * 2] == t ? pairs[x * 2 + 1] : pairs[x * 2]];
        if (!others.contains(other)) others.add(other);
      }
      // The first surface crossing it, as the pieces will be ordered against:
      // its plane here, the mean of the planes of the triangles of it that
      // cross this one, through the middle of the crossing.
      _Plane? against;
      double againstX = 0, againstY = 0, againstZ = 0;
      for (final int other in others) {
        final List<int> ends = <int>[];
        for (int e = crossStart[t]; e < crossStart[t + 1]; e++) {
          final int x = crossedBy[e];
          final int partner =
              pairs[x * 2] == t ? pairs[x * 2 + 1] : pairs[x * 2];
          if (owner[partner] != other) continue;
          ends
            ..add(x * 6)
            ..add(x * 6 + 3);
        }
        int bestA = ends.first, bestB = ends.first;
        double farthest = -1;
        for (int u = 0; u < ends.length; u++) {
          for (int v = u + 1; v < ends.length; v++) {
            final double dx = segments[ends[u]] - segments[ends[v]];
            final double dy = segments[ends[u] + 1] - segments[ends[v] + 1];
            final double dz = segments[ends[u] + 2] - segments[ends[v] + 2];
            final double d2 = dx * dx + dy * dy + dz * dz;
            if (d2 > farthest) {
              farthest = d2;
              bestA = ends[u];
              bestB = ends[v];
            }
          }
        }
        if (!(farthest > eps * eps)) continue;
        // A plane through the chord, square to the triangle: it meets the
        // triangle along the chord and nowhere else.
        final double cx = segments[bestB] - segments[bestA];
        final double cy = segments[bestB + 1] - segments[bestA + 1];
        final double cz = segments[bestB + 2] - segments[bestA + 2];
        final double tx = plane[t * 4], ty = plane[t * 4 + 1];
        final double tz = plane[t * 4 + 2];
        double mx = ty * cz - tz * cy;
        double my = tz * cx - tx * cz;
        double mz = tx * cy - ty * cx;
        final double len = math.sqrt(mx * mx + my * my + mz * mz);
        if (!(len > 1e-12)) continue;
        mx /= len;
        my /= len;
        mz /= len;
        final _Plane cut = _Plane(
          mx,
          my,
          mz,
          -(mx * segments[bestA] +
              my * segments[bestA + 1] +
              mz * segments[bestA + 2]),
        );
        final List<_Piece> next = <_Piece>[];
        for (final _Piece piece in pieces) {
          piece.cutBy(cut, eps, next);
        }
        pieces = next;

        if (against == null) {
          double nx = 0, ny = 0, nz = 0;
          double fx = 0, fy = 0, fz = 0;
          for (int e = crossStart[t]; e < crossStart[t + 1]; e++) {
            final int x = crossedBy[e];
            final int partner =
                pairs[x * 2] == t ? pairs[x * 2 + 1] : pairs[x * 2];
            if (owner[partner] != other) continue;
            double px = plane[partner * 4], py = plane[partner * 4 + 1];
            double pz = plane[partner * 4 + 2];
            if (fx == 0 && fy == 0 && fz == 0) {
              fx = px;
              fy = py;
              fz = pz;
            } else if (px * fx + py * fy + pz * fz < 0) {
              // A surface's triangles need not all face one way.
              px = -px;
              py = -py;
              pz = -pz;
            }
            nx += px;
            ny += py;
            nz += pz;
          }
          final double length = math.sqrt(nx * nx + ny * ny + nz * nz);
          if (length > 1e-12) {
            againstX = (segments[bestA] + segments[bestB]) / 2;
            againstY = (segments[bestA + 1] + segments[bestB + 1]) / 2;
            againstZ = (segments[bestA + 2] + segments[bestB + 2]) / 2;
            against = _Plane(
              nx / length,
              ny / length,
              nz / length,
              -(nx * againstX + ny * againstY + nz * againstZ) / length,
            );
          }
        }
      }
      for (final _Piece piece in pieces) {
        final _Plane? side = against;
        if (side != null) {
          final double at =
              (side.at(piece.v, 0) +
                  side.at(piece.v, 3) +
                  side.at(piece.v, 6)) /
              3;
          if (at.abs() > eps) {
            sidePieces.add(colors.length ~/ 3);
            sidePlanes.addAll(<double>[
              side.nx,
              side.ny,
              side.nz,
              side.d,
              againstX,
              againstY,
              againstZ,
            ]);
            sideSigns.add(at > 0 ? 1 : -1);
          }
        }
        for (int i = 0; i < 9; i++) {
          world.add(piece.v[i]);
        }
        colors
          ..add(piece.c[0])
          ..add(piece.c[1])
          ..add(piece.c[2]);
      }
    }
    out.add((
      world: Float32List.fromList(world),
      colors: Int32List.fromList(colors),
      count: colors.length ~/ 3,
      sides: CrossingSides(
        Int32List.fromList(sidePieces),
        Float32List.fromList(sidePlanes),
        Int8List.fromList(sideSigns),
      ),
    ));
  }
  return out;
}

/// Where triangles [a] and [b] cross, written into [segment] as its two ends,
/// or false when they do not.
///
/// Each has to reach both sides of the other's plane, and the spans the two
/// cut along the line the planes share have to overlap: Möller's test,
/// without its coplanar case — two surfaces lying in one plane have nothing
/// to cut — and carried on to the points where the crossing starts and stops.
bool _crossing(
  Float64List p,
  Float64List plane,
  int a,
  int b,
  double eps,
  Float64List segment,
) {
  final int qa = a * 4, qb = b * 4, ia = a * 9, ib = b * 9;
  double distance(int q, int i) =>
      plane[q] * p[i] +
      plane[q + 1] * p[i + 1] +
      plane[q + 2] * p[i + 2] +
      plane[q + 3];
  double snap(double d) => d.abs() < eps ? 0 : d;
  bool oneSide(double d0, double d1, double d2) =>
      (d0 > 0 && d1 > 0 && d2 > 0) || (d0 < 0 && d1 < 0 && d2 < 0);

  final double da0 = snap(distance(qb, ia));
  final double da1 = snap(distance(qb, ia + 3));
  final double da2 = snap(distance(qb, ia + 6));
  if (oneSide(da0, da1, da2)) return false;
  if (da0 == 0 && da1 == 0 && da2 == 0) return false;
  final double db0 = snap(distance(qa, ib));
  final double db1 = snap(distance(qa, ib + 3));
  final double db2 = snap(distance(qa, ib + 6));
  if (oneSide(db0, db1, db2)) return false;

  // The line the two planes share; places on it are told apart by how far
  // along it they lie.
  final double lx =
      plane[qa + 1] * plane[qb + 2] - plane[qa + 2] * plane[qb + 1];
  final double ly = plane[qa + 2] * plane[qb] - plane[qa] * plane[qb + 2];
  final double lz = plane[qa] * plane[qb + 1] - plane[qa + 1] * plane[qb];
  final _Reach? ra = _Reach.of(p, ia, da0, da1, da2, lx, ly, lz);
  final _Reach? rb = _Reach.of(p, ib, db0, db1, db2, lx, ly, lz);
  if (ra == null || rb == null) return false;
  // The later start and the earlier finish.
  final _Reach first = ra.lowAt >= rb.lowAt ? ra : rb;
  final _Reach last = ra.highAt <= rb.highAt ? ra : rb;
  if (!(first.lowAt + eps < last.highAt)) return false;
  segment[0] = first.low[0];
  segment[1] = first.low[1];
  segment[2] = first.low[2];
  segment[3] = last.high[0];
  segment[4] = last.high[1];
  segment[5] = last.high[2];
  return true;
}

/// Where a triangle meets another's plane: the two places, ordered along the
/// line the planes share, between which it lies on that plane.
class _Reach {
  _Reach(this.low, this.lowAt, this.high, this.highAt);

  final List<double> low, high;
  final double lowAt, highAt;

  /// From the triangle's corners at [p] [i] and their distances from the
  /// plane; null when it does not reach it.
  static _Reach? of(
    Float64List p,
    int i,
    double d0,
    double d1,
    double d2,
    double lx,
    double ly,
    double lz,
  ) {
    List<double>? low, high;
    double lowAt = double.infinity, highAt = double.negativeInfinity;
    void take(double x, double y, double z) {
      final double at = x * lx + y * ly + z * lz;
      if (at < lowAt) {
        lowAt = at;
        low = <double>[x, y, z];
      }
      if (at > highAt) {
        highAt = at;
        high = <double>[x, y, z];
      }
    }

    final List<double> d = <double>[d0, d1, d2];
    for (int k = 0; k < 3; k++) {
      final int m = (k + 1) % 3;
      final double dk = d[k], dm = d[m];
      if (dk == 0) {
        take(p[i + k * 3], p[i + k * 3 + 1], p[i + k * 3 + 2]);
      }
      if ((dk > 0 && dm < 0) || (dk < 0 && dm > 0)) {
        final double t = dk / (dk - dm);
        take(
          p[i + k * 3] + (p[i + m * 3] - p[i + k * 3]) * t,
          p[i + k * 3 + 1] + (p[i + m * 3 + 1] - p[i + k * 3 + 1]) * t,
          p[i + k * 3 + 2] + (p[i + m * 3 + 2] - p[i + k * 3 + 2]) * t,
        );
      }
    }
    if (low == null || high == null) return null;
    return _Reach(low!, lowAt, high!, highAt);
  }
}

/// A plane to cut by, the normal of unit length.
class _Plane {
  _Plane(this.nx, this.ny, this.nz, this.d);

  final double nx, ny, nz, d;

  /// Signed distance of the point at [p] [i].
  double at(Float64List p, int i) =>
      nx * p[i] + ny * p[i + 1] + nz * p[i + 2] + d;
}

/// A piece of a triangle being cut: its corners and their colours.
class _Piece {
  _Piece(this.v, this.c);

  final Float64List v;
  final Int32List c;

  /// This piece, cut by [plane] into [out]: itself when it lies to one side,
  /// otherwise two or three triangles that each do.
  void cutBy(_Plane plane, double eps, List<_Piece> out) {
    double snap(double d) => d.abs() < eps ? 0 : d;
    final List<double> s = <double>[
      snap(plane.at(v, 0)),
      snap(plane.at(v, 3)),
      snap(plane.at(v, 6)),
    ];
    final bool above = s[0] > 0 || s[1] > 0 || s[2] > 0;
    final bool below = s[0] < 0 || s[1] < 0 || s[2] < 0;
    if (!(above && below)) {
      out.add(this);
      return;
    }
    // The corner on its own: on the plane, or alone on its side. The other
    // two follow it in order, so the winding is kept.
    final int a;
    if (s[0] == 0 || s[1] == 0 || s[2] == 0) {
      a = s[0] == 0 ? 0 : (s[1] == 0 ? 1 : 2);
    } else {
      a = (s[0] > 0) == (s[1] > 0) ? 2 : ((s[0] > 0) == (s[2] > 0) ? 1 : 0);
    }
    final int b = (a + 1) % 3, c = (a + 2) % 3;
    if (s[a] == 0) {
      // On the plane: the opposite edge is cut, in two.
      final _Corner x = _between(b, c, s[b] / (s[b] - s[c]));
      out
        ..add(_from(_corner(a), _corner(b), x))
        ..add(_from(_corner(a), x, _corner(c)));
      return;
    }
    final _Corner ab = _between(a, b, s[a] / (s[a] - s[b]));
    final _Corner ac = _between(a, c, s[a] / (s[a] - s[c]));
    out
      ..add(_from(_corner(a), ab, ac))
      ..add(_from(ab, _corner(b), _corner(c)))
      ..add(_from(ab, _corner(c), ac));
  }

  _Corner _corner(int k) => (
    x: v[k * 3],
    y: v[k * 3 + 1],
    z: v[k * 3 + 2],
    argb: c[k],
  );

  _Corner _between(int from, int to, double t) => (
    x: v[from * 3] + (v[to * 3] - v[from * 3]) * t,
    y: v[from * 3 + 1] + (v[to * 3 + 1] - v[from * 3 + 1]) * t,
    z: v[from * 3 + 2] + (v[to * 3 + 2] - v[from * 3 + 2]) * t,
    argb: _blend(c[from], c[to], t),
  );

  static _Piece _from(_Corner a, _Corner b, _Corner c) => _Piece(
    Float64List.fromList(<double>[a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]),
    Int32List.fromList(<int>[a.argb, b.argb, c.argb]),
  );
}

typedef _Corner = ({double x, double y, double z, int argb});

/// Two packed colours mixed, [t] of the way from [a] to [b], channel by
/// channel: a new corner on an edge takes the colour the edge has there.
int _blend(int a, int b, double t) {
  int channel(int shift) {
    final int x = (a >> shift) & 0xFF, y = (b >> shift) & 0xFF;
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return (channel(24) << 24) |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}
