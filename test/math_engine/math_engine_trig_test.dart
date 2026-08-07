import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'dart:math';

void main() {
  // Helper constants for common values
  final sqrt2Over2 = sqrt(2) / 2; // ≈ 0.7071067811865476
  final sqrt3Over2 = sqrt(3) / 2; // ≈ 0.8660254037844386

  // Tolerance for floating point comparisons
  const double tolerance = 1e-5;

  /// Helper function to parse and evaluate, returning double
  double? evalToDouble(String expr) {
    String? result = MathSolverNew.evaluate(expr);
    if (result == null || result.isEmpty) return null;
    final normalized = result
        .replaceAll('\u1D07', 'E') // small-caps E scientific notation
        .replaceAll('\u2212', '-') // unicode minus
        .replaceAll(',', '');
    return double.tryParse(normalized);
  }

  /// Helper to check approximate equality
  void expectApprox(double? actual, double expected, {double eps = tolerance}) {
    expect(actual, isNotNull);
    expect(
      (actual! - expected).abs(),
      lessThan(eps),
      reason: 'Expected $expected but got $actual',
    );
  }

  group('Setup', () {
    // setUp(() {
    //   // Reset to default settings before each test
    //   MathSolverNew.setPrecision(10);
    //   MathSolverNew.setAngleMode(AngleMode.radians);
    // });
  });

  // ============================================================
  // SINE FUNCTION TESTS
  // ============================================================

  group('Sine Function - Degree Input with ° Symbol', () {
    test('sin(0°) = 0', () {
      expectApprox(evalToDouble('sin(0°)'), 0);
    });

    test('sin(30°) = 0.5', () {
      expectApprox(evalToDouble('sin(30°)'), 0.5);
    });

    test('sin(45°) = √2/2', () {
      expectApprox(evalToDouble('sin(45°)'), sqrt2Over2);
    });

    test('sin(60°) = √3/2', () {
      expectApprox(evalToDouble('sin(60°)'), sqrt3Over2);
    });

    test('sin(90°) = 1', () {
      expectApprox(evalToDouble('sin(90°)'), 1);
    });

    test('sin(120°) = √3/2', () {
      expectApprox(evalToDouble('sin(120°)'), sqrt3Over2);
    });

    test('sin(135°) = √2/2 [THE FAILING CASE]', () {
      expectApprox(evalToDouble('sin(135°)'), sqrt2Over2);
    });

    test('sin(150°) = 0.5', () {
      expectApprox(evalToDouble('sin(150°)'), 0.5);
    });

    test('sin(180°) = 0', () {
      expectApprox(evalToDouble('sin(180°)'), 0);
    });

    test('sin(210°) = -0.5', () {
      expectApprox(evalToDouble('sin(210°)'), -0.5);
    });

    test('sin(225°) = -√2/2', () {
      expectApprox(evalToDouble('sin(225°)'), -sqrt2Over2);
    });

    test('sin(240°) = -√3/2', () {
      expectApprox(evalToDouble('sin(240°)'), -sqrt3Over2);
    });

    test('sin(270°) = -1', () {
      expectApprox(evalToDouble('sin(270°)'), -1);
    });

    test('sin(300°) = -√3/2', () {
      expectApprox(evalToDouble('sin(300°)'), -sqrt3Over2);
    });

    test('sin(315°) = -√2/2', () {
      expectApprox(evalToDouble('sin(315°)'), -sqrt2Over2);
    });

    test('sin(330°) = -0.5', () {
      expectApprox(evalToDouble('sin(330°)'), -0.5);
    });

    test('sin(360°) = 0', () {
      expectApprox(evalToDouble('sin(360°)'), 0);
    });
  });

  group('Sine Function - Negative Degree Angles', () {
    test('sin(-30°) = -0.5', () {
      expectApprox(evalToDouble('sin(-30°)'), -0.5);
    });

    test('sin(-45°) = -√2/2', () {
      expectApprox(evalToDouble('sin(-45°)'), -sqrt2Over2);
    });

    test('sin(-90°) = -1', () {
      expectApprox(evalToDouble('sin(-90°)'), -1);
    });

    test('sin(-180°) = 0', () {
      expectApprox(evalToDouble('sin(-180°)'), 0);
    });

    test('sin(-270°) = 1', () {
      expectApprox(evalToDouble('sin(-270°)'), 1);
    });
  });

  group('Sine Function - Large Angles (Periodicity)', () {
    test('sin(390°) = sin(30°) = 0.5', () {
      expectApprox(evalToDouble('sin(390°)'), 0.5);
    });

    test('sin(405°) = sin(45°) = √2/2', () {
      expectApprox(evalToDouble('sin(405°)'), sqrt2Over2);
    });

    test('sin(720°) = 0', () {
      expectApprox(evalToDouble('sin(720°)'), 0);
    });

    test('sin(810°) = 1', () {
      expectApprox(evalToDouble('sin(810°)'), 1);
    });

    test('sin(-390°) = -0.5', () {
      expectApprox(evalToDouble('sin(-390°)'), -0.5);
    });
  });

  group('Sine Function - Radian Input', () {
    test('sin(0) = 0', () {
      expectApprox(evalToDouble('sin(0)'), 0);
    });

    test('sin(π/6) = 0.5', () {
      expectApprox(evalToDouble('sin(π/6)'), 0.5);
    });

    test('sin(π/4) = √2/2', () {
      expectApprox(evalToDouble('sin(π/4)'), sqrt2Over2);
    });

    test('sin(π/3) = √3/2', () {
      expectApprox(evalToDouble('sin(π/3)'), sqrt3Over2);
    });

    test('sin(π/2) = 1', () {
      expectApprox(evalToDouble('sin(π/2)'), 1);
    });

    test('sin(π) = 0', () {
      expectApprox(evalToDouble('sin(π)'), 0);
    });

    test('sin(3π/4) = √2/2 [135° equivalent]', () {
      expectApprox(evalToDouble('sin(3*π/4)'), sqrt2Over2);
    });

    test('sin(3π/2) = -1', () {
      expectApprox(evalToDouble('sin(3*π/2)'), -1);
    });

    test('sin(2π) = 0', () {
      expectApprox(evalToDouble('sin(2*π)'), 0);
    });
  });

  group('Sine Function - Explicit rad Suffix', () {
    test('sin(0rad) = 0', () {
      expectApprox(evalToDouble('sin(0rad)'), 0);
    });

    test('sin(1rad) ≈ 0.8414709848', () {
      expectApprox(evalToDouble('sin(1rad)'), sin(1));
    });

    test('sin(1.5707963rad) ≈ 1 (π/2)', () {
      expectApprox(evalToDouble('sin(1.5707963rad)'), 1, eps: 1e-6);
    });

    test('sin(3.1415926rad) ≈ 0 (π)', () {
      expectApprox(evalToDouble('sin(3.1415926rad)'), 0, eps: 1e-6);
    });
  });

  // ============================================================
  // COSINE FUNCTION TESTS
  // ============================================================

  group('Cosine Function - Degree Input with ° Symbol', () {
    test('cos(0°) = 1', () {
      expectApprox(evalToDouble('cos(0°)'), 1);
    });

    test('cos(30°) = √3/2', () {
      expectApprox(evalToDouble('cos(30°)'), sqrt3Over2);
    });

    test('cos(45°) = √2/2', () {
      expectApprox(evalToDouble('cos(45°)'), sqrt2Over2);
    });

    test('cos(60°) = 0.5', () {
      expectApprox(evalToDouble('cos(60°)'), 0.5);
    });

    test('cos(90°) = 0', () {
      expectApprox(evalToDouble('cos(90°)'), 0);
    });

    test('cos(120°) = -0.5', () {
      expectApprox(evalToDouble('cos(120°)'), -0.5);
    });

    test('cos(135°) = -√2/2', () {
      expectApprox(evalToDouble('cos(135°)'), -sqrt2Over2);
    });

    test('cos(150°) = -√3/2', () {
      expectApprox(evalToDouble('cos(150°)'), -sqrt3Over2);
    });

    test('cos(180°) = -1', () {
      expectApprox(evalToDouble('cos(180°)'), -1);
    });

    test('cos(210°) = -√3/2', () {
      expectApprox(evalToDouble('cos(210°)'), -sqrt3Over2);
    });

    test('cos(225°) = -√2/2', () {
      expectApprox(evalToDouble('cos(225°)'), -sqrt2Over2);
    });

    test('cos(240°) = -0.5', () {
      expectApprox(evalToDouble('cos(240°)'), -0.5);
    });

    test('cos(270°) = 0', () {
      expectApprox(evalToDouble('cos(270°)'), 0);
    });

    test('cos(300°) = 0.5', () {
      expectApprox(evalToDouble('cos(300°)'), 0.5);
    });

    test('cos(315°) = √2/2', () {
      expectApprox(evalToDouble('cos(315°)'), sqrt2Over2);
    });

    test('cos(330°) = √3/2', () {
      expectApprox(evalToDouble('cos(330°)'), sqrt3Over2);
    });

    test('cos(360°) = 1', () {
      expectApprox(evalToDouble('cos(360°)'), 1);
    });
  });

  group('Cosine Function - Negative and Large Angles', () {
    test('cos(-60°) = 0.5', () {
      expectApprox(evalToDouble('cos(-60°)'), 0.5);
    });

    test('cos(-90°) = 0', () {
      expectApprox(evalToDouble('cos(-90°)'), 0);
    });

    test('cos(-180°) = -1', () {
      expectApprox(evalToDouble('cos(-180°)'), -1);
    });

    test('cos(450°) = 0', () {
      expectApprox(evalToDouble('cos(450°)'), 0);
    });

    test('cos(720°) = 1', () {
      expectApprox(evalToDouble('cos(720°)'), 1);
    });
  });

  group('Cosine Function - Radian Input', () {
    test('cos(0) = 1', () {
      expectApprox(evalToDouble('cos(0)'), 1);
    });

    test('cos(π/6) = √3/2', () {
      expectApprox(evalToDouble('cos(π/6)'), sqrt3Over2);
    });

    test('cos(π/4) = √2/2', () {
      expectApprox(evalToDouble('cos(π/4)'), sqrt2Over2);
    });

    test('cos(π/3) = 0.5', () {
      expectApprox(evalToDouble('cos(π/3)'), 0.5);
    });

    test('cos(π/2) = 0', () {
      expectApprox(evalToDouble('cos(π/2)'), 0);
    });

    test('cos(π) = -1', () {
      expectApprox(evalToDouble('cos(π)'), -1);
    });

    test('cos(2π) = 1', () {
      expectApprox(evalToDouble('cos(2*π)'), 1);
    });
  });

  // ============================================================
  // TANGENT FUNCTION TESTS
  // ============================================================

  group('Tangent Function - Degree Input', () {
    test('tan(0°) = 0', () {
      expectApprox(evalToDouble('tan(0°)'), 0);
    });

    test('tan(30°) = 1/√3 ≈ 0.577', () {
      expectApprox(evalToDouble('tan(30°)'), 1 / sqrt(3));
    });

    test('tan(45°) = 1', () {
      expectApprox(evalToDouble('tan(45°)'), 1);
    });

    test('tan(60°) = √3', () {
      expectApprox(evalToDouble('tan(60°)'), sqrt(3));
    });

    test('tan(135°) = -1', () {
      expectApprox(evalToDouble('tan(135°)'), -1);
    });

    test('tan(180°) = 0', () {
      expectApprox(evalToDouble('tan(180°)'), 0);
    });

    test('tan(225°) = 1', () {
      expectApprox(evalToDouble('tan(225°)'), 1);
    });

    test('tan(315°) = -1', () {
      expectApprox(evalToDouble('tan(315°)'), -1);
    });
  });

  group('Tangent Function - Undefined Values (Asymptotes)', () {
    test('tan(90°) should be very large or infinity', () {
      double? result = evalToDouble('tan(90°)');
      // Due to floating point, it may not be exactly infinity
      // but should be very large or infinity
      expect(
        result == null || result.abs() > 1e10 || result.isInfinite,
        isTrue,
      );
    });

    test('tan(270°) should be very large or infinity', () {
      double? result = evalToDouble('tan(270°)');
      expect(
        result == null || result.abs() > 1e10 || result.isInfinite,
        isTrue,
      );
    });
  });

  group('Tangent Function - Radian Input', () {
    test('tan(0) = 0', () {
      expectApprox(evalToDouble('tan(0)'), 0);
    });

    test('tan(π/4) = 1', () {
      expectApprox(evalToDouble('tan(π/4)'), 1);
    });

    test('tan(π) = 0', () {
      expectApprox(evalToDouble('tan(π)'), 0);
    });

    test('tan(-π/4) = -1', () {
      expectApprox(evalToDouble('tan(-π/4)'), -1);
    });
  });

  // ============================================================
  // INVERSE TRIGONOMETRIC FUNCTION TESTS
  // ============================================================

  group('Inverse Sine (asin) Tests', () {
    test('asin(0) = 0', () {
      expectApprox(evalToDouble('asin(0)'), 0);
    });

    test('asin(0.5) = π/6 ≈ 0.5236', () {
      expectApprox(evalToDouble('asin(0.5)'), pi / 6);
    });

    test('asin(√2/2) = π/4', () {
      expectApprox(evalToDouble('asin($sqrt2Over2)'), pi / 4);
    });

    test('asin(√3/2) = π/3', () {
      expectApprox(evalToDouble('asin($sqrt3Over2)'), pi / 3);
    });

    test('asin(1) = π/2', () {
      expectApprox(evalToDouble('asin(1)'), pi / 2);
    });

    test('asin(-1) = -π/2', () {
      expectApprox(evalToDouble('asin(-1)'), -pi / 2);
    });

    test('asin(-0.5) = -π/6', () {
      expectApprox(evalToDouble('asin(-0.5)'), -pi / 6);
    });
  });

  group('Inverse Cosine (acos) Tests', () {
    test('acos(1) = 0', () {
      expectApprox(evalToDouble('acos(1)'), 0);
    });

    test('acos(√3/2) = π/6', () {
      expectApprox(evalToDouble('acos($sqrt3Over2)'), pi / 6);
    });

    test('acos(√2/2) = π/4', () {
      expectApprox(evalToDouble('acos($sqrt2Over2)'), pi / 4);
    });

    test('acos(0.5) = π/3', () {
      expectApprox(evalToDouble('acos(0.5)'), pi / 3);
    });

    test('acos(0) = π/2', () {
      expectApprox(evalToDouble('acos(0)'), pi / 2);
    });

    test('acos(-1) = π', () {
      expectApprox(evalToDouble('acos(-1)'), pi);
    });
  });

  group('Inverse Tangent (atan) Tests', () {
    test('atan(0) = 0', () {
      expectApprox(evalToDouble('atan(0)'), 0);
    });

    test('atan(1) = π/4', () {
      expectApprox(evalToDouble('atan(1)'), pi / 4);
    });

    test('atan(-1) = -π/4', () {
      expectApprox(evalToDouble('atan(-1)'), -pi / 4);
    });

    test('atan(√3) = π/3', () {
      expectApprox(evalToDouble('atan(${sqrt(3)})'), pi / 3);
    });

    test('atan(1/√3) = π/6', () {
      expectApprox(evalToDouble('atan(${1 / sqrt(3)})'), pi / 6);
    });
  });

  // ============================================================
  // HYPERBOLIC FUNCTION TESTS
  // ============================================================

  group('Hyperbolic Sine (sinh) Tests', () {
    test('sinh(0) = 0', () {
      expectApprox(evalToDouble('sinh(0)'), 0);
    });

    test('sinh(1) ≈ 1.1752011936', () {
      expectApprox(evalToDouble('sinh(1)'), (exp(1) - exp(-1)) / 2);
    });

    test('sinh(-1) ≈ -1.1752011936', () {
      expectApprox(evalToDouble('sinh(-1)'), -(exp(1) - exp(-1)) / 2);
    });

    test('sinh(2) ≈ 3.6268604078', () {
      expectApprox(evalToDouble('sinh(2)'), (exp(2) - exp(-2)) / 2);
    });
  });

  group('Hyperbolic Cosine (cosh) Tests', () {
    test('cosh(0) = 1', () {
      expectApprox(evalToDouble('cosh(0)'), 1);
    });

    test('cosh(1) ≈ 1.5430806348', () {
      expectApprox(evalToDouble('cosh(1)'), (exp(1) + exp(-1)) / 2);
    });

    test('cosh(-1) = cosh(1) (even function)', () {
      double? pos = evalToDouble('cosh(1)');
      double? neg = evalToDouble('cosh(-1)');
      expect(pos, isNotNull);
      expect(neg, isNotNull);
      expectApprox(neg, pos!);
    });

    test('cosh(2) ≈ 3.7621956911', () {
      expectApprox(evalToDouble('cosh(2)'), (exp(2) + exp(-2)) / 2);
    });
  });

  group('Hyperbolic Tangent (tanh) Tests', () {
    test('tanh(0) = 0', () {
      expectApprox(evalToDouble('tanh(0)'), 0);
    });

    test('tanh(1) ≈ 0.7615941559', () {
      double expected = (exp(1) - exp(-1)) / (exp(1) + exp(-1));
      expectApprox(evalToDouble('tanh(1)'), expected);
    });

    test('tanh(-1) ≈ -0.7615941559', () {
      double expected = (exp(-1) - exp(1)) / (exp(-1) + exp(1));
      expectApprox(evalToDouble('tanh(-1)'), expected);
    });

    test('tanh(large) ≈ 1', () {
      double? result = evalToDouble('tanh(10)');
      expectApprox(result, 1, eps: 1e-6);
    });

    test('tanh(-large) ≈ -1', () {
      double? result = evalToDouble('tanh(-10)');
      expectApprox(result, -1, eps: 1e-6);
    });
  });

  // ============================================================
  // INVERSE HYPERBOLIC FUNCTION TESTS
  // ============================================================

  group('Inverse Hyperbolic Functions', () {
    test('asinh(0) = 0', () {
      expectApprox(evalToDouble('asinh(0)'), 0);
    });

    test('asinh(1) ≈ 0.8813735870', () {
      expectApprox(evalToDouble('asinh(1)'), log(1 + sqrt(2)));
    });

    test('acosh(1) = 0', () {
      expectApprox(evalToDouble('acosh(1)'), 0);
    });

    test('acosh(2) ≈ 1.3169578969', () {
      expectApprox(evalToDouble('acosh(2)'), log(2 + sqrt(3)));
    });

    test('atanh(0) = 0', () {
      expectApprox(evalToDouble('atanh(0)'), 0);
    });

    test('atanh(0.5) ≈ 0.5493061443', () {
      expectApprox(evalToDouble('atanh(0.5)'), 0.5 * log(3));
    });
  });

  // ============================================================
  // GLOBAL ANGLE MODE TESTS
  // ============================================================

  group('Default Angle Mode - Radians', () {
    test('Without ° symbol: sin(90) uses radians', () {
      expectApprox(evalToDouble('sin(90)'), sin(90));
    });

    test('Without ° symbol: cos(180) uses radians', () {
      expectApprox(evalToDouble('cos(180)'), cos(180));
    });

    test('Without ° symbol: tan(45) uses radians', () {
      expectApprox(evalToDouble('tan(45)'), tan(45));
    });

    test('Inverse trig output remains radians: asin(0.5) = π/6', () {
      expectApprox(evalToDouble('asin(0.5)'), pi / 6);
    });

    test('Inverse trig output remains radians: acos(0.5) = π/3', () {
      expectApprox(evalToDouble('acos(0.5)'), pi / 3);
    });

    test('Inverse trig output remains radians: atan(1) = π/4', () {
      expectApprox(evalToDouble('atan(1)'), pi / 4);
    });
  });

  group('Global Angle Mode - Radian Mode (default)', () {
    // setUp(() {
    //   MathSolverNew.setAngleMode(AngleMode.radians);
    // });

    test('In radian mode: sin(π/2) = 1', () {
      expectApprox(evalToDouble('sin(π/2)'), 1);
    });

    test('In radian mode: cos(π) = -1', () {
      expectApprox(evalToDouble('cos(π)'), -1);
    });

    test('In radian mode: asin(0.5) = π/6', () {
      expectApprox(evalToDouble('asin(0.5)'), pi / 6);
    });
  });

  // ============================================================
  // COMBINED EXPRESSION TESTS
  // ============================================================

  group('Combined Trigonometric Expressions', () {
    test('sin(30°) + cos(60°) = 1', () {
      expectApprox(evalToDouble('sin(30°)+cos(60°)'), 1);
    });

    test('sin²(45°) + cos²(45°) = 1 (Pythagorean identity)', () {
      expectApprox(evalToDouble('sin(45°)^2+cos(45°)^2'), 1);
    });

    test('sin(60°) / cos(60°) = tan(60°)', () {
      double? ratio = evalToDouble('sin(60°)/cos(60°)');
      double? tangent = evalToDouble('tan(60°)');
      expectApprox(ratio, tangent!);
    });

    test('2*sin(45°)*cos(45°) = sin(90°) (double angle)', () {
      expectApprox(evalToDouble('2*sin(45°)*cos(45°)'), 1);
    });

    test('cos(60°) - cos(120°) = 1', () {
      expectApprox(evalToDouble('cos(60°)-cos(120°)'), 1);
    });

    test('sin(30°) * cos(60°) + cos(30°) * sin(60°) = sin(90°)', () {
      // sin(A+B) = sin(A)cos(B) + cos(A)sin(B)
      expectApprox(evalToDouble('sin(30°)*cos(60°)+cos(30°)*sin(60°)'), 1);
    });
  });

  // ============================================================
  // EDGE CASES AND BOUNDARY CONDITIONS
  // ============================================================

  group('Edge Cases - Very Small Angles', () {
    test('sin(0.001°) ≈ 0.001 * π/180', () {
      double expected = sin(0.001 * pi / 180);
      expectApprox(evalToDouble('sin(0.001°)'), expected);
    });

    test('cos(0.001°) ≈ 1', () {
      expectApprox(evalToDouble('cos(0.001°)'), 1, eps: 1e-6);
    });

    test('tan(0.001°) ≈ 0.001 * π/180', () {
      double expected = tan(0.001 * pi / 180);
      expectApprox(evalToDouble('tan(0.001°)'), expected);
    });
  });

  group('Edge Cases - Decimal Degrees', () {
    test('sin(30.5°)', () {
      expectApprox(evalToDouble('sin(30.5°)'), sin(30.5 * pi / 180));
    });

    test('cos(45.25°)', () {
      expectApprox(evalToDouble('cos(45.25°)'), cos(45.25 * pi / 180));
    });

    test('sin(89.999°) ≈ 1', () {
      expectApprox(evalToDouble('sin(89.999°)'), 1, eps: 1e-4);
    });
  });

  group('Edge Cases - Expression Inside Trig Functions', () {
    test('sin((90+45)°) = sin(135°)', () {
      expectApprox(evalToDouble('sin((90+45)°)'), sqrt2Over2);
    });

    test('cos((180-45)°) = cos(135°)', () {
      expectApprox(evalToDouble('cos((180-45)°)'), -sqrt2Over2);
    });

    test('sin(2*45°) = sin(90°) = 1', () {
      expectApprox(evalToDouble('sin(2*45°)'), 1);
    });

    test('cos(360°/4) = cos(90°) = 0', () {
      expectApprox(evalToDouble('cos(360°/4)'), 0);
    });
  });

  group('Edge Cases - Nested Functions', () {
    test('sin(asin(0.5)) = 0.5', () {
      expectApprox(evalToDouble('sin(asin(0.5))'), 0.5);
    });

    test('cos(acos(0.5)) = 0.5', () {
      expectApprox(evalToDouble('cos(acos(0.5))'), 0.5);
    });

    test('tan(atan(1)) = 1', () {
      expectApprox(evalToDouble('tan(atan(1))'), 1);
    });

    test('asin(sin(30°)) = 30° in radians', () {
      expectApprox(evalToDouble('asin(sin(30°))'), pi / 6);
    });
  });

  group('Edge Cases - Complex Input to Trig Functions', () {
    test('sin(i) should return complex result', () {
      String? result = MathSolverNew.evaluate('sin(i)');
      expect(result, isNotNull);
      expect(result!.contains('i'), isTrue);
    });

    test('cos(i) should return complex result', () {
      String? result = MathSolverNew.evaluate('cos(i)');
      expect(result, isNotNull);
      // cos(i) = cosh(1) ≈ 1.543 (real)
      double? parsed = double.tryParse(result!);
      if (parsed != null) {
        expectApprox(parsed, (exp(1) + exp(-1)) / 2);
      }
    });
  });

  // ============================================================
  // REGRESSION TESTS FOR THE REPORTED BUG
  // ============================================================

  group('Regression Tests - sin(135°) Bug', () {
    test('sin(135°) = √2/2 ≈ 0.7071', () {
      expectApprox(evalToDouble('sin(135°)'), sqrt2Over2);
    });

    test('sin(135°) equals sin(45°)', () {
      double? sin135 = evalToDouble('sin(135°)');
      double? sin45 = evalToDouble('sin(45°)');
      expectApprox(sin135, sin45!);
    });

    test('sin(135°) equals sin(180°-45°)', () {
      double? sin135 = evalToDouble('sin(135°)');
      double? sinDiff = evalToDouble('sin((180-45)°)');
      expectApprox(sin135, sinDiff!);
    });

    test('Verify preprocessing: 135° should convert to radians correctly', () {
      // 135° = 135 * π/180 = 3π/4 ≈ 2.356 radians
      double expectedRadians = 135 * pi / 180;
      expectApprox(evalToDouble('sin($expectedRadians)'), sqrt2Over2);
    });
  });

  group('Regression Tests - rad Suffix Bug', () {
    test('sin(1rad) should equal sin(1)', () {
      double? withRad = evalToDouble('sin(1rad)');
      double? withoutRad = evalToDouble('sin(1)');
      expectApprox(withRad, withoutRad!);
    });

    test('cos(1.5707963rad) ≈ 0 (π/2 radians)', () {
      expectApprox(evalToDouble('cos(1.5707963rad)'), 0, eps: 1e-6);
    });

    test('sin(3.14159rad) ≈ 0 (π radians)', () {
      expectApprox(evalToDouble('sin(3.14159rad)'), 0, eps: 1e-4);
    });
  });

  // ============================================================
  // STRESS TESTS
  // ============================================================

  group('Stress Tests - Many Consecutive Calls', () {
    test('Evaluate all quadrant angles for sin', () {
      List<int> angles = [
        0,
        30,
        45,
        60,
        90,
        120,
        135,
        150,
        180,
        210,
        225,
        240,
        270,
        300,
        315,
        330,
        360,
      ];

      for (int angle in angles) {
        double expected = sin(angle * pi / 180);
        double? actual = evalToDouble('sin($angle°)');
        expect(actual, isNotNull, reason: 'sin($angle°) returned null');
        expect(
          (actual! - expected).abs(),
          lessThan(tolerance),
          reason: 'sin($angle°): expected $expected but got $actual',
        );
      }
    });

    test('Evaluate all quadrant angles for cos', () {
      List<int> angles = [
        0,
        30,
        45,
        60,
        90,
        120,
        135,
        150,
        180,
        210,
        225,
        240,
        270,
        300,
        315,
        330,
        360,
      ];

      for (int angle in angles) {
        double expected = cos(angle * pi / 180);
        double? actual = evalToDouble('cos($angle°)');
        expect(actual, isNotNull, reason: 'cos($angle°) returned null');
        expect(
          (actual! - expected).abs(),
          lessThan(tolerance),
          reason: 'cos($angle°): expected $expected but got $actual',
        );
      }
    });
  });
}
