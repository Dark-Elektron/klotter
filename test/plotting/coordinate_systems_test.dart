import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/utils/coordinate_system.dart';

/// Expressions written in polar, cylindrical or spherical symbols.
///
/// Nothing that draws knows about them. Every renderer walks a Cartesian
/// lattice, and an expression in another system is handled by converting the
/// *sample point* rather than rewriting the expression — so ρ = 1 comes out as
/// the unit sphere through exactly the code that draws any other level set.
void main() {
  PlotExpression fn(String s, CoordinateSystem system) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)], system: system);

  group('symbols belong to one system', () {
    test('ISO keeps r and ρ apart', () {
      // Cylindrical r is the distance from the z axis; spherical ρ is the
      // distance from the origin. Different quantities, different letters.
      expect(CoordinateSystem.cylindrical.variables, <String>['r', 'θ', 'z']);
      expect(CoordinateSystem.spherical.variables, <String>['ρ', 'θ', 'φ']);
      expect(CoordinateSystem.cartesian.variables, <String>['x', 'y', 'z']);
    });

    test('a line is read in whichever system its symbols belong to', () {
      // The plot no longer has a system; each line does. One plot can carry
      // x + y on one line and r on the next, because both convert to
      // Cartesian before anything is drawn.
      expect(
        PlotExpression.compile(<MathNode>[LiteralNode(text: 'r')]).system,
        CoordinateSystem.cylindrical,
      );
      expect(
        PlotExpression.compile(<MathNode>[LiteralNode(text: 'x')]).system,
        CoordinateSystem.cartesian,
      );
    });

    test('mixing systems inside one line is refused', () {
      final e = PlotExpression.compile(<MathNode>[LiteralNode(text: 'x+r')]);
      expect(e.isValid, isFalse);
      expect(e.error, contains('mix'));
    });

    test('φ is a variable, not the golden ratio', () {
      // Nothing in the app could produce that constant, so the symbol was free
      // for the spherical angle ISO gives it.
      final PlotExpression e = fn('φ', CoordinateSystem.spherical);
      expect(e.isValid, isTrue);
      expect(e.variables, contains('φ'));
    });
  });

  group('the sample point is converted, not the expression', () {
    test('ρ is the distance from the origin', () {
      final PlotExpression rho = fn('ρ', CoordinateSystem.spherical);
      expect(rho.evaluate(3, 4, 0), closeTo(5, 1e-9));
      expect(rho.evaluate(1, 2, 2), closeTo(3, 1e-9));
      expect(rho.evaluate(0, 0, 0), closeTo(0, 1e-9));
    });

    test('r is the distance from the z axis, and ignores z', () {
      final PlotExpression r = fn('r', CoordinateSystem.cylindrical);
      expect(r.evaluate(3, 4, 0), closeTo(5, 1e-9));
      expect(
        r.evaluate(3, 4, 99),
        closeTo(5, 1e-9),
        reason: 'cylindrical r does not climb with z',
      );
    });

    test('θ is measured from the x axis', () {
      final PlotExpression theta = fn('θ', CoordinateSystem.cylindrical);
      expect(theta.evaluate(1, 0, 0), closeTo(0, 1e-9));
      expect(theta.evaluate(0, 1, 0), closeTo(math.pi / 2, 1e-9));
      expect(theta.evaluate(-1, 0, 0), closeTo(math.pi, 1e-9));
    });

    test('φ is measured down from the z axis', () {
      final PlotExpression phi = fn('φ', CoordinateSystem.spherical);
      expect(phi.evaluate(0, 0, 1), closeTo(0, 1e-9), reason: 'up the z axis');
      expect(phi.evaluate(1, 0, 0), closeTo(math.pi / 2, 1e-9));
      expect(phi.evaluate(0, 0, -1), closeTo(math.pi, 1e-9));
    });

    test('the origin does not produce NaN', () {
      // φ is undefined there; seeding NaN would poison a whole surface.
      final PlotExpression phi = fn('φ', CoordinateSystem.spherical);
      expect(phi.evaluate(0, 0, 0).isFinite, isTrue);
    });
  });

  group('the shapes come out right', () {
    test('ρ = 1 is the unit sphere', () {
      final PlotExpression e = fn('ρ=1', CoordinateSystem.spherical);
      expect(e.isValid, isTrue);
      expect(e.isLevelSet, isTrue, reason: 'an equation, so a level set');

      // Zero exactly on the surface, and opposite signs either side of it —
      // which is what marching tetrahedra needs to find the shape.
      for (final List<double> p in <List<double>>[
        <double>[1, 0, 0],
        <double>[0, 1, 0],
        <double>[0, 0, 1],
        <double>[0.5773502692, 0.5773502692, 0.5773502692],
      ]) {
        expect(e.evaluate(p[0], p[1], p[2]).abs(), lessThan(1e-6));
      }
      expect(e.evaluate(0, 0, 0), lessThan(0), reason: 'inside');
      expect(e.evaluate(2, 0, 0), greaterThan(0), reason: 'outside');
    });

    test('ρ² = 1 is the same sphere', () {
      final PlotExpression e = fn('ρ^2=1', CoordinateSystem.spherical);
      expect(e.isValid, isTrue);
      expect(e.evaluate(1, 0, 0).abs(), lessThan(1e-6));
      expect(e.evaluate(0, 0.6, 0.8).abs(), lessThan(1e-6));
      expect(e.evaluate(0, 0, 0), lessThan(0));
    });

    test('it agrees with the Cartesian way of writing it', () {
      final PlotExpression spherical = fn('ρ=1', CoordinateSystem.spherical);
      final PlotExpression cartesian = fn(
        'x^2+y^2+z^2=1',
        CoordinateSystem.cartesian,
      );
      // Different functions, but they vanish on the same set.
      for (final List<double> p in <List<double>>[
        <double>[1, 0, 0],
        <double>[0, 0, 1],
        <double>[0.6, 0.8, 0],
      ]) {
        expect(spherical.evaluate(p[0], p[1], p[2]).abs(), lessThan(1e-6));
        expect(cartesian.evaluate(p[0], p[1], p[2]).abs(), lessThan(1e-6));
      }
    });

    test('r = 1 is a cylinder, not a sphere', () {
      final PlotExpression e = fn('r=1', CoordinateSystem.cylindrical);
      expect(e.evaluate(1, 0, 0).abs(), lessThan(1e-6));
      expect(
        e.evaluate(1, 0, 5).abs(),
        lessThan(1e-6),
        reason: 'the surface runs the length of the z axis',
      );
      expect(
        e.evaluate(0, 0, 1),
        lessThan(0),
        reason: 'a point on the axis is inside it, however high',
      );
    });

    test('r = 1 + cos(θ) is a cardioid', () {
      // The classic polar curve, drawn by the same marching-squares code as
      // any other implicit curve. At θ = 0 it reaches r = 2; at θ = π it
      // closes at the origin.
      final PlotExpression e = PlotExpression.compile(<MathNode>[
        LiteralNode(text: 'r='),
        LiteralNode(text: '1+'),
        TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'θ')]),
      ], system: CoordinateSystem.cylindrical);
      expect(e.isValid, isTrue, reason: e.error);

      expect(e.evaluate(2, 0, 0).abs(), lessThan(1e-6), reason: 'θ=0, r=2');
      expect(e.evaluate(0, 1, 0).abs(), lessThan(1e-6), reason: 'θ=π/2, r=1');
      // Off the curve it does not vanish.
      expect(e.evaluate(0.5, 0, 0).abs(), greaterThan(0.1));
    });
  });
}
