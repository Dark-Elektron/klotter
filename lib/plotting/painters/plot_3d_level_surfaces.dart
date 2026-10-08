part of 'plot_3d_painter.dart';

/// Level surfaces F(x, y, z) = 0: marched, made into meshes, and drawn.
extension Plot3DLevelSurfaces on Plot3DPainter {
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
    // The floor and axes in the same back-to-front order as the triangles,
    // so the plane cuts through the surface where it should instead of the
    // whole surface being painted over a finished floor. That is what made a
    // sphere sit on top of its own axes.
    final _DepthScene scene = _DepthScene();
    if (withFloor) {
      _addFloorGridTo(scene, size, focalLength);
      _addAxisChromeTo(scene, size, focalLength);
    }
    final int equations = _addLevelSurfacesTo(scene, size, focalLength);
    if (withFloor) _addAxisMarksTo(scene, size, focalLength);
    scene.paint(canvas, fog: plotTheme.fog.toARGB32());
    _drawLevelSurfaceKey(canvas, size, equations);
  }

  /// Put every equation in the cell into [scene], and say how many there were.
  int _addLevelSurfacesTo(_DepthScene scene, Size size, double focalLength) {
    // Hidden equations are dropped before the ramp index is taken, so the ones
    // still showing keep telling themselves apart. Their solid colour comes
    // from the row number, so it does not move when a neighbour is hidden.
    final List<PlotExpression> equations =
        _curves.where((PlotExpression e) => e.isLevelSet && !e.hidden).toList();
    if (equations.isEmpty) return 0;

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
    if (count == 0) return 0;

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

    // Each triangle's colours as they are added: the surface's own, and for
    // a grid line's two triangles, laid out by [_projectMeshLines] as
    // (start, start, end) and (start, end, end), the ink of the end each
    // corner belongs to, so the line shades along its length. The fog and the
    // order are the scene's.
    final Int32List argb = Int32List(total * 3);
    argb.setRange(0, count * 3, meshColors);
    for (int s = 0; s < segments * 2; s++) {
      final int line = s >> 1;
      final int start = meshInks[line * 2];
      final int end = meshInks[line * 2 + 1];
      final int c = (count + s) * 3;
      argb[c] = start;
      argb[c + 1] = s.isEven ? start : end;
      argb[c + 2] = end;
    }
    scene.addTriangles(screen, argb, depth, total, spanning: count);
    return equations.length;
  }

  /// The colour key for [equations] level surfaces drawn.
  ///
  /// A solid surface has no ramp, so a bar of numbers beside it labels
  /// nothing — and the swatches name ramps that are not on screen. Height
  /// surfaces have always held this back; level surfaces drew the bar
  /// regardless, which put a rainbow scale over a plain blue shape.
  void _drawLevelSurfaceKey(Canvas canvas, Size size, int equations) {
    if (equations == 0 || surfaceMode == SurfaceMode.none) return;
    if (equations == 1) {
      _drawColorbar3D(canvas, size, -rangeZ, rangeZ);
    } else {
      _drawSurfaceLegend(canvas, size, equations);
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
        hasMesh(Plot3DPainter._levelResolution, refined: true) ||
        hasMarchedSurface(
          equation,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
          resolution: Plot3DPainter._levelResolution,
        );
    int resolution = Plot3DPainter._levelResolution;
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
          hasMesh(Plot3DPainter._levelPlaceholderResolution, refined: false)) {
        marches.march(
          equation,
          -rangeX,
          rangeX,
          -rangeY,
          rangeY,
          -rangeZ,
          rangeZ,
          resolution: Plot3DPainter._levelResolution,
        );
      }
      resolution = Plot3DPainter._levelPlaceholderResolution;
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
          exact: resolution == Plot3DPainter._levelResolution,
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
}
