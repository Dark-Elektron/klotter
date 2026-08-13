import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/curve_features.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

void main() {
  group('roots', () {
    test('finds the root of a line', () {
      final f = findFeatures(fn('x-2'), -10, 10);
      final roots = f.where((e) => e.kind == FeatureKind.root).toList();
      expect(roots, hasLength(1));
      expect(roots.single.x, closeTo(2, 1e-6));
    });

    test('finds both roots of a parabola', () {
      // xx-4 crosses at -2 and 2.
      final roots =
          findFeatures(
              fn('xx-4'),
              -10,
              10,
            ).where((e) => e.kind == FeatureKind.root).map((e) => e.x).toList()
            ..sort();
      expect(roots, hasLength(2));
      expect(roots.first, closeTo(-2, 1e-6));
      expect(roots.last, closeTo(2, 1e-6));
    });

    test('a curve that never crosses has no roots', () {
      final roots = findFeatures(
        fn('xx+1'),
        -5,
        5,
      ).where((e) => e.kind == FeatureKind.root);
      expect(roots, isEmpty);
    });

    test('does not mistake a discontinuity for a root', () {
      // 1/x flips sign at 0 without crossing.
      final roots = findFeatures(
        fn('1/x'),
        -5,
        5,
      ).where((e) => e.kind == FeatureKind.root);
      expect(roots, isEmpty);
    });
  });

  group('turning points', () {
    test('finds the vertex of a parabola as a minimum', () {
      final mins =
          findFeatures(
            fn('xx-4'),
            -10,
            10,
          ).where((e) => e.kind == FeatureKind.minimum).toList();
      expect(mins, hasLength(1));
      expect(mins.single.x, closeTo(0, 1e-4));
      expect(mins.single.y, closeTo(-4, 1e-4));
    });

    test('finds a maximum for a downward parabola', () {
      final maxes =
          findFeatures(
            fn('4-xx'),
            -10,
            10,
          ).where((e) => e.kind == FeatureKind.maximum).toList();
      expect(maxes, hasLength(1));
      expect(maxes.single.x, closeTo(0, 1e-4));
      expect(maxes.single.y, closeTo(4, 1e-4));
    });

    test('a straight line has no turning points', () {
      final turns = findFeatures(
        fn('2x'),
        -10,
        10,
      ).where((e) => e.kind != FeatureKind.root);
      expect(turns, isEmpty);
    });
  });

  group('nearestFeature', () {
    test('snaps only within tolerance', () {
      final features = findFeatures(fn('xx-4'), -10, 10);
      expect(nearestFeature(features, 1.95, 0.2)?.x, closeTo(2, 1e-6));
      expect(nearestFeature(features, 1.0, 0.2), isNull);
    });

    test('null when there is nothing to snap to', () {
      expect(nearestFeature(const <CurveFeature>[], 0, 1), isNull);
    });
  });

  group('robustness', () {
    test('an invalid curve yields nothing', () {
      expect(findFeatures(fn('q'), -5, 5), isEmpty);
    });

    test('an inverted window yields nothing', () {
      expect(findFeatures(fn('x'), 5, -5), isEmpty);
    });

    test('trig roots land on multiples of pi', () {
      // sin must be a TrigNode; the engine does not parse function syntax out
      // of raw literal text.
      final sinx = PlotExpression.compile(<MathNode>[
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'x')]),
      ]);
      final roots =
          findFeatures(
              sinx,
              -0.5,
              7,
            ).where((e) => e.kind == FeatureKind.root).map((e) => e.x).toList()
            ..sort();
      expect(roots.length, greaterThanOrEqualTo(3));
      expect(roots[0], closeTo(0, 1e-6));
      expect(roots[1], closeTo(math.pi, 1e-6));
      expect(roots[2], closeTo(2 * math.pi, 1e-6));
    });
  });
}
