import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
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

  group('θ runs from 0 to a full turn', () {
    double thetaAt(double x, double y) =>
        toCoordinates(CoordinateSystem.cylindrical, x, y, 0).$2;

    test('the turn starts on the positive x axis', () {
      expect(thetaAt(1, 0), 0);
      expect(thetaAt(-1, 0), closeTo(math.pi, 1e-15));
      expect(thetaAt(0, -1), closeTo(3 * math.pi / 2, 1e-15));
      expect(thetaAt(1, -1e-6), closeTo(2 * math.pi - 1e-6, 1e-12));
      // A negative zero used to put this at −π.
      expect(thetaAt(-1, -0.0), closeTo(math.pi, 1e-15));
      // Spherical θ is the same angle.
      expect(
        toCoordinates(CoordinateSystem.spherical, 0, -1, 1).$2,
        closeTo(3 * math.pi / 2, 1e-15),
      );
    });

    test('0 < θ < 3π/2 is three quadrants', () {
      // It was the upper half-plane while θ ran from −π to π.
      final PlotExpression wedge = PlotExpression.compile(<MathNode>[
        LiteralNode(text: '0<θ<3π/2'),
      ]);
      expect(wedge.isValid, isTrue, reason: wedge.error);
      expect(wedge.evaluate(1, 1), lessThan(0));
      expect(wedge.evaluate(-1, 1), lessThan(0));
      expect(wedge.evaluate(-1, -0.5), lessThan(0), reason: 'third quadrant');
      expect(wedge.evaluate(1, -0.5), greaterThan(0), reason: 'fourth');
    });
  });

  group('the sample point is converted, not the expression', () {
    // Read off the conversion itself: an equation such as ρ = 0 is read at
    // every address of a point (see [PlotExpression.evaluate]), so it no
    // longer reports the one coordinate alone.
    double coordinate(CoordinateSystem s, int i, double x, double y, double z) {
      final (double a, double b, double c) = toCoordinates(s, x, y, z);
      return <double>[a, b, c][i];
    }

    test('ρ is the distance from the origin', () {
      final PlotExpression rho = fn('ρ=0', CoordinateSystem.spherical);
      expect(rho.evaluate(3, 4, 0).abs(), closeTo(5, 1e-9));
      expect(
        coordinate(CoordinateSystem.spherical, 0, 1, 2, 2),
        closeTo(3, 1e-9),
      );
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
      const CoordinateSystem c = CoordinateSystem.cylindrical;
      expect(coordinate(c, 1, 1, 0, 0), closeTo(0, 1e-9));
      expect(coordinate(c, 1, 0, 1, 0), closeTo(math.pi / 2, 1e-9));
      expect(coordinate(c, 1, -1, 0, 0), closeTo(math.pi, 1e-9));
    });

    test('φ is measured down from the z axis', () {
      const CoordinateSystem s = CoordinateSystem.spherical;
      expect(
        coordinate(s, 2, 0, 0, 1),
        closeTo(0, 1e-9),
        reason: 'up the z axis',
      );
      expect(coordinate(s, 2, 1, 0, 0), closeTo(math.pi / 2, 1e-9));
      expect(coordinate(s, 2, 0, 0, -1), closeTo(math.pi, 1e-9));
    });

    test('the origin does not produce NaN', () {
      // φ is undefined there; seeding NaN would poison a whole surface.
      final PlotExpression phi = fn('φ=0', CoordinateSystem.spherical);
      expect(phi.evaluate(0, 0, 0).isFinite, isTrue);
    });

    test('φ keeps its digits next to the z axis', () {
      // acos(z/ρ) is flat at 1, so a point 1e-8 off the axis came back as
      // exactly zero. atan2 keeps full relative precision.
      for (final double d in <double>[1e-4, 1e-6, 1e-8, 1e-12]) {
        final (_, _, double above) = toCoordinates(
          CoordinateSystem.spherical,
          d,
          0,
          1,
        );
        final (_, _, double below) = toCoordinates(
          CoordinateSystem.spherical,
          d,
          0,
          -1,
        );
        expect(above, closeTo(math.atan(d), d * 1e-12));
        expect(below, closeTo(math.pi - math.atan(d), 1e-15));
      }
    });

    test('the converted point maps back to where it was sampled', () {
      // The round trip through the forward map is the whole contract: if it
      // fails anywhere, a shape is drawn somewhere other than where it is.
      const List<List<double>> points = <List<double>>[
        <double>[1, 2, 3],
        <double>[-2, 0.5, -1],
        <double>[0.3, -0.7, 0.2],
        <double>[-1, -1, 2],
        <double>[0, 0, -2],
        <double>[-3, 1e-12, 0],
      ];
      for (final List<double> p in points) {
        final (double r, double t, double z) = toCoordinates(
          CoordinateSystem.cylindrical,
          p[0],
          p[1],
          p[2],
        );
        expect(r * math.cos(t), closeTo(p[0], 1e-12));
        expect(r * math.sin(t), closeTo(p[1], 1e-12));
        expect(z, p[2]);

        final (double rho, double th, double ph) = toCoordinates(
          CoordinateSystem.spherical,
          p[0],
          p[1],
          p[2],
        );
        expect(rho * math.sin(ph) * math.cos(th), closeTo(p[0], 1e-12));
        expect(rho * math.sin(ph) * math.sin(th), closeTo(p[1], 1e-12));
        expect(rho * math.cos(ph), closeTo(p[2], 1e-12));
        expect(ph, inInclusiveRange(0, math.pi));
      }
    });
  });

  group('unit vectors are the right columns of the basis', () {
    VectorFieldParser field(List<MathNode> nodes) {
      final VectorFieldParser? f = VectorFieldParser.fromNodes(nodes);
      expect(f, isNotNull);
      expect(f!.error, isNull);
      return f;
    }

    // Unit vectors joined by +, each with an optional coefficient before it.
    VectorFieldParser sum(List<(String, String)> terms) {
      final List<MathNode> nodes = <MathNode>[];
      for (int i = 0; i < terms.length; i++) {
        final (String coefficient, String axis) = terms[i];
        final String sign = i > 0 ? '+' : '';
        if (sign.isNotEmpty || coefficient.isNotEmpty) {
          nodes.add(LiteralNode(text: '$sign$coefficient'));
        }
        nodes.add(UnitVectorNode(axis));
      }
      return field(nodes);
    }

    const List<List<double>> points = <List<double>>[
      <double>[1, 2, 3],
      <double>[-2, 0.5, -1],
      <double>[0.3, -0.7, 0.2],
      <double>[-1, -1, 2],
    ];

    void expectVector(
      (double, double, double) actual,
      List<double> expected, {
      String? reason,
    }) {
      expect(actual.$1, closeTo(expected[0], 1e-9), reason: reason);
      expect(actual.$2, closeTo(expected[1], 1e-9), reason: reason);
      expect(actual.$3, closeTo(expected[2], 1e-9), reason: reason);
    }

    double dot((double, double, double) a, (double, double, double) b) =>
        a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;

    (double, double, double) cross(
      (double, double, double) a,
      (double, double, double) b,
    ) => (
      a.$2 * b.$3 - a.$3 * b.$2,
      a.$3 * b.$1 - a.$1 * b.$3,
      a.$1 * b.$2 - a.$2 * b.$1,
    );

    test('ρ̂ points away from the origin, not away from the z axis', () {
      // It used to be read as r̂, which is flat: on the z axis it pointed
      // along x instead of up.
      final VectorFieldParser rhoHat = sum(<(String, String)>[('', 'ρ')]);
      expectVector(rhoHat.evaluate(0, 0, 1), <double>[0, 0, 1]);
      expectVector(rhoHat.evaluate(0, 0, -1), <double>[0, 0, -1]);
      expectVector(rhoHat.evaluate(1, 0, 1), <double>[
        math.sqrt1_2,
        0,
        math.sqrt1_2,
      ]);
      expect(rhoHat.is3D, isTrue, reason: 'ρ̂ has a z component');
    });

    test('φ̂ points down the meridian', () {
      // It used to be read as ẑ, so on the equator it pointed up where it
      // points down.
      final VectorFieldParser phiHat = sum(<(String, String)>[('', 'φ')]);
      expectVector(phiHat.evaluate(1, 0, 0), <double>[0, 0, -1]);
      expectVector(phiHat.evaluate(0, 2, 0), <double>[0, 0, -1]);
      expectVector(phiHat.evaluate(1, 0, 1), <double>[
        math.sqrt1_2,
        0,
        -math.sqrt1_2,
      ]);
    });

    test('ρ ρ̂ and r r̂ + z ẑ are both the position vector', () {
      final VectorFieldParser spherical = sum(<(String, String)>[('ρ', 'ρ')]);
      final VectorFieldParser cylindrical = sum(<(String, String)>[
        ('r', 'r'),
        ('z', 'z'),
      ]);
      for (final List<double> p in points) {
        expectVector(spherical.evaluate(p[0], p[1], p[2]), p, reason: '$p');
        expectVector(cylindrical.evaluate(p[0], p[1], p[2]), p, reason: '$p');
      }
    });

    test('r θ̂ is the rotation field −y x̂ + x ŷ, in either system', () {
      // θ̂ is the same vector in cylindrical and spherical.
      final VectorFieldParser cylindrical = sum(<(String, String)>[('r', 'θ')]);
      final VectorFieldParser spherical = sum(<(String, String)>[
        ('ρ', 'θ'),
        ('0', 'ρ'),
      ]);
      for (final List<double> p in points) {
        expectVector(cylindrical.evaluate(p[0], p[1], p[2]), <double>[
          -p[1],
          p[0],
          0,
        ]);
        final double r = math.sqrt(p[0] * p[0] + p[1] * p[1]);
        final double rho = math.sqrt(r * r + p[2] * p[2]);
        expectVector(spherical.evaluate(p[0], p[1], p[2]), <double>[
          -p[1] * rho / r,
          p[0] * rho / r,
          0,
        ]);
      }
    });

    test('each local basis is orthonormal and right-handed', () {
      final VectorFieldParser rHat = sum(<(String, String)>[('', 'r')]);
      final VectorFieldParser thetaHat = sum(<(String, String)>[('', 'θ')]);
      final VectorFieldParser zHat = sum(<(String, String)>[('', 'z')]);
      final VectorFieldParser rhoHat = sum(<(String, String)>[('', 'ρ')]);
      final VectorFieldParser phiHat = sum(<(String, String)>[('', 'φ')]);

      for (final List<double> p in points) {
        final r = rHat.evaluate(p[0], p[1], p[2]);
        final t = thetaHat.evaluate(p[0], p[1], p[2]);
        final z = zHat.evaluate(p[0], p[1], p[2]);
        final rho = rhoHat.evaluate(p[0], p[1], p[2]);
        final phi = phiHat.evaluate(p[0], p[1], p[2]);

        for (final v in <(double, double, double)>[r, t, z, rho, phi]) {
          expect(dot(v, v), closeTo(1, 1e-12));
        }
        expect(dot(r, t), closeTo(0, 1e-12));
        expect(dot(rho, t), closeTo(0, 1e-12));
        expect(dot(rho, phi), closeTo(0, 1e-12));
        expect(dot(phi, t), closeTo(0, 1e-12));

        // (r̂, θ̂, ẑ) and (ρ̂, φ̂, θ̂) are the right-handed orders.
        expectVector(cross(r, t), <double>[z.$1, z.$2, z.$3]);
        expectVector(cross(rho, phi), <double>[t.$1, t.$2, t.$3]);
      }
    });

    test('repeated unit vectors add up rather than replace each other', () {
      // Each axis used to be a single slot, so the last term won: 2x̂ + 3x̂
      // drew 3x̂ and x̂ + r̂ silently lost its x̂.
      expectVector(
        sum(<(String, String)>[('2', 'x'), ('3', 'x')]).evaluate(0, 0),
        <double>[5, 0, 0],
      );
      expectVector(
        sum(<(String, String)>[('', 'x'), ('', 'r')]).evaluate(0, 1),
        <double>[1, 1, 0],
      );
      expectVector(
        sum(<(String, String)>[('', 'ρ'), ('', 'z')]).evaluate(0, 0, 1),
        <double>[0, 0, 2],
        reason: 'ẑ stays ẑ beside a spherical unit vector',
      );
    });

    test('the order of the terms does not matter', () {
      final VectorFieldParser a = sum(<(String, String)>[
        ('', 'ρ'),
        ('2', 'θ'),
        ('3', 'φ'),
      ]);
      final VectorFieldParser b = sum(<(String, String)>[
        ('3', 'φ'),
        ('2', 'θ'),
        ('', 'ρ'),
      ]);
      for (final List<double> p in points) {
        final (double, double, double) va = a.evaluate(p[0], p[1], p[2]);
        expectVector(b.evaluate(p[0], p[1], p[2]), <double>[
          va.$1,
          va.$2,
          va.$3,
        ]);
      }
    });

    test('a negative term flips its share of every component', () {
      final VectorFieldParser f = field(<MathNode>[
        LiteralNode(text: '-'),
        UnitVectorNode('φ'),
      ]);
      expectVector(f.evaluate(1, 0, 0), <double>[0, 0, 1]);
    });
  });

  group('a line with no = reads the way its own system does', () {
    PlotExpression compile(List<MathNode> nodes) =>
        PlotExpression.compile(nodes);
    MathNode trig(String fn, String arg) =>
        TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: arg)]);

    test('a bare f(θ) is the polar curve r = f(θ)', () {
      // As a height it was a step: f(0) right of the origin, f(π) left of it.
      final PlotExpression e = compile(<MathNode>[
        LiteralNode(text: '1+'),
        trig('cos', 'θ'),
      ]);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isLevelSet, isTrue);
      expect(e.isImplicitSurface, isFalse, reason: 'a curve in the plane');
      expect(e.evaluate(2, 0).abs(), lessThan(1e-9), reason: 'θ = 0, r = 2');
      expect(e.evaluate(0, 1).abs(), lessThan(1e-9), reason: 'θ = π/2, r = 1');
      expect(e.evaluate(0, -1).abs(), lessThan(1e-9));
      expect(e.evaluate(-2, 0).abs(), greaterThan(1));
    });

    test('a bare f(θ, φ) is the surface ρ = f(θ, φ)', () {
      // 2 cos φ is the unit sphere resting on the origin, centred at z = 1.
      final PlotExpression e = compile(<MathNode>[
        LiteralNode(text: '2'),
        trig('cos', 'φ'),
      ]);
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isImplicitSurface, isTrue);
      expect(e.evaluate(0, 0, 2).abs(), lessThan(1e-9));
      expect(e.evaluate(1, 0, 1).abs(), lessThan(1e-9));
      expect(e.evaluate(0, -1, 1).abs(), lessThan(1e-9));
      expect(e.evaluate(0, 0, 1), lessThan(0), reason: 'the centre is inside');
    });

    test('a bare line with ρ in it is refused, not sampled at z = 0', () {
      // ρ depends on z, so as a height z would be on both sides.
      for (final String s in <String>['ρ', 'ρθ', 'ρ+1']) {
        final PlotExpression e = compile(<MathNode>[LiteralNode(text: s)]);
        expect(e.isValid, isFalse, reason: s);
        expect(e.error, contains('ρ ='));
      }
    });

    test('a bare line in r is still a height', () {
      // z = rθ is a surface over the plane, as x·y is; r² on its own is
      // still read as a height, the way x² is.
      final PlotExpression rTheta = compile(<MathNode>[
        LiteralNode(text: 'rθ'),
      ]);
      expect(rTheta.isLevelSet, isFalse);
      expect(rTheta.isSurface, isTrue);
      final PlotExpression r = compile(<MathNode>[LiteralNode(text: 'r^2')]);
      expect(r.isLevelSet, isFalse);
      expect(r.evaluate(3, 4), closeTo(25, 1e-9));
    });

    test('a vector component is a value, never rewritten into a curve', () {
      final VectorFieldParser f =
          VectorFieldParser.fromNodes(<MathNode>[
            trig('cos', 'θ'),
            UnitVectorNode('x'),
          ])!;
      expect(f.error, isNull);
      expect(f.evaluate(1, 0).$1, closeTo(1, 1e-12));
      expect(f.evaluate(0, 1).$1, closeTo(0, 1e-12));
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
