import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/curve_features.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// Tracing an equation has to solve for y.
///
/// The trace evaluated every curve as f(x), which for an equation returns
/// F(x, 0) — the amount by which (x, 0) misses satisfying it. On the unit
/// circle at x = 0.65 that is −0.578, a value not on the curve, and the marker
/// was drawn there: floating inside the circle rather than on it.
void main() {
  PlotExpression fn(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  group('the unit circle', () {
    final PlotExpression circle = fn('x^2+y^2=1');

    test('is recognised as an equation', () {
      expect(circle.isValid, isTrue);
      expect(circle.isLevelSet, isTrue);
    });

    test('has two y values inside the circle', () {
      final List<double> ys = levelSetYAt(circle, 0.65, -3, 3)..sort();
      expect(ys, hasLength(2));
      // ±√(1 − 0.65²) = ±0.7599
      expect(ys.first, closeTo(-0.75993, 1e-4));
      expect(ys.last, closeTo(0.75993, 1e-4));
    });

    test('never reports the value the old trace showed', () {
      // F(0.65, 0) = 0.65² − 1 = −0.5775, which is what was displayed.
      final List<double> ys = levelSetYAt(circle, 0.65, -3, 3);
      for (final double y in ys) {
        expect(
          (y - (-0.5775)).abs(),
          greaterThan(0.1),
          reason: 'F(x, 0) is not a point on the curve',
        );
      }
    });

    test('has no y outside the circle', () {
      // The screenshots traced to x = 1.331 and x = 1.466, where the circle
      // does not exist; the marker was drawn at 0.771 and 1.150 regardless.
      expect(levelSetYAt(circle, 1.331, -3, 3), isEmpty);
      expect(levelSetYAt(circle, 1.466, -3, 3), isEmpty);
      expect(levelSetYAt(circle, -2.0, -3, 3), isEmpty);
    });

    test('finds points at the centre and near the edge', () {
      final List<double> atZero = levelSetYAt(circle, 0, -3, 3)..sort();
      expect(atZero, hasLength(2));
      expect(atZero.first, closeTo(-1, 1e-4));
      expect(atZero.last, closeTo(1, 1e-4));

      final List<double> nearEdge = levelSetYAt(circle, 0.999, -3, 3);
      for (final double y in nearEdge) {
        expect(y.abs(), lessThan(0.05));
      }
    });

    test('only reports y inside the visible window', () {
      // A window that excludes the lower half must not invent the point.
      final List<double> ys = levelSetYAt(circle, 0.65, 0, 3);
      expect(ys, hasLength(1));
      expect(ys.single, closeTo(0.75993, 1e-4));
    });

    test('every reported y satisfies the equation', () {
      for (final double x in <double>[-0.9, -0.4, 0, 0.25, 0.8]) {
        for (final double y in levelSetYAt(circle, x, -3, 3)) {
          expect(
            circle.evaluate(x, y).abs(),
            lessThan(1e-6),
            reason: 'F($x, $y) should vanish on the curve',
          );
        }
      }
    });
  });

  test('a hyperbola reports both branches where they exist', () {
    final PlotExpression h = fn('x^2-y^2=1');
    final List<double> ys = levelSetYAt(h, 2, -5, 5)..sort();
    // y = ±√3
    expect(ys, hasLength(2));
    expect(ys.first, closeTo(-1.7320, 1e-3));
    expect(ys.last, closeTo(1.7320, 1e-3));

    expect(levelSetYAt(h, 0.5, -5, 5), isEmpty);
  });

  test('an ordinary function is untouched by any of this', () {
    final PlotExpression f = fn('x^2');
    expect(f.isLevelSet, isFalse);
    expect(f.evaluate(3, 0), 9);
  });

  group('snapping', () {
    test('offers nothing on an equation', () {
      // Sampling F(x, 0) as though it were the curve reports roots and turning
      // points that are not on the circle.
      expect(findFeatures(fn('x^2+y^2=1'), -3, 3), isEmpty);
    });

    test('still works on a function', () {
      final List<CurveFeature> features = findFeatures(fn('x^2-1'), -3, 3);
      expect(features, isNotEmpty);
    });
  });
}
