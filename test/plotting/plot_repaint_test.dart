import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A plot repaints when any one of its inputs changes, on its own.
///
/// `CustomPaint` keeps the old picture whenever `shouldRepaint` says no, so an
/// input missing from it is one the plot ignores until something else happens
/// to move. Each of these was missing, and each showed up as a control that
/// did nothing: the 3D trace marker never appeared under a long press,
/// Re/Im/|f| and arg/↗ did not redraw, the u and v chips waited for the next
/// pan, a new row's inset left the 3D box where it was, and a surface kept its
/// coarse dragging grid after the finger lifted.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  final PlotThemeData lightTheme = PlotThemeData.fromColors(
    AppColors.fromType(ThemeType.light),
  );
  final PlotExpression surface = PlotExpression.compile(<MathNode>[
    LiteralNode(text: 'x^2+y^2'),
  ]);
  final PlotExpression other = PlotExpression.compile(<MathNode>[
    LiteralNode(text: 'x+y'),
  ]);
  const ParameterRange wide = (min: -3.0, max: 3.0);
  const ComplexView modulusOnly = ComplexView(
    colouring: false,
    modulus: true,
  );
  const SurfaceHit hit = (
    x: 1.0,
    y: 1.0,
    z: 2.0,
    curveIndex: 0,
    u: null,
    v: null,
  );

  group('3D', () {
    Plot3DPainter painter({
      List<PlotExpression>? functions,
      double bottomInset = 0,
      ParameterRange uRange = defaultParameterRange,
      ParameterRange vRange = defaultParameterRange,
      ComplexView complexView = ComplexView.initial,
      SurfaceHit? tracePoint,
      bool interacting = false,
      Size? fitSize,
      PlotThemeData? plotTheme,
    }) => Plot3DPainter(
      function: surface,
      functions: functions ?? <PlotExpression>[surface],
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: 5,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: plotTheme ?? theme,
      bottomInset: bottomInset,
      uRange: uRange,
      vRange: vRange,
      complexView: complexView,
      tracePoint: tracePoint,
      interacting: interacting,
      fitSize: fitSize,
    );

    final Plot3DPainter base = painter();

    test('the same inputs do not repaint', () {
      expect(painter().shouldRepaint(base), isFalse);
      // A new list holding the same surfaces is the same picture.
      expect(
        painter(functions: <PlotExpression>[surface]).shouldRepaint(base),
        isFalse,
      );
    });

    final Map<String, Plot3DPainter> changes = <String, Plot3DPainter>{
      'a second surface': painter(
        functions: <PlotExpression>[surface, other],
      ),
      'the rows covering more of the panel': painter(bottomInset: 120),
      'the u sweep': painter(uRange: wide),
      'the v sweep': painter(vRange: wide),
      'the complex readings on show': painter(complexView: modulusOnly),
      'the trace marker': painter(tracePoint: hit),
      'the surface settling after a spin': painter(interacting: true),
      'a resize settling': painter(fitSize: const Size(400, 500)),
      'the plot theme': painter(plotTheme: lightTheme),
    };
    for (final MapEntry<String, Plot3DPainter> c in changes.entries) {
      test('${c.key} repaints', () {
        expect(c.value.shouldRepaint(base), isTrue);
        expect(base.shouldRepaint(c.value), isTrue);
      });
    }
  });

  group('2D', () {
    final PlotExpression z2 = PlotExpression.compile(<MathNode>[
      ComplexVariableNode(),
      LiteralNode(text: '^2'),
    ]);

    Plot2DPainter painter({
      ParameterRange uRange = defaultParameterRange,
      ParameterRange vRange = defaultParameterRange,
      ComplexView complexView = ComplexView.initial,
      bool interacting = false,
      PlotThemeData? plotTheme,
    }) => Plot2DPainter(
      function: z2,
      functions: <PlotExpression>[z2],
      xMin: -5,
      xMax: 5,
      yMin: -10,
      yMax: 10,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: plotTheme ?? theme,
      uRange: uRange,
      vRange: vRange,
      complexView: complexView,
      interacting: interacting,
    );

    final Plot2DPainter base = painter();

    test('the same inputs do not repaint', () {
      expect(painter().shouldRepaint(base), isFalse);
    });

    final Map<String, Plot2DPainter> changes = <String, Plot2DPainter>{
      'arg and ↗ toggled': painter(
        complexView: ComplexView.initial.copyWith(colouring: false),
      ),
      'the u sweep': painter(uRange: wide),
      'the v sweep': painter(vRange: wide),
      'the curve settling after a pan': painter(interacting: true),
      'the plot theme': painter(plotTheme: lightTheme),
    };
    for (final MapEntry<String, Plot2DPainter> c in changes.entries) {
      test('${c.key} repaints', () {
        expect(c.value.shouldRepaint(base), isTrue);
        expect(base.shouldRepaint(c.value), isTrue);
      });
    }
  });
}
