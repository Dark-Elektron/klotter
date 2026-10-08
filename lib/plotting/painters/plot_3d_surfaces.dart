part of 'plot_3d_painter.dart';

/// Height surfaces z = f(x, y): their quads and mesh lines, the legend that
/// names them, and the surfaces a vector field is drawn as.
extension Plot3DSurfaces on Plot3DPainter {
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
    final double bias = _viewExtentXY * Plot3DPainter._meshDepthBias;
    final double half = Plot3DPainter._meshStrokeWidth / 2;
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
        spansFog: false,
      );
      scene.addTriangle(
        start + side,
        end - side,
        end + side,
        ca,
        cb,
        cb,
        depth,
        spansFog: false,
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
    return extent <= 0 ? 0 : 2 * extent / Plot3DPainter._levelMeshLinesAcross;
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
    final double bias = _viewExtentXY * Plot3DPainter._levelMeshDepthBias;
    final double half = Plot3DPainter._meshStrokeWidth / 2;

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

  /// Cells on a side for one of [surfaces] sharing the axes.
  ///
  /// The budget is the whole scene, not one surface. Every surface used to get
  /// the full grid, so two surfaces did twice the clipping, rotating,
  /// projecting and depth-sorting and a drag frame went from 11 ms to 22 ms.
  /// Dividing by the square root keeps the total number of cells roughly
  /// fixed however many surfaces share the axes — the same reasoning as the
  /// parametric sampler's cell budget.
  int _surfaceCells(int surfaces, {bool? moving}) {
    final int base =
        (moving ?? interacting)
            ? Plot3DPainter._surfaceGridMoving
            : Plot3DPainter._surfaceGridStill;
    return surfaces <= 1 ? base : max(16, (base / sqrt(surfaces)).round());
  }

  /// [rotated] false leaves the corners in world space, for a mesh that is
  /// made once and projected on every frame (see [_sheetMeshFor]).
  ({List<Quad> quads, double minV, double maxV, List<_GridPiece> mesh})
  _surfaceQuads(
    PlotExpression parser, {
    int? gridSize,
    double Function(double x, double y)? heightAt,
    int surfaces = 1,
    double Function(double x, double y)? valueAt,
    bool rotated = true,
  }) {
    final int cells = gridSize ?? _surfaceCells(surfaces);
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
    Point3D world(({double x, double y, double z, double v, double l}) c) {
      final Point3D at = Point3D(c.x * scaleX, c.y * scaleY, c.z * scaleZ);
      return rotated ? at.rotateZ(rotationZ).rotateX(rotationX) : at;
    }

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
    final int meshStride = Plot3DPainter._meshStrideFor(cells);

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

  /// [curve] as a mesh to project, made once for its window, its resolution
  /// and its colouring (see [_SheetMesh]).
  ///
  /// [index] of [of] picks its ramp from the palette.
  _SheetMesh _sheetMeshFor(PlotExpression curve, int index, int of) {
    // Off means one colour, not one ramp. The menu had offered this all along
    // and the painter ignored it, so a surface was always coloured by its own
    // height — which the shape already shows.
    final bool solid = surfaceMode == SurfaceMode.none;
    // The series palette, always — including for a lone surface. Falling back
    // to the accent when there was only one meant a surface was yellow on its
    // own and blue the moment a second was added, so adding a plot recoloured
    // the one already there.
    final int plainArgb = _theme.seriesColor(curve.seriesIndex).toARGB32();
    Object keyAt(int cells) => PlotCacheKey(curve, <num>[
      rangeX,
      rangeY,
      rangeZ,
      cells,
      scaleX,
      scaleY,
      scaleZ,
      showMesh ? 1 : 0,
      surfaceMode.index,
      palette.index,
      plainArgb,
      index,
      of,
    ]);
    final int cells = _surfaceCells(of);
    return _sheetCache.resolve(
      keyAt(cells),
      () {
        final built = _surfaceQuads(curve, gridSize: cells, rotated: false);
        // Each surface is coloured against its own range. Sharing one range
        // across all of them would flatten a shallow surface to a single
        // colour whenever a steeper one is on the same axes.
        final Color Function(double) ramp = surfaceColormap(
          index,
          of: of,
          palette: palette,
        );
        final double span = built.maxV - built.minV;

        // A corner's colour under the key light, the same light a level
        // surface is lit by. Solid used to be shaded by how squarely each
        // cell faced the camera, which lights whatever you look at straight
        // on and so hides the shape exactly where you are looking at it;
        // coloured by value it was not lit at all. Per corner, interpolated
        // across the cell: one colour from the cell average makes each cell a
        // flat block, which reads as banding however fine the grid.
        int shade(double v, double light) =>
            solid
                ? litSurfaceArgb(plainArgb, light)
                : litSurfaceArgb(
                  ramp(((v - built.minV) / span).clamp(0.0, 1.0)).toARGB32(),
                  light,
                  strength: _valueShadeStrength,
                );

        // Each quad here is one triangle of a cell's fan: p4 repeats p3.
        final List<Quad> quads = built.quads;
        final Float32List world = Float32List(quads.length * 9);
        final Int32List colors = Int32List(quads.length * 3);
        for (int t = 0; t < quads.length; t++) {
          final Quad q = quads[t];
          final int w = t * 9;
          world[w] = q.p1.x;
          world[w + 1] = q.p1.y;
          world[w + 2] = q.p1.z;
          world[w + 3] = q.p2.x;
          world[w + 4] = q.p2.y;
          world[w + 5] = q.p2.z;
          world[w + 6] = q.p3.x;
          world[w + 7] = q.p3.y;
          world[w + 8] = q.p3.z;
          colors[t * 3] = shade(q.v1, q.l1);
          colors[t * 3 + 1] = shade(q.v2, q.l2);
          colors[t * 3 + 2] = shade(q.v3, q.l3);
        }
        final List<_GridPiece> mesh = built.mesh;
        final Float32List lines = Float32List(mesh.length * 6);
        final Int32List inks = Int32List(mesh.length * 2);
        for (int g = 0; g < mesh.length; g++) {
          final _GridPiece piece = mesh[g];
          lines[g * 6] = piece.a.x;
          lines[g * 6 + 1] = piece.a.y;
          lines[g * 6 + 2] = piece.a.z;
          lines[g * 6 + 3] = piece.b.x;
          lines[g * 6 + 4] = piece.b.y;
          lines[g * 6 + 5] = piece.b.z;
          inks[g * 2] = meshInkArgb(shade(piece.va, piece.la), 1);
          inks[g * 2 + 1] = meshInkArgb(shade(piece.vb, piece.lb), 1);
        }
        return _SheetMesh(world, colors, lines, inks, built.minV, built.maxV);
      },
    );
  }

  /// Rotate and project [count] triangles of [world] into [screen], six
  /// floats each, and the depth of each one's centre into [depth], from
  /// triangle [at] on.
  ///
  /// Azimuth first, then elevation — a turntable: spinning after the tilt
  /// would turn the model about an axis that is no longer screen-vertical,
  /// which reads as tumbling rather than rotating. Four scalars a frame
  /// rather than a cos/sin pair per vertex.
  void _projectTriangles(
    Float32List world,
    int count,
    Float32List screen,
    Float64List depth,
    int at,
    Size size,
    double focalLength,
  ) {
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    final double halfW = size.width / 2, halfH = size.height / 2;
    for (int t = 0; t < count; t++) {
      final int w = t * 9, o = (at + t) * 6;
      double depthSum = 0;
      for (int v = 0; v < 3; v++) {
        final double x = world[w + v * 3];
        final double y = world[w + v * 3 + 1];
        final double z = world[w + v * 3 + 2];
        final double x1 = x * cz - y * sz;
        final double y1 = x * sz + y * cz;
        final double y2 = y1 * cx - z * sx;
        final double z2 = y1 * sx + z * cx;
        final double scale = focalLength / (focalLength + y2);
        screen[o + v * 2] = halfW + x1 * scale + _panX;
        screen[o + v * 2 + 1] = halfH - z2 * scale + _panY;
        depthSum += y2;
      }
      depth[at + t] = depthSum / 3;
    }
  }

  /// [parts] cut where they cross one another, as [shapes] were last cut, or
  /// cut now (see [cutAtCrossings]).
  ///
  /// A turn of the camera keeps the box, and its coarser surfaces are cut
  /// once, on the first frame of the turn, and kept. A pinch changes the box
  /// on every frame, so shapes made for one frame are gone by the next and
  /// so would any cut be: they are drawn uncut until the hand comes off.
  List<SurfaceTriangles> _cutsFor(
    List<Object> shapes,
    List<SurfaceTriangles> parts,
  ) {
    if (parts.length < 2) return parts;
    final _CutsKey key = _CutsKey(shapes);
    final List<double> box = <double>[
      rangeX,
      rangeY,
      rangeZ,
      scaleX,
      scaleY,
      scaleZ,
    ];
    if (!interacting) {
      _stillBox = box;
    } else if (!_cutCache.contains(key) && !listEquals(box, _stillBox)) {
      return parts;
    }
    return _cutCache.resolve(key, () => cutAtCrossings(parts));
  }

  /// [count] world-space triangles of [world], coloured by [colors], put on
  /// the screen and into [scene].
  void _addTrianglesTo(
    _DepthScene scene,
    Float32List world,
    Int32List colors,
    int count,
    Size size,
    double focalLength, {
    CrossingSides? sides,
  }) {
    if (count == 0) return;
    final Float32List screen = Float32List(count * 6);
    final Float64List depth = Float64List(count);
    _projectTriangles(world, count, screen, depth, 0, size, focalLength);
    if (sides != null) _orderAtCrossings(sides, depth, 0, focalLength);
    scene.addTriangles(screen, colors, depth, count, spanning: count);
  }

  /// Order the pieces cut at crossings by which side of the other surface
  /// faces the camera (see [CrossingSides]): a piece on the camera's side is
  /// in front of the other surface there, one on the far side behind it.
  ///
  /// Each is held to the depth of the middle of its crossing, just in front
  /// or just behind — by more than the sort's buckets are wide, or within one
  /// the order added would decide instead. [depth] holds the surface's
  /// triangles from [at] on.
  void _orderAtCrossings(
    CrossingSides sides,
    Float64List depth,
    int at,
    double focalLength,
  ) {
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    // The eye in world space: undo the turntable on (0, -f, 0).
    final double ex = -focalLength * cx * sz;
    final double ey = -focalLength * cx * cz;
    final double ez = focalLength * sx;
    final double nudge = _viewExtentXY * 2e-3;
    final Float32List planes = sides.planes;
    for (int e = 0; e < sides.length; e++) {
      final int o = e * 7;
      final double facing =
          planes[o] * ex +
          planes[o + 1] * ey +
          planes[o + 2] * ez +
          planes[o + 3];
      if (facing == 0) continue;
      final bool front = (facing > 0) == (sides.sides[e] > 0);
      final double y1 = planes[o + 4] * sz + planes[o + 5] * cz;
      final double crossing = y1 * cx - planes[o + 6] * sx;
      final int t = at + sides.pieces[e];
      depth[t] =
          front
              ? min(depth[t], crossing - nudge)
              : max(depth[t], crossing + nudge);
    }
  }

  /// A height surface's grid, as thin quads that go into the batch with the
  /// cells (see [_addMeshTo], which this is for a [_SheetMesh]'s packed
  /// lines).
  void _addSheetLinesTo(
    _DepthScene scene,
    _SheetMesh sheet,
    Size size,
    double focalLength,
  ) {
    if (!showMesh || sheet.lineCount == 0) return;
    final double bias = _viewExtentXY * Plot3DPainter._meshDepthBias;
    final double half = Plot3DPainter._meshStrokeWidth / 2;
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    final double halfW = size.width / 2, halfH = size.height / 2;
    final Float32List lines = sheet.lines;
    for (int g = 0; g < sheet.lineCount; g++) {
      double ax = 0, ay = 0, da = 0, bx = 0, by = 0, db = 0;
      for (int end = 0; end < 2; end++) {
        final double x = lines[g * 6 + end * 3];
        final double y = lines[g * 6 + end * 3 + 1];
        final double z = lines[g * 6 + end * 3 + 2];
        final double x1 = x * cz - y * sz;
        final double y1 = x * sz + y * cz;
        final double y2 = y1 * cx - z * sx;
        final double z2 = y1 * sx + z * cx;
        final double scale = focalLength / (focalLength + y2);
        final double px = halfW + x1 * scale + _panX;
        final double py = halfH - z2 * scale + _panY;
        if (end == 0) {
          ax = px;
          ay = py;
          da = y2;
        } else {
          bx = px;
          by = py;
          db = y2;
        }
      }
      final double dx = bx - ax, dy = by - ay;
      final double len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      // Along the segment and across it, half a stroke each.
      final double ux = dx / len * half, uy = dy / len * half;
      final double sx0 = ax - ux, sy0 = ay - uy;
      final double fx = bx + ux, fy = by + uy;
      final int ca = sheet.inks[g * 2], cb = sheet.inks[g * 2 + 1];
      final double depth = (da + db) / 2 - bias;
      scene.addTriangleAt(
        sx0 - uy,
        sy0 + ux,
        sx0 + uy,
        sy0 - ux,
        fx + uy,
        fy - ux,
        ca,
        ca,
        cb,
        depth,
        spansFog: false,
      );
      scene.addTriangleAt(
        sx0 - uy,
        sy0 + ux,
        fx + uy,
        fy - ux,
        fx - uy,
        fy + ux,
        ca,
        cb,
        cb,
        depth,
        spansFog: false,
      );
    }
  }

  /// Draw every z = f(x, y) in the cell on one set of axes, and with
  /// [withLevelSurfaces] every equation too.
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
  void _drawHeightSurfaces(
    Canvas canvas,
    Size size,
    double focalLength, {
    bool withLevelSurfaces = false,
  }) {
    final List<PlotExpression> curves = _sheetCurves;
    if (curves.isEmpty &&
        _lineCurves.isEmpty &&
        !_isParametric &&
        !function.isComplex &&
        !withLevelSurfaces) {
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

    final List<_SheetMesh> sheets = <_SheetMesh>[];
    for (int c = 0; c < curves.length; c++) {
      if (curves[c].hidden) continue;
      final _SheetMesh sheet = _sheetMeshFor(curves[c], c, curves.length);
      if (sheet.count == 0) continue;
      if (curves.length == 1) {
        soleMin = sheet.minV;
        soleMax = sheet.maxV;
      }
      // Every surface's own span, so each ramp can be given a scale rather
      // than a swatch. A swatch says which surface a colour belongs to; it
      // does not say what the colour means, which is the whole point of
      // colouring by value.
      ranges.add((c, sheet.minV, sheet.maxV));
      sheets.add(sheet);
    }
    // Equations join the scene too: a level surface sorted on its own and
    // painted first was covered by every height surface, wherever the two
    // were. And all of them are cut where they cross, so the sort can place
    // both sides of a crossing (see [cutAtCrossings]).
    final List<LevelMesh> levels =
        withLevelSurfaces ? _levelMeshesOnShow() : const <LevelMesh>[];
    final List<SurfaceTriangles> cut = _cutsFor(
      <Object>[...sheets, ...levels],
      <SurfaceTriangles>[
        for (final _SheetMesh m in sheets)
          (world: m.world, colors: m.colors, count: m.count, sides: null),
        for (final LevelMesh m in levels)
          (
            world: m.world,
            colors: m.colors,
            count: m.triangleCount,
            sides: null,
          ),
      ],
    );
    for (int i = 0; i < sheets.length; i++) {
      // Each triangle carries its own depth, so a cell can be sorted against
      // a grid segment passing under it — or against another surface
      // threading between them.
      _addTrianglesTo(
        scene,
        cut[i].world,
        cut[i].colors,
        cut[i].count,
        size,
        focalLength,
        sides: cut[i].sides,
      );
      _addSheetLinesTo(scene, sheets[i], size, focalLength);
    }

    // Single-variable curves join the same list, so one passing behind a
    // surface is hidden by it. Drawn afterwards on top of a finished scene, a
    // curve floats in front of geometry it runs through — the same fault the
    // floor grid had against the surface.
    _addStandingCurvesTo(scene, size, focalLength);
    _addComplexSurfacesTo(scene, size, focalLength);
    _addParametricSurfaceTo(scene, size, focalLength);
    _addParametricTo(scene, size, focalLength);
    final int equations =
        levels.isNotEmpty &&
                _addLevelMeshesTo(
                  scene,
                  size,
                  focalLength,
                  levels,
                  cut.sublist(sheets.length),
                )
            ? levels.length
            : 0;

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

    // The equations' key first, as when they were drawn first; a height
    // surface's bar, where there is one, goes over it.
    _drawLevelSurfaceKey(canvas, size, equations);

    // A colorbar keys one ramp to one set of values, so it can only speak for
    // a lone surface. With several, each has its own ramp and its own range,
    // and a single bar would attach the wrong numbers to all but one of them.
    // A parametric mesh coloured by a value owns the bar: it is the only
    // surface on the axes, and its ramp is the one the numbers belong to.
    final (double, double)? parametric = Plot3DPainter._parametricValueRange;
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
}
