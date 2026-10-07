import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';

/// The inverse trigonometric and hyperbolic functions over the complex plane.
///
/// They returned NaN, so asin(z̲) and the rest drew a blank plane. Each is now
/// the principal value: the branch meant whenever the function is written
/// without qualification.
void main() {
  // The forward functions, written out independently here so the round trips
  // below check the inverses against something they do not share code with.
  double sh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  double ch(double x) => (math.exp(x) + math.exp(-x)) / 2;
  Complex sin(Complex z) =>
      Complex(math.sin(z.real) * ch(z.imag), math.cos(z.real) * sh(z.imag));
  Complex cos(Complex z) =>
      Complex(math.cos(z.real) * ch(z.imag), -math.sin(z.real) * sh(z.imag));
  Complex sinh(Complex z) =>
      Complex(sh(z.real) * math.cos(z.imag), ch(z.real) * math.sin(z.imag));
  Complex cosh(Complex z) =>
      Complex(ch(z.real) * math.cos(z.imag), sh(z.real) * math.sin(z.imag));
  Complex tan(Complex z) => sin(z) / cos(z);
  Complex tanh(Complex z) => sinh(z) / cosh(z);

  void expectNear(Complex actual, Complex expected, {double tol = 1e-12}) {
    final double err = (actual - expected).magnitude;
    expect(
      err,
      lessThanOrEqualTo(tol * (1 + expected.magnitude)),
      reason: 'got $actual, expected $expected',
    );
  }

  const Complex onePlusI = Complex(1, 1);

  test('each agrees with the reference value at 1 + i', () {
    expectNear(
      complexAsin(onePlusI),
      const Complex(0.6662394324925153, 1.0612750619050357),
    );
    expectNear(
      complexAcos(onePlusI),
      const Complex(0.9045568943023813, -1.0612750619050357),
    );
    expectNear(
      complexAtan(onePlusI),
      const Complex(1.0172219678978514, 0.4023594781085251),
    );
    expectNear(
      complexAsinh(onePlusI),
      const Complex(1.0612750619050357, 0.6662394324925153),
    );
    expectNear(
      complexAcosh(onePlusI),
      const Complex(1.0612750619050357, 0.9045568943023813),
    );
    expectNear(
      complexAtanh(onePlusI),
      const Complex(0.4023594781085251, 1.0172219678978514),
    );
  });

  /// Points spread over the plane, cuts and all. A round trip f(f⁻¹(z)) = z
  /// holds whichever branch was taken, so it checks the formulas everywhere;
  /// the range test after it checks that the branch is the principal one.
  final math.Random random = math.Random(7);
  final List<Complex> points = <Complex>[
    for (int i = 0; i < 400; i++)
      Complex(random.nextDouble() * 6 - 3, random.nextDouble() * 6 - 3),
  ];

  test('applying the function undoes the inverse', () {
    for (final Complex z in points) {
      expectNear(sin(complexAsin(z)), z, tol: 1e-9);
      expectNear(cos(complexAcos(z)), z, tol: 1e-9);
      expectNear(sinh(complexAsinh(z)), z, tol: 1e-9);
      expectNear(cosh(complexAcosh(z)), z, tol: 1e-9);
      // Poles at ±i and ±1, where the inverses are infinite.
      if ((z - const Complex(0, 1)).magnitude > 1e-3 &&
          (z - const Complex(0, -1)).magnitude > 1e-3) {
        expectNear(tan(complexAtan(z)), z, tol: 1e-9);
      }
      if ((z - const Complex(1, 0)).magnitude > 1e-3 &&
          (z - const Complex(-1, 0)).magnitude > 1e-3) {
        expectNear(tanh(complexAtanh(z)), z, tol: 1e-9);
      }
    }
  });

  test('each lands in its principal range', () {
    const double half = math.pi / 2 + 1e-12;
    for (final Complex z in points) {
      expect(complexAsin(z).real.abs(), lessThanOrEqualTo(half));
      final double acosRe = complexAcos(z).real;
      expect(acosRe, inInclusiveRange(-1e-12, math.pi + 1e-12));
      expect(complexAtan(z).real.abs(), lessThanOrEqualTo(half));
      expect(complexAsinh(z).imag.abs(), lessThanOrEqualTo(half));
      final Complex acosh = complexAcosh(z);
      expect(acosh.real, greaterThanOrEqualTo(-1e-12));
      expect(acosh.imag.abs(), lessThanOrEqualTo(math.pi + 1e-12));
      expect(complexAtanh(z).imag.abs(), lessThanOrEqualTo(half));
    }
  });

  test('on the real line inside their domains they are the real functions', () {
    for (final double x in <double>[-0.9, -0.3, 0, 0.4, 0.95]) {
      expectNear(complexAsin(Complex(x, 0)), Complex(math.asin(x), 0));
      expectNear(complexAcos(Complex(x, 0)), Complex(math.acos(x), 0));
      expectNear(
        complexAtanh(Complex(x, 0)),
        Complex(0.5 * math.log((1 + x) / (1 - x)), 0),
      );
    }
    for (final double x in <double>[-50, -2, 0.5, 3, 80]) {
      expectNear(complexAtan(Complex(x, 0)), Complex(math.atan(x), 0));
      expectNear(
        complexAsinh(Complex(x, 0)),
        Complex(math.log(x.abs() + math.sqrt(x * x + 1)) * x.sign, 0),
      );
    }
    for (final double x in <double>[1, 1.5, 10, 1e4]) {
      expectNear(
        complexAcosh(Complex(x, 0)),
        Complex(math.log(x + math.sqrt(x * x - 1)), 0),
      );
    }
  });

  test('tiny and huge arguments keep their value', () {
    expectNear(
      complexAsin(const Complex(0, 1e-10)),
      const Complex(0, 1e-10),
      tol: 1e-15,
    );
    expectNear(
      complexAtan(const Complex(1e-10, 0)),
      const Complex(1e-10, 0),
      tol: 1e-15,
    );
    // ln(2e8): log(z + √(z² + 1)) cancels to log 0 here unless worked out on
    // the other side of the origin.
    expectNear(
      complexAsinh(const Complex(-1e8, 0)),
      const Complex(-19.113827924512311, 0),
    );
    final Complex far = complexAsin(const Complex(0, 1e9));
    expect(far.real.isFinite && far.imag.isFinite, isTrue);
  });

  group('in a plot of z̲', () {
    PlotExpression of(String function) => PlotExpression.compile(<MathNode>[
      TrigNode(function: function, argument: <MathNode>[ComplexVariableNode()]),
    ]);

    test('every inverse is drawn rather than left blank', () {
      for (final String f in <String>[
        'asin',
        'acos',
        'atan',
        'asinh',
        'acosh',
        'atanh',
      ]) {
        final PlotExpression line = of(f);
        expect(line.error, isNull, reason: f);
        expect(line.isComplex, isTrue, reason: f);
        final Complex v = line.evaluateComplex(1, 1);
        expect(
          v.real.isFinite && v.imag.isFinite,
          isTrue,
          reason: '$f(1 + i) = $v',
        );
      }
    });

    test('and has the value at the point', () {
      expectNear(
        of('asin').evaluateComplex(1, 1),
        const Complex(0.6662394324925153, 1.0612750619050357),
      );
      expectNear(
        of('atanh').evaluateComplex(1, 1),
        const Complex(0.4023594781085251, 1.0172219678978514),
      );
    });
  });
}
