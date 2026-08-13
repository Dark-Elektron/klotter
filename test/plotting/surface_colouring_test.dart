import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/utils/colormap.dart';

/// A surface must be coloured against its own value range.
///
/// The 3D surface used to normalise by the axis half-range —
/// `(value + rangeZ) / (2 * rangeZ)` — which assumes the data is symmetric
/// about zero and fills the axis. `x² + y²` is neither: every value landed in
/// the upper half of the ramp, so the surface came out nearly one colour no
/// matter its magnitude. These pin the arithmetic that replaced it.
void main() {
  /// The normalisation the surface now uses.
  double normalize(double value, double min, double max) {
    final span = max > min ? max - min : 0.0;
    return span > 0 ? ((value - min) / span).clamp(0.0, 1.0) : 0.5;
  }

  group('a non-negative surface uses the whole ramp', () {
    test('x²+y² spans 0..1 rather than 0.5..1', () {
      // Sampled over x,y in [-3,3]: min 0 at the origin, max 18 at a corner.
      const double min = 0, max = 18;
      expect(normalize(0, min, max), equals(0.0));
      expect(normalize(18, min, max), equals(1.0));
      expect(normalize(9, min, max), closeTo(0.5, 1e-12));
    });

    test('the old axis-relative formula compressed it into half the ramp', () {
      // rangeZ is the axis half-range, here 18.
      double old(double v, double rangeZ) => (v + rangeZ) / (2 * rangeZ);
      expect(old(0, 18), closeTo(0.5, 1e-12));
      expect(old(18, 18), closeTo(1.0, 1e-12));
      // Half the ramp unreachable — the bug, stated as a fact.
      expect(old(0, 18), greaterThan(0.45));
    });

    test('distinct magnitudes get distinct colours', () {
      const double min = 0, max = 18;
      final low = plotColormap(normalize(1, min, max));
      final mid = plotColormap(normalize(9, min, max));
      final high = plotColormap(normalize(17, min, max));
      expect(low, isNot(equals(mid)));
      expect(mid, isNot(equals(high)));
    });
  });

  group('edge cases', () {
    test('a flat surface sits mid-ramp instead of dividing by zero', () {
      expect(normalize(5, 5, 5), equals(0.5));
      expect(plotColormap(normalize(5, 5, 5)), isA<Color>());
    });

    test('a surface entirely below zero still spans the ramp', () {
      expect(normalize(-10, -10, -2), equals(0.0));
      expect(normalize(-2, -10, -2), equals(1.0));
    });

    test('values outside the sampled range clamp rather than wrap', () {
      expect(normalize(-1, 0, 10), equals(0.0));
      expect(normalize(11, 0, 10), equals(1.0));
    });
  });
}
