import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/utils/coordinate_system.dart';

/// Plotting an expression written in another coordinate system.
///
/// Every renderer walks a Cartesian lattice, so a polar or spherical cell is
/// handled by converting the sample point rather than rewriting the
/// expression. That means the existing curve tracer, height sampler, marching
/// squares and marching tetrahedra all work on it unchanged.
void main() {
  mixedLines();
  PlotExpression fn(String s, CoordinateSystem system) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)], system: system);

  group('spherical', () {
    test('ρ² = 1 is the unit sphere', () {
      final e = fn('ρ^2=1', CoordinateSystem.spherical);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isLevelSet, isTrue);

      // Vanishes exactly on the unit sphere...
      for (final p in <List<double>>[
        <double>[1, 0, 0],
        <double>[0, 1, 0],
        <double>[0, 0, 1],
        <double>[0.5773502692, 0.5773502692, 0.5773502692],
      ]) {
        expect(e.evaluate(p[0], p[1], p[2]).abs(), lessThan(1e-6));
      }
      // ...and is signed either side of it.
      expect(e.evaluate(0.5, 0, 0), lessThan(0));
      expect(e.evaluate(2, 0, 0), greaterThan(0));
    });

    test('φ is the polar angle, measured down from z', () {
      final e = fn('φ', CoordinateSystem.spherical);
      expect(e.isValid, isTrue, reason: e.error);
      // On the +z axis φ = 0; in the xy-plane φ = π/2; on −z it is π.
      expect(e.evaluate(0, 0, 1), closeTo(0, 1e-9));
      expect(e.evaluate(1, 0, 0), closeTo(1.5707963268, 1e-9));
      expect(e.evaluate(0, 0, -1), closeTo(3.1415926536, 1e-9));
    });

    test('φ is no longer the golden ratio', () {
      expect(fn('φ', CoordinateSystem.spherical).evaluate(0, 0, 1), 0);
    });
  });

  group('cylindrical', () {
    test('r is the distance from the z axis, not from the origin', () {
      final e = fn('r', CoordinateSystem.cylindrical);
      expect(e.evaluate(3, 4, 99), closeTo(5, 1e-9));
    });

    test('r = 1 + cos(θ) is a cardioid', () {
      // A curve the Cartesian form cannot express in one equation, traced by
      // the same marching squares that draws any other implicit curve.
      final e = PlotExpression.compile(<MathNode>[
        LiteralNode(text: 'r-1-'),
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'θ')]),
      ], system: CoordinateSystem.cylindrical);
      expect(e.isValid, isTrue, reason: e.error);

      // θ = 0 gives r = 2; θ = π gives r = 0; θ = π/2 gives r = 1.
      expect(e.evaluate(2, 0).abs(), lessThan(1e-9));
      expect(e.evaluate(0, 1).abs(), lessThan(1e-9));
      expect(e.evaluate(-1, 0).abs(), greaterThan(0.5));
    });
  });

  group('the systems stay separate', () {
    test('the system passed in is only a fallback', () {
      // A line is read in whichever system its symbols belong to, so asking
      // for spherical and then writing x gives a Cartesian line, not an
      // error. Only the symbols decide.
      final e = fn('x+1', CoordinateSystem.spherical);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.system, CoordinateSystem.cartesian);
      expect(
        fn('ρ', CoordinateSystem.cartesian).system,
        CoordinateSystem.spherical,
      );
    });

    test('cartesian is untouched by any of this', () {
      final e = fn('x^2+y^2+z^2=1', CoordinateSystem.cartesian);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.evaluate(1, 0, 0).abs(), lessThan(1e-9));
    });
  });
}

/// One plot, several lines, each in whichever system it is written in.
///
/// Everything converts to Cartesian before it is drawn, so the systems only
/// have to agree within a line — never across the plot.
void mixedLines() {
  group('lines choose their own system', () {
    List<PlotExpression> lines(List<String> exprs) {
      final nodes = <MathNode>[];
      for (int i = 0; i < exprs.length; i++) {
        if (i > 0) nodes.add(NewlineNode());
        nodes.add(LiteralNode(text: exprs[i]));
      }
      return PlotExpression.compileAll(nodes);
    }

    test('x + y on one line and r on the next are both fine', () {
      final out = lines(<String>['x+y', 'r']);
      expect(out, hasLength(2));
      for (final e in out) {
        expect(e.isValid, isTrue, reason: e.error);
      }
      expect(out[0].system, CoordinateSystem.cartesian);
      expect(out[1].system, CoordinateSystem.cylindrical);

      // Each samples by its own rule at the same Cartesian point.
      expect(out[0].evaluate(3, 4), closeTo(7, 1e-9));
      expect(out[1].evaluate(3, 4), closeTo(5, 1e-9));
    });

    test('a spherical line sits happily beside a cartesian one', () {
      final out = lines(<String>['x^2', 'ρ^2=1']);
      expect(out[0].system, CoordinateSystem.cartesian);
      expect(out[1].system, CoordinateSystem.spherical);
      expect(out[1].isValid, isTrue, reason: out[1].error);
    });

    test('mixing inside one line is refused, and says which symbols', () {
      final e = PlotExpression.compile(<MathNode>[LiteralNode(text: 'x+r')]);
      expect(e.isValid, isFalse);
      expect(e.error, contains('x'));
      expect(e.error, contains('r'));
      expect(e.error, contains('mix'));
    });

    test('shared symbols do not count as mixing', () {
      // θ means the same azimuth in cylindrical and spherical, and z the same
      // height in Cartesian and cylindrical, so neither is ambiguous in a way
      // that changes the numbers.
      expect(
        PlotExpression.compile(<MathNode>[LiteralNode(text: 'r+θ')]).isValid,
        isTrue,
      );
      expect(
        PlotExpression.compile(<MathNode>[LiteralNode(text: 'ρ+θ')]).isValid,
        isTrue,
      );
    });

    test('a spherical level set is a surface, not a flat curve', () {
      // ρ, θ and φ only describe 3D space, so ρ = 1 is a sphere even though
      // it never mentions the third symbol.
      final e = PlotExpression.compile(<MathNode>[LiteralNode(text: 'ρ^2=1')]);
      expect(e.isLevelSet, isTrue);
      expect(e.isImplicitSurface, isTrue);
    });
  });
}
