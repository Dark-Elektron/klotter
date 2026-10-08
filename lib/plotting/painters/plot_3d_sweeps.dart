part of 'plot_3d_painter.dart';

/// What is traced rather than sampled over the box: complex surfaces,
/// parametric curves and surfaces, and single-variable curves standing in it.
extension Plot3DSweeps on Plot3DPainter {
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
    Plot3DPainter._parametricValueRange = null;
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
    Plot3DPainter._parametricValueRange = null;
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
      Plot3DPainter._parametricValueRange = (minV, maxV);
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
    final int meshStride = Plot3DPainter._meshStrideFor(max(rows, cols));

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
}
