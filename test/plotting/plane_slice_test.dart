import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// A flat view of a 3D plot is a slice of it, and which slice is now a choice.
void main() {
  group('the plane slides', () {
    // A sphere of radius 2 cut at height c is a circle of radius sqrt(4 - c*c),
    // so every slice has an answer that can be checked rather than eyeballed.
    void expectCircle(List<LevelSegment> segments, double radius) {
      expect(segments, isNotEmpty, reason: 'nothing was traced');
      for (final LevelSegment s in segments) {
        expect(
          math.sqrt(s.x1 * s.x1 + s.y1 * s.y1),
          closeTo(radius, 0.05),
          reason: 'a point came out off the circle',
        );
      }
    }

    test('a sphere cut at z = 0 is its equator', () {
      expectCircle(marchingSquares(fn('xx+yy+zz=4'), -3, 3, -3, 3), 2);
    });

    test('cutting it higher up gives a smaller circle', () {
      expectCircle(
        marchingSquares(
          fn('xx+yy+zz=4'),
          -3,
          3,
          -3,
          3,
          slice: const PlaneSlice(offset: 1),
        ),
        math.sqrt(3),
      );
    });

    test('cutting past the top gives nothing', () {
      expect(
        marchingSquares(
          fn('xx+yy+zz=4'),
          -3,
          3,
          -3,
          3,
          slice: const PlaneSlice(offset: 2.5),
        ),
        isEmpty,
      );
    });

    test('the plane it cuts is the one asked for, not always z', () {
      // A cylinder about the z axis. Cut across z it is a circle; cut across x
      // it is a pair of straight lines, so the two readings cannot be mistaken
      // for one another.
      final PlotExpression cylinder = fn('xx+yy=1');
      expectCircle(marchingSquares(cylinder, -3, 3, -3, 3), 1);

      final List<LevelSegment> walls = marchingSquares(
        cylinder,
        -3,
        3,
        -3,
        3,
        slice: const PlaneSlice(axis: SliceAxis.x),
      );
      expect(walls, isNotEmpty);
      // Held at x = 0 the equation reads y*y = 1, so every point sits on
      // y = plus or minus 1 whatever z is. Horizontal here is y.
      for (final LevelSegment s in walls) {
        expect(s.x1.abs(), closeTo(1, 0.05));
      }
    });

    test('a cached trace of one plane is not handed back for another', () {
      // The slice is not part of the expression, so without it in the key the
      // window and the resolution alone would match and sliding the plane
      // would appear to do nothing at all.
      final PlotExpression sphere = fn('xx+yy+zz=4');
      final List<LevelSegment> a = marchingSquares(sphere, -3, 3, -3, 3);
      final List<LevelSegment> b = marchingSquares(
        sphere,
        -3,
        3,
        -3,
        3,
        slice: const PlaneSlice(offset: 1),
      );
      expect(identical(a, b), isFalse);
      expectCircle(a, 2);
      expectCircle(b, math.sqrt(3));
    });

    test('a height surface cut across z is its contour', () {
      // z = x*x + y*y read at z = 4 is the circle of radius 2. This is the one
      // reading that is not a function of anything, so it goes through the
      // level tracer with the held height as the level.
      expectCircle(
        marchingSquares(
          fn('xx+yy'),
          -3,
          3,
          -3,
          3,
          slice: const PlaneSlice(offset: 4),
          iso: 4,
        ),
        2,
      );
    });
  });

  group('an untouched plot keeps the plane it always had', () {
    final AppColors colors = AppColors.fromType(ThemeType.dark);

    Plot2DPainter painterFor(PlotExpression f, {PlaneSlice? slice}) =>
        Plot2DPainter(
          function: f,
          functions: <PlotExpression>[f],
          xMin: -3,
          xMax: 3,
          yMin: -3,
          yMax: 3,
          plotMode: PlotMode.function,
          fieldType: FieldType.scalar,
          showContour: false,
          surfaceMode: SurfaceMode.none,
          colors: colors,
          plotTheme: PlotThemeData.fromColors(colors),
          slice: slice,
        );

    test('an equation still opens on z = 0', () {
      // Marching squares let the third argument default, so this is what a
      // level set has always shown.
      final PlotExpression e = fn('xx+yy+zz=4');
      expect(painterFor(e).sliceFor(e).axis, SliceAxis.z);
      expect(painterFor(e).sliceFor(e).offset, 0);
      expect(painterFor(e).tracesLevel(e), isTrue);
      expect(painterFor(e).isoFor(e), 0);
    });

    test('a surface still opens on y = 0', () {
      // A height surface was drawn by evaluating f(x, 0) — a different plane
      // from the one an equation showed, which is the confusion this fixes.
      // It must not move under anyone who has not asked for it to.
      final PlotExpression e = fn('xx+yy');
      expect(painterFor(e).sliceFor(e).axis, SliceAxis.y);
      expect(
        painterFor(e).tracesLevel(e),
        isFalse,
        reason: 'cut across y it is still a function, drawn by walking it',
      );
    });

    test('a surface asked for z is traced as a contour at that height', () {
      final PlotExpression e = fn('xx+yy');
      final Plot2DPainter p = painterFor(e, slice: const PlaneSlice(offset: 4));
      expect(p.tracesLevel(e), isTrue);
      expect(p.isoFor(e), 4);
    });

    test('a plain curve is untouched by the default', () {
      final PlotExpression e = fn('xx');
      final Plot2DPainter p = painterFor(e);
      expect(p.tracesLevel(e), isFalse);
      // f(x) at any y, so the default slice must not change what is drawn.
      expect(p.sliceFor(e).sample(e, 3, 0), closeTo(9, 1e-9));
    });
  });

  group('the chosen plane survives being swiped away', () {
    test('it round-trips through storage', () {
      const PlotViewState v = PlotViewState(sliceAxis: 1, sliceOffset: -1.25);
      final PlotViewState back = PlotViewState.fromJson(v.toJson());
      expect(back.sliceAxis, 1);
      expect(back.sliceOffset, -1.25);
    });

    test('an untouched plot stores no plane at all', () {
      expect(PlotViewState.initial.sliceAxis, isNull);
      expect(PlotViewState.initial.isInitial, isTrue);
    });

    test('a nonsense axis is refused rather than crashing', () {
      final PlotViewState back = PlotViewState.fromJson(<String, dynamic>{
        'sliceAxis': 9,
        'sliceOffset': 'nope',
      });
      expect(back.sliceAxis, isNull);
      expect(back.sliceOffset, 0);
    });

    test('choosing a plane and clearing it are both sayable', () {
      const PlotViewState v = PlotViewState(sliceAxis: 2, sliceOffset: 3);
      expect(v.copyWith(sliceOffset: 4).sliceAxis, 2);
      expect(v.copyWith(clearSlice: true).sliceAxis, isNull);
      expect(v.copyWith(clearSlice: true).sliceOffset, 0);
    });
  });
}
