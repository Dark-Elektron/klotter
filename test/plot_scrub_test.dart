import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// The dock's magnification, as a curve.
///
/// A copy of the falloff used by the strip's dots, checked for the properties
/// that make it read as a swell rather than as one dot picked out: it peaks
/// under the finger, falls away smoothly either side, and comes back to the
/// resting size for dots that are far off.
double dotSize(int i, int focus, {required bool scrubbing}) {
  const double resting = 5, current = 7, peak = 14;
  if (!scrubbing) return i == focus ? current : resting;
  final double d = (i - focus).toDouble();
  return resting + (peak - resting) * math.exp(-(d * d) / 2.0);
}

void main() {
  group('at rest', () {
    test('the strip is a plain row of dots', () {
      // No swell when nobody is scrubbing: one dot marks the page and the
      // rest are the same size.
      expect(dotSize(3, 3, scrubbing: false), 7);
      expect(dotSize(2, 3, scrubbing: false), 5);
      expect(dotSize(9, 3, scrubbing: false), 5);
    });
  });

  group('while scrubbing', () {
    test('the dot under the finger is the largest', () {
      final double centre = dotSize(4, 4, scrubbing: true);
      for (final int i in <int>[0, 1, 2, 3, 5, 6, 7, 8]) {
        expect(dotSize(i, 4, scrubbing: true), lessThan(centre));
      }
    });

    test('it falls away either side rather than cutting off', () {
      // The thing that separates a dock swell from a highlight: the
      // neighbours are raised too, by progressively less.
      final double a = dotSize(4, 4, scrubbing: true);
      final double b = dotSize(5, 4, scrubbing: true);
      final double c = dotSize(6, 4, scrubbing: true);
      expect(b, lessThan(a));
      expect(c, lessThan(b));
      // And the first neighbour is meaningfully raised, not a hair.
      expect(b, greaterThan(7));
    });

    test('and is symmetric about the finger', () {
      for (final int d in <int>[1, 2, 3]) {
        expect(
          dotSize(4 - d, 4, scrubbing: true),
          closeTo(dotSize(4 + d, 4, scrubbing: true), 1e-9),
        );
      }
    });

    test('dots far from the finger return to their resting size', () {
      // Otherwise a long strip would swell along its whole length and the
      // magnification would say nothing about where the finger is.
      expect(dotSize(12, 4, scrubbing: true), closeTo(5, 0.01));
    });

    test('nothing shrinks below its resting size', () {
      for (int i = 0; i < 20; i++) {
        expect(dotSize(i, 7, scrubbing: true), greaterThanOrEqualTo(5.0));
      }
    });
  });
}
