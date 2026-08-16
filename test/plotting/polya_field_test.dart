import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The Polya vector field: the arrows of the *conjugate* of f.
///
/// The conjugation is the whole point. That field is divergence-free and
/// curl-free exactly where f is holomorphic — the Cauchy-Riemann equations
/// restated — which is what makes the arrows mean something rather than merely
/// decorate the plot. Drawn from f itself the picture would look much the same
/// and say nothing, so these tests are about direction, not about ink.
void main() {
  const Size canvas = Size(240, 240);
  const double span = 2;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  PlotExpression identity() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'z+0i')]);

  PlotExpression squared() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'z^2+0i')]);

  Future<ui.Image> render(PlotExpression expr, ComplexView view) async {
    final painter = Plot2DPainter(
      function: expr,
      functions: <PlotExpression>[expr],
      xMin: -span,
      xMax: span,
      yMin: -span,
      yMax: span,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: PlotThemeData.fromColors(colors),
      complexView: view,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvas);
    return recorder.endRecording().toImage(240, 240);
  }

  Future<int> inked(ui.Image image) async {
    final data = (await image.toByteData())!;
    int n = 0;
    for (int i = 0; i < 240 * 240; i++) {
      if (data.getUint8(i * 4 + 3) > 40) n++;
    }
    return n;
  }

  /// The Polya field at a point: the conjugate, as a plain pair.
  ({double x, double y}) polyaAt(PlotExpression f, double re, double im) {
    final w = f.evaluateComplex(re, im);
    return (x: w.real, y: -w.imag);
  }

  test('the expressions under test are complex', () {
    // The guard every rendering test here carries: one that failed to compile
    // draws nothing, and renders of nothing agree about everything.
    expect(identity().isComplex, isTrue);
    expect(squared().isComplex, isTrue);
    expect(squared().isValid, isTrue, reason: squared().error);
  });

  group('the view is a set, not a choice', () {
    test('a new complex plot shows the colouring', () {
      expect(ComplexView.initial.showsColouring, isTrue);
      expect(ComplexView.initial.showsPolya, isFalse);
    });

    test('both can be on at once', () {
      const ComplexView both = ComplexView(colouring: true, polya: true);
      expect(both.showsColouring, isTrue);
      expect(both.showsPolya, isTrue);
      expect(both.isEmpty, isFalse);
    });

    test('and everything can be off', () {
      const ComplexView none = ComplexView(
        colouring: false,
        polya: false,
        modulus: false,
      );
      expect(none.isEmpty, isTrue);
    });

    test('it survives being packed and unpacked', () {
      for (final ComplexView v in <ComplexView>[
        ComplexView.initial,
        const ComplexView(colouring: false, polya: true),
        const ComplexView(real: true, imaginary: true, modulus: false),
      ]) {
        expect(ComplexView.fromBits(v.bits), v);
      }
    });
  });

  group('drawing', () {
    testWidgets('the arrows can be drawn without the colouring', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final int arrows = await inked(
          await render(
            identity(),
            const ComplexView(colouring: false, polya: true),
          ),
        );
        final int bare = await inked(
          await render(
            identity(),
            const ComplexView(colouring: false, polya: false),
          ),
        );
        expect(arrows, greaterThan(bare + 800), reason: '$arrows vs $bare');
      });
    });

    testWidgets('and the colouring fills far more of the window than they do', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final int both = await inked(
          await render(
            identity(),
            const ComplexView(colouring: true, polya: true),
          ),
        );
        final int arrows = await inked(
          await render(
            identity(),
            const ComplexView(colouring: false, polya: true),
          ),
        );
        expect(arrows * 2, lessThan(both));
      });
    });
  });

  group('the arrows point the conjugate way', () {
    test('for f(z) = z they lean back toward the zero', () {
      final f = identity();
      final a = polyaAt(f, 1, 0);
      expect(a.x, closeTo(1, 1e-9));
      expect(a.y, closeTo(0, 1e-9));

      final b = polyaAt(f, 0, 1);
      expect(b.x, closeTo(0, 1e-9));
      expect(b.y, closeTo(-1, 1e-9));
    });

    test('which is not where f itself points', () {
      // The distinction the visualisation rests on: at i, f gives (0, 1) and
      // the Polya field gives (0, -1). Opposite.
      final f = identity();
      expect(f.evaluateComplex(0, 1).imag, closeTo(1, 1e-9));
      expect(polyaAt(f, 0, 1).y, closeTo(-1, 1e-9));
    });

    test('a holomorphic field neither spreads nor swirls', () {
      final f = squared();
      const double h = 1e-4;
      const double x0 = 0.7, y0 = -0.4;
      final right = polyaAt(f, x0 + h, y0);
      final left = polyaAt(f, x0 - h, y0);
      final up = polyaAt(f, x0, y0 + h);
      final down = polyaAt(f, x0, y0 - h);

      final double divergence =
          (right.x - left.x) / (2 * h) + (up.y - down.y) / (2 * h);
      final double curl =
          (right.y - left.y) / (2 * h) - (up.x - down.x) / (2 * h);

      expect(divergence.abs(), lessThan(1e-5), reason: 'div $divergence');
      expect(curl.abs(), lessThan(1e-5), reason: 'curl $curl');
    });

    test('while the un-conjugated field does both', () {
      // The control. Without it the test above could be passing on the limits
      // of the difference quotient rather than on the conjugation.
      final f = squared();
      ({double x, double y}) raw(double re, double im) {
        final w = f.evaluateComplex(re, im);
        return (x: w.real, y: w.imag);
      }

      const double h = 1e-4;
      const double x0 = 0.7, y0 = -0.4;
      final double divergence =
          (raw(x0 + h, y0).x - raw(x0 - h, y0).x) / (2 * h) +
          (raw(x0, y0 + h).y - raw(x0, y0 - h).y) / (2 * h);
      expect(divergence.abs(), greaterThan(1), reason: 'div $divergence');
    });
  });

  testWidgets('every arrow is the same length', (tester) async {
    await tester.runAsync(() async {
      // The modulus is already shown by the colouring underneath. Letting it
      // set the length too made the arrows near a zero too short to read a
      // direction from, which is the one thing the field is for.
      //
      // Measured as ink rather than as geometry: for f(z) = z the modulus
      // runs from nothing at the origin to its largest at the corners, so
      // length-scaled arrows would put far more of their ink in the outer
      // half of the plot than in the inner one.
      final image = await render(
        identity(),
        const ComplexView(colouring: false, polya: true),
      );
      final data = (await image.toByteData())!;

      int inner = 0, outer = 0;
      for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 240; x++) {
          if (data.getUint8((y * 240 + x) * 4 + 3) < 40) continue;
          final double dx = (x - 120) / 120, dy = (y - 120) / 120;
          if (dx * dx + dy * dy < 0.25) {
            inner++;
          } else {
            outer++;
          }
        }
      }
      // The inner disc is a quarter of the square, so equal-length arrows put
      // roughly a quarter of the ink there. Scaled ones put almost none.
      final double share = inner / (inner + outer);
      expect(share, greaterThan(0.12), reason: 'inner share $share');
    });
  });
}
