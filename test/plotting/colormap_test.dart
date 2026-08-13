import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/models/point_3d.dart';
import 'package:klotter/plotting/utils/colormap.dart';

/// Relative luminance (WCAG), the perceptual "how light is it" of a colour.
double _luminance(Color c) => c.computeLuminance();

void main() {
  group('plotColormap is jet', () {
    // Jet is the chosen ramp. It is deliberately NOT monotonic in lightness —
    // that is the trade-off of a rainbow — so these tests pin its shape rather
    // than a uniformity property it does not have.
    test('runs blue through cyan and yellow to red', () {
      expect(plotColormap(0.0).b, greaterThan(plotColormap(0.0).r));
      expect(plotColormap(1.0).r, greaterThan(plotColormap(1.0).b));
    });

    test('is clamped outside 0..1', () {
      expect(plotColormap(-5), equals(plotColormap(0)));
      expect(plotColormap(5), equals(plotColormap(1)));
    });

    test('is continuous — no jumps between stops', () {
      const int samples = 200;
      Color previous = plotColormap(0);
      for (int i = 1; i <= samples; i++) {
        final Color c = plotColormap(i / samples);
        final double step =
            (c.r - previous.r).abs() +
            (c.g - previous.g).abs() +
            (c.b - previous.b).abs();
        expect(
          step,
          lessThan(0.15),
          reason: 'discontinuity at t=${i / samples}',
        );
        previous = c;
      }
    });
  });

  group('viridisColormap remains available and uniform', () {
    // Kept as the perceptually uniform alternative.
    test('lightness increases monotonically', () {
      const int samples = 64;
      double previous = -1;
      for (int i = 0; i <= samples; i++) {
        final double lum = _luminance(viridisColormap(i / samples));
        expect(lum, greaterThanOrEqualTo(previous - 0.005));
        previous = lum;
      }
    });
  });

  group('plotColormapBanded quantises into discrete levels', () {
    test('yields exactly plotColorBands distinct colours', () {
      final seen = <int>{};
      for (int i = 0; i <= 400; i++) {
        seen.add(plotColormapBanded(i / 400).toARGB32());
      }
      expect(seen.length, equals(plotColorBands));
    });

    test('a whole band shares one colour', () {
      // Anything inside band 0 must be identical; the next band must differ.
      final double w = 1 / plotColorBands;
      expect(
        plotColormapBanded(0.01 * w),
        equals(plotColormapBanded(0.99 * w)),
      );
      expect(
        plotColormapBanded(0.5 * w),
        isNot(equals(plotColormapBanded(1.5 * w))),
      );
    });

    test('band colours are the smooth ramp sampled at band midpoints', () {
      // The colorbar swatch must be the exact colour drawn on the surface.
      for (int i = 0; i < plotColorBands; i++) {
        expect(
          plotColormapBanded((i + 0.5) / plotColorBands),
          equals(plotColormap((i + 0.5) / plotColorBands)),
        );
      }
    });

    test('the endpoints stay inside the ramp', () {
      expect(plotColormapBanded(0), equals(plotColormapBanded(0.001)));
      // The top edge belongs to the last band, not a new one.
      expect(plotColormapBanded(1), equals(plotColormapBanded(0.999)));
    });

    test('is clamped outside 0..1', () {
      expect(plotColormapBanded(-3), equals(plotColormapBanded(0)));
      expect(plotColormapBanded(7), equals(plotColormapBanded(1)));
    });

    test('plotColorBand reports the interval a value falls in', () {
      final b = plotColorBand(0.5);
      expect(b.lower, lessThanOrEqualTo(0.5));
      expect(b.upper, greaterThan(0.5));
      expect(b.index, equals((0.5 * plotColorBands).floor()));

      final top = plotColorBand(1.0);
      expect(top.index, equals(plotColorBands - 1), reason: 'no extra band');
      expect(top.upper, closeTo(1.0, 1e-12));
    });
  });

  group('surfaceGradientColor is single-hue light to dark', () {
    test('lightness decreases monotonically', () {
      const int samples = 32;
      double previous = 2;
      for (int i = 0; i <= samples; i++) {
        final double lum = _luminance(surfaceGradientColor(i / samples));
        expect(lum, lessThanOrEqualTo(previous + 0.005));
        previous = lum;
      }
    });
  });

  group('depth shading', () {
    test('a face turned toward the light is brighter than one turned away', () {
      // Flat quad in the view plane (normal along z, toward the viewer).
      final facing = quadShadeFactor(
        const Point3D(0, 0, 0),
        const Point3D(1, 0, 0),
        const Point3D(0, 1, 0),
      );
      // Quad edge-on to the light direction.
      final edgeOn = quadShadeFactor(
        const Point3D(0, 0, 0),
        const Point3D(0, 0, 1),
        const Point3D(0.5924, -0.8057, 0),
      );
      expect(facing, greaterThan(edgeOn));
    });

    test('never goes fully black — unlit faces still read as surface', () {
      final f = quadShadeFactor(
        const Point3D(0, 0, 0),
        const Point3D(0, 0, 1),
        const Point3D(0.5924, -0.8057, 0),
      );
      expect(f, greaterThan(0.3));
      expect(f, lessThanOrEqualTo(1.0));
    });

    test('degenerate quads do not produce NaN', () {
      final f = quadShadeFactor(
        const Point3D(0, 0, 0),
        const Point3D(0, 0, 0),
        const Point3D(0, 0, 0),
      );
      expect(f.isFinite, isTrue);
    });

    test('applyShading darkens toward a cool shadow, not black', () {
      const base = Color(0xFF21918C);
      final lit = applyShading(base, 1.0);
      final shadow = applyShading(base, 0.0);
      expect(lit, equals(base));
      expect(_luminance(shadow), lessThan(_luminance(base)));
      // A pure-black shadow reads as dirt; keep some blue in it.
      expect(shadow.b, greaterThan(shadow.r));
    });
  });
}
