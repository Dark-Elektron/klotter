import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// A flat view of a 3D field is a slice of it, and it slides like every other.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);

  Plot2DPainter painterFor(VectorFieldParser field, {PlaneSlice? slice}) {
    final PlotExpression blank = fn('x');
    return Plot2DPainter(
      function: blank,
      functions: const <PlotExpression>[],
      vectorParser: field,
      xMin: -3,
      xMax: 3,
      yMin: -3,
      yMax: 3,
      plotMode: PlotMode.function,
      fieldType: FieldType.vector,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
      slice: slice,
    );
  }

  /// The field whose value at a point is the point itself.
  final VectorFieldParser position = VectorFieldParser(
    xComponent: fn('x'),
    yComponent: fn('y'),
    zComponent: fn('z'),
  );

  test('a field opens on z = 0, which is where it has always been read', () {
    final Plot2DPainter p = painterFor(position);
    expect(p.fieldSlice.axis, SliceAxis.z);
    expect(p.fieldSlice.offset, 0);
  });

  test('the arrows are whichever components lie in the plane', () {
    // A constant field, so only the choice of components can vary the answer.
    final VectorFieldParser uniform = VectorFieldParser(
      xComponent: fn('1'),
      yComponent: fn('2'),
      zComponent: fn('3'),
    );

    // Held at z the plane's axes are x across and y up, so the arrows are
    // (Fx, Fy) and Fz points at the reader.
    final held = painterFor(uniform).fieldOnPlane(uniform, 0, 0);
    expect(held.h, 1);
    expect(held.v, 2);
    expect(held.out, 3);

    // Held at x they are y across and z up, so the arrows become (Fy, Fz).
    final acrossX = painterFor(
      uniform,
      slice: const PlaneSlice(axis: SliceAxis.x),
    ).fieldOnPlane(uniform, 0, 0);
    expect(acrossX.h, 2);
    expect(acrossX.v, 3);
    expect(acrossX.out, 1);

    // Held at y they are x across and z up.
    final acrossY = painterFor(
      uniform,
      slice: const PlaneSlice(axis: SliceAxis.y),
    ).fieldOnPlane(uniform, 0, 0);
    expect(acrossY.h, 1);
    expect(acrossY.v, 3);
    expect(acrossY.out, 2);
  });

  test('where it samples and what it draws agree, on every plane', () {
    // The field that reports its own position. Read on any plane it must come
    // back saying exactly where it was asked from: the two in-plane readings
    // are the coordinates given, and the one pointing out of the plane is the
    // offset being held. It is the one field that catches permuting the point
    // one way and the components another — which reads correctly on the plane
    // it was written for and is wrong on the other two.
    for (final SliceAxis axis in SliceAxis.values) {
      final PlaneSlice slice = PlaneSlice(axis: axis, offset: 1.75);
      final f = painterFor(
        position,
        slice: slice,
      ).fieldOnPlane(position, 0.5, -2.25);
      expect(f.h, closeTo(0.5, 1e-9), reason: 'across, held at ${axis.label}');
      expect(f.v, closeTo(-2.25, 1e-9), reason: 'up, held at ${axis.label}');
      expect(
        f.out,
        closeTo(1.75, 1e-9),
        reason: 'out of the plane, held at ${axis.label}',
      );
    }
  });

  test('sliding the plane moves where the field is read', () {
    // A field that is nothing at z = 0 and grows as the plane rises, so a
    // slider that did not reach the sampling would read zero for ever.
    final VectorFieldParser rising = VectorFieldParser(
      xComponent: fn('z'),
      yComponent: fn('0'),
      zComponent: fn('0'),
    );
    expect(painterFor(rising).fieldMagnitude(rising, 1, 1), 0);
    expect(
      painterFor(
        rising,
        slice: const PlaneSlice(offset: 2),
      ).fieldMagnitude(rising, 1, 1),
      closeTo(2, 1e-9),
    );
  });

  test('strength is the whole vector, not just the part in view', () {
    // Running straight through the slice and nowhere across it. Shading that
    // as weak would say the field is absent where it is strongest.
    final VectorFieldParser through = VectorFieldParser(
      xComponent: fn('0'),
      yComponent: fn('0'),
      zComponent: fn('4'),
    );
    final Plot2DPainter p = painterFor(through);
    expect(p.fieldOnPlane(through, 0, 0).h, 0);
    expect(p.fieldOnPlane(through, 0, 0).v, 0);
    expect(p.fieldMagnitude(through, 0, 0), closeTo(4, 1e-9));
  });

  test('a named component keeps its name whatever the plane', () {
    final VectorFieldParser uniform = VectorFieldParser(
      xComponent: fn('1'),
      yComponent: fn('2'),
      zComponent: fn('3'),
    );
    for (final SliceAxis axis in SliceAxis.values) {
      final Plot2DPainter p = painterFor(
        uniform,
        slice: PlaneSlice(axis: axis),
      );
      expect(p.fieldComponent(uniform, SurfaceMode.x, 0, 0), 1);
      expect(p.fieldComponent(uniform, SurfaceMode.y, 0, 0), 2);
      expect(p.fieldComponent(uniform, SurfaceMode.z, 0, 0), 3);
      expect(
        p.fieldComponent(uniform, SurfaceMode.magnitude, 0, 0),
        closeTo(math.sqrt(14), 1e-9),
      );
    }
  });
}
