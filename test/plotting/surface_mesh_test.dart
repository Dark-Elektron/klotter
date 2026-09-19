import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Surfaces can be drawn with their own grid over them.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int side = 300;

  Future<int> edgePixels({required bool mesh, bool interacting = false}) async {
    final PlotExpression e = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x^2+y^2'),
    ]);
    final painter = Plot3DPainter(
      function: e,
      functions: <PlotExpression>[e],
      showMesh: mesh,
      interacting: interacting,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 4,
      rangeY: 4,
      rangeZ: 30,
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
    final ByteData data = (await image.toByteData())!;

    // Count sharp changes between neighbouring pixels: a grid drawn over a
    // smooth surface is exactly that, and counting them says the lines are
    // there without pinning any particular colour.
    int edges = 0;
    for (int y = 0; y < side; y++) {
      for (int x = 1; x < side; x++) {
        final int a = (y * side + x - 1) * 4;
        final int b = (y * side + x) * 4;
        int diff = 0;
        for (int k = 0; k < 3; k++) {
          diff += (data.getUint8(a + k) - data.getUint8(b + k)).abs();
        }
        if (diff > 40) edges++;
      }
    }
    return edges;
  }

  testWidgets('the mesh puts a grid on the surface', (tester) async {
    await tester.runAsync(() async {
      final int plain = await edgePixels(mesh: false);
      final int wired = await edgePixels(mesh: true);

      expect(plain, greaterThan(0), reason: 'nothing was drawn at all');
      // Drawn every few cells rather than on every one, so it adds a clear
      // amount and not an overwhelming one — measured, about 15,900 edges
      // against 12,100 without it. A mesh as fine as the sampling grid costs
      // 2.7x the frame time and reads as shading rather than as a grid.
      expect(
        wired,
        greaterThan(plain * 1.15),
        reason: 'the mesh added little: $wired edges against $plain without it',
      );
    });
  });

  testWidgets('the mesh stays the same density however finely it samples', (
    tester,
  ) async {
    // The sampling grid drops while you drag and comes back at rest. Tying the
    // mesh to it would thin the grid out and thicken it again as you let go,
    // which reads as the picture changing rather than the camera moving.
    await tester.runAsync(() async {
      final int moving = await edgePixels(mesh: true, interacting: true);
      final int still = await edgePixels(mesh: true, interacting: false);
      final int movingPlain = await edgePixels(mesh: false, interacting: true);
      final int stillPlain = await edgePixels(mesh: false, interacting: false);

      final double addedMoving = (moving - movingPlain).toDouble();
      final double addedStill = (still - stillPlain).toDouble();
      expect(addedMoving, greaterThan(0));
      expect(
        addedStill / addedMoving,
        closeTo(1, 0.6),
        reason:
            'the mesh added $addedStill edges at rest against $addedMoving '
            'while dragging — its density is following the sampling grid',
      );
    });
  });

  testWidgets('the mesh is dark on a dark theme too', (tester) async {
    // It is drawn on the surface, not on the page. The colormap is bright
    // wherever the surface is interesting, so a line taking the theme's ink
    // went white on a dark theme and disappeared into the yellows and greens.
    await tester.runAsync(() async {
      Future<int> darkPixels(ThemeType type, {required bool mesh}) async {
        final AppColors c = AppColors.fromType(type);
        final PlotExpression e = PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'x^2+y^2'),
        ]);
        final painter = Plot3DPainter(
          function: e,
          functions: <PlotExpression>[e],
          showMesh: mesh,
          is3DFunction: true,
          rotationX: 0.6,
          rotationZ: 0.8,
          rangeX: 4,
          rangeY: 4,
          rangeZ: 30,
          panX: 0,
          panY: 0,
          plotMode: PlotMode.function,
          fieldType: FieldType.scalar,
          showContour: false,
          surfaceMode: SurfaceMode.none,
          colors: c,
          plotTheme: PlotThemeData.fromColors(c),
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(300, 300));
        final ui.Image image = await recorder.endRecording().toImage(
          side,
          side,
        );
        final ByteData data = (await image.toByteData())!;

        // Near-black pixels sitting on a saturated cell: that is a mesh line
        // over the colormap, and nothing else in the picture looks like it.
        int n = 0;
        for (int i = 0; i < side * side; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          final int r = data.getUint8(o);
          final int g = data.getUint8(o + 1);
          final int b = data.getUint8(o + 2);
          if (r < 90 && g < 90 && b < 90) n++;
        }
        return n;
      }

      // How many dark pixels the mesh *adds*. Counting dark pixels outright
      // measures the theme's own background more than anything else; the
      // difference is the mesh and nothing but the mesh.
      Future<int> added(ThemeType type) async =>
          await darkPixels(type, mesh: true) -
          await darkPixels(type, mesh: false);

      final int onLight = await added(ThemeType.light);
      final int onDark = await added(ThemeType.dark);

      expect(onLight, greaterThan(0), reason: 'no dark mesh on a light theme');
      expect(
        onDark,
        greaterThan(0),
        reason:
            'the mesh removed $onDark dark pixels on the dark theme, so it is '
            'drawing light lines there — it should be dark on both',
      );
    });
  });

  /// Ink the mesh adds for [line], as pixels that turn near-black when it is
  /// switched on.
  Future<int> meshInkFor(String line, {ComplexView? complex}) async {
    Future<int> darkPixels({required bool mesh}) async {
      final PlotExpression e = PlotExpression.compile(<MathNode>[
        LiteralNode(text: line),
      ]);
      expect(e.isValid, isTrue, reason: '$line: ${e.error}');
      final painter = Plot3DPainter(
        function: e,
        functions: <PlotExpression>[e],
        showMesh: mesh,
        is3DFunction: true,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 3,
        rangeY: 3,
        rangeZ: 3,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        complexView: complex ?? ComplexView.initial,
        colors: colors,
        plotTheme: theme,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(300, 300));
      final ui.Image image = await recorder.endRecording().toImage(side, side);
      final ByteData data = (await image.toByteData())!;
      int n = 0;
      for (int i = 0; i < side * side; i++) {
        final int o = i * 4;
        if (data.getUint8(o + 3) < 200) continue;
        if (data.getUint8(o) < 90 &&
            data.getUint8(o + 1) < 90 &&
            data.getUint8(o + 2) < 90) {
          n++;
        }
      }
      return n;
    }

    return await darkPixels(mesh: true) - await darkPixels(mesh: false);
  }

  testWidgets('an implicit surface is meshed too', (tester) async {
    // A sphere has no sampling grid: it is marched into triangles, and its own
    // edges are the mesh. It went through a different draw path from a height
    // surface and had no mesh at all.
    await tester.runAsync(() async {
      final int added = await meshInkFor('x^2+y^2+z^2=4');
      expect(
        added,
        greaterThan(0),
        reason: 'switching the mesh on changed the sphere by $added pixels',
      );
    });
  });

  testWidgets('a complex surface is meshed too', (tester) async {
    await tester.runAsync(() async {
      final int added = await meshInkFor(
        'z̲^2',
        complex: const ComplexView(colouring: false, modulus: true),
      );
      expect(
        added,
        greaterThan(0),
        reason: 'switching the mesh on changed the surface by $added pixels',
      );
    });
  });

  testWidgets('a parametric surface is meshed too', (tester) async {
    // A sweep is a grid in u and v, so its mesh is those parameter lines.
    await tester.runAsync(() async {
      final List<MathNode> nodes = <MathNode>[
        LiteralNode(text: 'u'),
        UnitVectorNode('x'),
        LiteralNode(text: '+v'),
        UnitVectorNode('y'),
        LiteralNode(text: '+u^2'),
        UnitVectorNode('z'),
      ];
      final VectorFieldParser field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.isParametric, isTrue);

      Future<int> darkPixels({required bool mesh}) async {
        final painter = Plot3DPainter(
          function: PlotExpression.invalid,
          vectorParser: field,
          vectorFields: <VectorFieldParser>[field],
          showMesh: mesh,
          is3DFunction: true,
          rotationX: 0.6,
          rotationZ: 0.8,
          rangeX: 3,
          rangeY: 3,
          rangeZ: 3,
          panX: 0,
          panY: 0,
          plotMode: PlotMode.function,
          fieldType: FieldType.vector,
          showContour: false,
          surfaceMode: SurfaceMode.none,
          uRange: (min: -1.0, max: 1.0),
          vRange: (min: -1.0, max: 1.0),
          colors: colors,
          plotTheme: theme,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(300, 300));
        final ui.Image image = await recorder.endRecording().toImage(
          side,
          side,
        );
        final ByteData data = (await image.toByteData())!;
        int n = 0;
        for (int i = 0; i < side * side; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          if (data.getUint8(o) < 90 &&
              data.getUint8(o + 1) < 90 &&
              data.getUint8(o + 2) < 90) {
            n++;
          }
        }
        return n;
      }

      final int added =
          await darkPixels(mesh: true) - await darkPixels(mesh: false);
      expect(
        added,
        greaterThan(0),
        reason: 'switching the mesh on changed the sweep by $added pixels',
      );
    });
  });

  testWidgets('an implicit mesh is a grid, not confetti', (tester) async {
    // A level surface's vertices are scaled to view units on the way out of
    // the marcher, so slicing planes spaced in data units land hundreds of
    // times too close together: measured, that covered 35% of the surface in
    // fragments. Spaced correctly it is under 1%.
    await tester.runAsync(() async {
      Future<({int dark, int surface})> counts({required bool mesh}) async {
        final PlotExpression e = PlotExpression.compile(<MathNode>[
          LiteralNode(text: 'x^2-y^2+z^2=1'),
        ]);
        final painter = Plot3DPainter(
          function: e,
          functions: <PlotExpression>[e],
          showMesh: mesh,
          is3DFunction: true,
          rotationX: 0.6,
          rotationZ: 0.8,
          rangeX: 3,
          rangeY: 3,
          rangeZ: 3,
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
        final ui.Image image = await recorder.endRecording().toImage(
          side,
          side,
        );
        final ByteData data = (await image.toByteData())!;
        int dark = 0;
        int surface = 0;
        for (int i = 0; i < side * side; i++) {
          final int o = i * 4;
          if (data.getUint8(o + 3) < 200) continue;
          final int r = data.getUint8(o);
          final int g = data.getUint8(o + 1);
          final int b = data.getUint8(o + 2);
          if (r < 90 && g < 90 && b < 90) dark++;
          final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
          final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
          if (mx > 60 && mx - mn > 40) surface++;
        }
        return (dark: dark, surface: surface);
      }

      final off = await counts(mesh: false);
      final on = await counts(mesh: true);
      final double covered = (on.dark - off.dark) / off.surface;

      // The band is wide because both ends have moved for good reasons: a
      // small depth bias buried most of the grid, and the pen was translucent
      // before it was asked to be black. Measured with the current pen, a
      // proper grid covers about 22% of the surface and slicing planes spaced
      // in the wrong units cover 89% — so anything inside the band is a grid
      // and anything outside it is either invisible or confetti.
      expect(
        covered,
        greaterThan(0.05),
        reason:
            'the mesh covers ${(covered * 100).toStringAsFixed(1)}% of the '
            'surface — too little to see',
      );
      expect(
        covered,
        lessThan(0.45),
        reason:
            'the mesh covers ${(covered * 100).toStringAsFixed(1)}% of the '
            'surface — that is fragments, not a grid',
      );
    });
  });
}
