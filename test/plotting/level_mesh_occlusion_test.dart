import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_cache.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A level surface's grid belongs to the surface, so the surface has to hide it.
///
/// The grid used to be merged in after the triangles as `drawLine` calls
/// batched into twenty-four depth slabs, every line in a slab drawn at the
/// depth of the first. On a marched surface that is five hundred to eight
/// hundred segments spanning most of the box at one depth, so the grid on the
/// far side was painted over the near side and the surface came out covered in
/// scribble. The grid is geometry in the same buffer now, sorted segment by
/// segment.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int side = 300;

  // Compiled once: the marched mesh is cached against the expression's
  // identity, so a fresh compile per frame re-marches instead of reusing.
  final Map<String, PlotExpression> compiled = <String, PlotExpression>{};
  PlotExpression of(String src, int series) => compiled.putIfAbsent(
    '$src#$series',
    () =>
        PlotExpression.compile(<MathNode>[LiteralNode(text: src)])
          ..seriesIndex = series,
  );

  Future<ByteData> render(
    List<PlotExpression> equations,
    double rotationZ,
  ) async {
    final painter = Plot3DPainter(
      function: equations.first,
      functions: equations,
      showMesh: true,
      is3DFunction: false,
      rotationX: 0,
      rotationZ: rotationZ,
      rangeX: 4,
      rangeY: 4,
      rangeZ: 4,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(300, 300));
    final ui.Image image = await recorder.endRecording().toImage(side, side);
    return (await image.toByteData())!;
  }

  /// Grid pixels in the middle of the canvas, away from the colorbar and the
  /// legend. The grid is the only near-black ink drawn over a surface.
  int gridPixels(ByteData data) {
    int dark = 0;
    for (int y = side ~/ 4; y < side * 3 ~/ 4; y++) {
      for (int x = side ~/ 4; x < side * 3 ~/ 4; x++) {
        final int p = (y * side + x) * 4;
        final int r = data.getUint8(p);
        final int g = data.getUint8(p + 1);
        final int b = data.getUint8(p + 2);
        if (r < 40 && g < 40 && b < 40) dark++;
      }
    }
    return dark;
  }

  testWidgets('a surface behind an opaque one does not show its grid through', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A plane at y = -3 and a sphere of radius 2 at the origin. With no
      // rotation the camera looks down +y, so the plane is nearer than every
      // part of the sphere and covers all of it.
      final List<PlotExpression> pair = <PlotExpression>[
        of('y=-3', 0),
        of('x^2+y^2+z^2=4', 1),
      ];

      final int behind = gridPixels(await render(pair, 0));
      // The same plane with nothing behind it. If the sphere is properly
      // covered, putting it there costs no ink at all.
      final int alone = gridPixels(
        await render(<PlotExpression>[of('y=-3', 0)], 0),
      );

      expect(alone, greaterThan(0), reason: 'the plane drew no grid at all');
      // Measured at 3,731 against 3,731: the hidden sphere costs no ink at
      // all. Winding the depth bias back up to the figure the batched grid
      // needed to survive its own slabs puts it at 5,761 — half as much ink
      // again, all of it the covered sphere showing through — so the margin
      // here is wide.
      expect(
        behind,
        lessThan((alone * 1.15).round()),
        reason:
            'the plane alone drew $alone grid pixels and the plane with a '
            'sphere hidden behind it $behind: the covered sphere is showing '
            'through',
      );
    });
  });

  test('switching the grid on rebuilds a mesh that was cached without it', () {
    // The grid is cached with the triangles, so a mesh built with the grid off
    // has no grid in it. If that entry answered for the grid being on, turning
    // the mesh on would draw no grid at all.
    final PlotExpression sphere = of('x^2+y^2+z^2=4', 0);
    const List<double> box = <double>[-4, 4, -4, 4, -4, 4];

    final LevelSurface marched = marchedSurface(sphere, -4, 4, -4, 4, -4, 4);

    LevelMesh build({List<double>? steps}) => cachedLevelMesh(
      sphere,
      box,
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
        for (final LevelTriangle t in marched.triangles)
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
      50,
      50,
      50,
      () => marched.normals,
      (double z, double light) => 0xFF3366CC,
      0,
      meshSteps: steps,
    );

    final LevelMesh plain = build();
    expect(plain.meshLineCount, 0);
    expect(plain.triangleCount, greaterThan(0));

    final LevelMesh wired = build(steps: <double>[40, 40, 40]);
    expect(
      wired.meshLineCount,
      greaterThan(0),
      reason:
          'the mesh cached without a grid was handed back with one asked for',
    );

    // Every segment lies on the surface it was cut from: the sphere has radius
    // 2 in data units and the mesh is scaled by 50, so 100 in mesh units.
    double worst = 0;
    for (int s = 0; s < wired.meshLineCount; s++) {
      for (int end = 0; end < 2; end++) {
        final int i = s * 6 + end * 3;
        final double x = wired.meshLines[i];
        final double y = wired.meshLines[i + 1];
        final double z = wired.meshLines[i + 2];
        worst = max(worst, (sqrt(x * x + y * y + z * z) - 100).abs());
      }
    }
    expect(worst, lessThan(1.0), reason: 'a grid segment came off the surface');

    // No segment with nothing in it. A slicing plane clipping a triangle's
    // corner meets it twice in the same place, which between a tenth and a
    // sixth of the time it does; those draw nothing but were still being
    // carried through the vertex buffer and the depth sort.
    for (int s = 0; s < wired.meshLineCount; s++) {
      final int i = s * 6;
      expect(
        wired.meshLines[i] == wired.meshLines[i + 3] &&
            wired.meshLines[i + 1] == wired.meshLines[i + 4] &&
            wired.meshLines[i + 2] == wired.meshLines[i + 5],
        isFalse,
        reason: 'segment $s has no length',
      );
    }
  });
}
