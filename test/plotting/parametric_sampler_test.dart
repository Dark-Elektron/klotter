import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';

/// Sweeping a parametric expression into points.
void main() {
  VectorFieldParser circle() =>
      VectorFieldParser.fromNodes(<MathNode>[
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
        UnitVectorNode('y'),
      ])!;

  group('a curve', () {
    test('cos(u)x̂ + sin(u)ŷ traces the unit circle', () {
      final pts = sampleParametricCurve(circle());
      expect(pts.length, parametricCurveSteps + 1);

      for (final p in pts) {
        expect(p, isNotNull);
        // Every point is one unit from the origin.
        expect(
          math.sqrt(p!.x * p.x + p.y * p.y),
          closeTo(1, 1e-9),
          reason: 'off the circle at (${p.x}, ${p.y})',
        );
      }
    });

    test('it closes, because the default sweep is a full turn', () {
      final pts = sampleParametricCurve(circle());
      expect(pts.first!.x, closeTo(pts.last!.x, 1e-9));
      expect(pts.first!.y, closeTo(pts.last!.y, 1e-9));
    });

    test('a missing component is zero, not a gap', () {
      // No ẑ term, so the circle lies in the plane z = 0 rather than being
      // discarded as undefined.
      for (final p in sampleParametricCurve(circle())) {
        expect(p!.z, 0);
      }
    });

    test('half a turn gives half the circle', () {
      final pts = sampleParametricCurve(circle(), u: (min: 0.0, max: math.pi));
      // y never goes negative on the upper half.
      for (final p in pts) {
        expect(p!.y, greaterThan(-1e-9));
      }
    });

    test('an undefined point comes back as a break, not a jump', () {
      // 1/u is undefined at u = 0, and joining across it would draw a line
      // through somewhere the curve never goes.
      final f =
          VectorFieldParser.fromNodes(<MathNode>[
            LiteralNode(text: '1/u'),
            UnitVectorNode('x'),
          ])!;
      final pts = sampleParametricCurve(f, u: (min: -1.0, max: 1.0));
      expect(pts.any((p) => p == null), isTrue);
    });
  });

  group('a surface', () {
    test('sweeps both parameters into a grid', () {
      final f =
          VectorFieldParser.fromNodes(<MathNode>[
            LiteralNode(text: 'u'),
            UnitVectorNode('x'),
            LiteralNode(text: '+v'),
            UnitVectorNode('y'),
          ])!;
      expect(f.isParametricSurface, isTrue);

      final grid = sampleParametricSurface(
        f,
        u: (min: 0.0, max: 1.0),
        v: (min: 0.0, max: 2.0),
        steps: 4,
      );
      expect(grid.length, 5);
      expect(grid.first.length, 5);
      // The corner at (u, v) = (1, 2).
      expect(grid.last.last!.x, closeTo(1, 1e-9));
      expect(grid.last.last!.y, closeTo(2, 1e-9));
    });
  });

  group('extent', () {
    test('measures how far the path reaches', () {
      final e = parametricExtent(sampleParametricCurve(circle()));
      expect(e, isNotNull);
      expect(e!.x, closeTo(1, 1e-6));
      expect(e.y, closeTo(1, 1e-6));
      expect(e.z, 0);
    });

    test('is null when nothing is ever defined', () {
      expect(parametricExtent(<ParametricPoint?>[null, null]), isNull);
    });
  });
}
