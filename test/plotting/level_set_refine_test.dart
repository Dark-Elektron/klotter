import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/point_3d.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_cache.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Where two sheets of a surface come closer than a lattice cell, both ends of
/// every edge between them are on the same side, and a march sees nothing
/// there. (x²+z²−y)(x²+z²−2y) = 0 — two paraboloids touching at their tips —
/// came out with a ragged hole round the tips and the background showing
/// through. The cells that cannot see are found and marched again finer.
void main() {
  PlotExpression fn(String t) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

  setUp(releasePlotGeometry);

  double nearestToOrigin(LevelSurface s) {
    double nearest = double.infinity;
    for (final LevelTriangle t in s.triangles) {
      for (final Point3D p in <Point3D>[t.a, t.b, t.c]) {
        nearest = min(nearest, sqrt(p.x * p.x + p.y * p.y + p.z * p.z));
      }
    }
    return nearest;
  }

  /// Connected pieces of a mesh, joining corners that meet within [tolerance].
  /// Pieces of a handful of corners are not counted.
  int pieces(LevelSurface s, double tolerance) {
    final Map<String, int> ids = <String, int>{};
    final List<int> parent = <int>[];
    int idOf(Point3D p) {
      final String key =
          '${(p.x / tolerance).round()},${(p.y / tolerance).round()},'
          '${(p.z / tolerance).round()}';
      return ids.putIfAbsent(key, () {
        parent.add(parent.length);
        return parent.length - 1;
      });
    }

    int find(int a) {
      while (parent[a] != a) {
        parent[a] = parent[parent[a]];
        a = parent[a];
      }
      return a;
    }

    for (final LevelTriangle t in s.triangles) {
      final int a = find(idOf(t.a)), b = find(idOf(t.b)), c = find(idOf(t.c));
      parent[a] = b;
      parent[find(c)] = find(b);
    }
    final Map<int, int> sizes = <int, int>{};
    for (int i = 0; i < parent.length; i++) {
      sizes[find(i)] = (sizes[find(i)] ?? 0) + 1;
    }
    return sizes.values.where((int n) => n > 20).length;
  }

  const String tips = 'x^4+z^4+2x^2z^2-3y(x^2+z^2)+2y^2=0';

  test('two sheets that touch are drawn right up to where they meet', () {
    final PlotExpression pair = fn(tips);
    LevelSurface march({required bool refine}) =>
        marchedSurface(pair, -3, 3, -3, 3, -3.45, 3.45, refine: refine);

    // Both sheets pass through the origin. Plain, nothing came within 0.3 of
    // it — the hole; refined, the surface reaches to within a tenth.
    final double plain = nearestToOrigin(march(refine: false));
    final double refined = nearestToOrigin(march(refine: true));
    expect(plain, greaterThan(0.25), reason: 'the plain march has changed');
    expect(refined, lessThan(0.15), reason: 'the hole is $refined across');
  });

  test('a surface with nothing too thin is marched exactly as before', () {
    // Refinement looks only into cells that see nothing, so a shape the
    // lattice resolves everywhere costs nothing and comes out the same.
    final PlotExpression tooth = fn('x^4+y^4+z^4-x^2-y^2-z^2+0.4=0');
    final LevelSurface plain = marchedSurface(
      tooth,
      -2,
      2,
      -2,
      2,
      -2,
      2,
      refine: false,
    );
    final LevelSurface refined = marchedSurface(tooth, -2, 2, -2, 2, -2, 2);
    expect(refined.triangles.length, plain.triangles.length);
  });

  test('pieces that really are apart stay apart', () {
    // Four legs that stop just short of a body: F peaks at +0.019 between
    // them, so there are five pieces. A refinement that invented necks there
    // would be drawing a shape the equation does not have.
    final LevelSurface s = marchedSurface(
      fn('x^4+0.5y^4+z^4-y^3-x^2-z^2+0.5x^2z^2+x^2y^2+y^2z^2+1/3=0'),
      -2,
      2,
      -2,
      2,
      -2.3,
      2.3,
    );
    expect(pieces(s, 0.02), 5);
  });

  test('and pieces joined by thin necks stay joined', () {
    final LevelSurface s = marchedSurface(
      fn('x^4+0.5y^4+z^4-y^3-x^2-z^2+0.5x^2z^2+x^2y^2+y^2z^2+0.31=0'),
      -2,
      2,
      -2,
      2,
      -2.3,
      2.3,
    );
    expect(pieces(s, 0.02), 1);
  });

  testWidgets('a pinch draws the plain march, and rest the refined one', (
    tester,
  ) async {
    // While the box changes every frame is a march of its own, so refining
    // each of them would cost a pinch its smoothness. At rest it is refined.
    final AppColors colors = AppColors.fromType(ThemeType.dark);
    final PlotThemeData theme = PlotThemeData.fromColors(colors);
    final PlotExpression pair = fn(tips);

    Plot3DPainter painter({required bool interacting}) => Plot3DPainter(
      function: pair,
      functions: <PlotExpression>[pair],
      is3DFunction: true,
      interacting: interacting,
      rotationX: 0.12,
      rotationZ: 0,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 3.45,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );

    void paint(Plot3DPainter p) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), const Size(300, 300));
      recorder.endRecording().dispose();
    }

    // Read off a painter that has painted: the scale is worked out from the
    // panel as it paints.
    bool cached(Plot3DPainter p, {required bool refined}) => hasCachedLevelMesh(
      pair,
      <double>[-3, 3, -3, 3, -3.45, 3.45],
      40,
      p.scaleX,
      p.scaleY,
      p.scaleZ,
      // How the painter tells meshes coloured differently apart: the mode and
      // the ramp.
      SurfaceMode.none.index * 2 + PlotPalette.turbo.index,
      refined: refined,
    );

    final Plot3DPainter moving = painter(interacting: true);
    paint(moving);
    expect(cached(moving, refined: false), isTrue);
    expect(cached(moving, refined: true), isFalse, reason: 'refined mid-pinch');

    final Plot3DPainter still = painter(interacting: false);
    paint(still);
    expect(cached(still, refined: true), isTrue);

    // A rotation changes nothing the mesh depends on, so once the refined one
    // is made it is used while moving too, rather than the plain one.
    releasePlotGeometry();
    paint(painter(interacting: false));
    final Plot3DPainter turning = painter(interacting: true);
    paint(turning);
    expect(cached(turning, refined: false), isFalse);
  });

  testWidgets('in the app the refined surface is made off the UI thread', (
    tester,
  ) async {
    // Under `flutter test` it is made in place, so every other test sees the
    // finished surface on the first paint. The app draws the plain march at
    // once instead and swaps the refined one in when it lands.
    final BackgroundMarches marches = BackgroundMarches(enabled: true);

    final AppColors colors = AppColors.fromType(ThemeType.dark);
    final PlotThemeData theme = PlotThemeData.fromColors(colors);
    final PlotExpression pair = fn(tips);
    final Plot3DPainter p = Plot3DPainter(
      function: pair,
      functions: <PlotExpression>[pair],
      is3DFunction: true,
      rotationX: 0.12,
      rotationZ: 0,
      rangeX: 3,
      rangeY: 3,
      rangeZ: 3.45,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
      marches: marches,
    );
    void paint() {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), const Size(300, 300));
      recorder.endRecording().dispose();
    }

    bool refinedMarched() =>
        hasMarchedSurface(pair, -3, 3, -3, 3, -3.45, 3.45, refine: true);

    await tester.runAsync(() async {
      final int before = marches.landed.value;
      paint();
      // Not yet: the first paint drew the plain march.
      expect(refinedMarched(), isFalse);

      final Stopwatch waited = Stopwatch()..start();
      while (marches.landed.value == before &&
          waited.elapsed < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(marches.enabled, isTrue, reason: 'the isolate could not run');
      expect(refinedMarched(), isTrue, reason: 'nothing landed');
    });

    // What landed is what marching in place makes.
    final LevelSurface landed = marchedSurface(pair, -3, 3, -3, 3, -3.45, 3.45);
    releasePlotGeometry();
    final LevelSurface inPlace = marchedSurface(
      pair,
      -3,
      3,
      -3,
      3,
      -3.45,
      3.45,
    );
    expect(landed.triangles.length, inPlace.triangles.length);
  });
}
