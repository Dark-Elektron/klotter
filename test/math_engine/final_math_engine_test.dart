import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';

void main() {
  // ignore: no_leading_underscores_for_local_identifiers
  double _parse(String? s) {
    if (s == null || s.isEmpty) return 0.0;
    return double.parse(s.replaceAll('\u1D07', 'e').replaceAll(',', '').trim());
  }

  group('Final Math Engine Tests (Decimal)', () {
    setUp(() {
      MathSolverNew.setPrecision(10);
    });

    tearDown(() {
      MathSolverNew.setPrecision(6);
    });

    test('Hyperbolic Functions Evaluation', () {
      // sinh(0) = 0
      expect(MathSolverNew.solve('sinh(0)'), equals('0'));
      // cosh(0) = 1
      expect(MathSolverNew.solve('cosh(0)'), equals('1'));
      // tanh(0) = 0
      expect(MathSolverNew.solve('tanh(0)'), equals('0'));

      // Values
      // sinh(1) approx 1.17520119364
      String? resSinh = MathSolverNew.solve('sinh(1)');
      expect(_parse(resSinh), closeTo(1.175201, 0.00001));

      // cosh(1) approx 1.54308063482
      String? resCosh = MathSolverNew.solve('cosh(1)');
      expect(_parse(resCosh), closeTo(1.543080, 0.00001));
    });

    test('Inverse Hyperbolic Functions Evaluation', () {
      expect(MathSolverNew.solve('asinh(0)'), equals('0'));
      expect(MathSolverNew.solve('acosh(1)'), equals('0'));
      expect(MathSolverNew.solve('atanh(0)'), equals('0'));

      // asinh(1) approx 0.88137358701
      String? resAsinh = MathSolverNew.solve('asinh(1)');
      expect(_parse(resAsinh), closeTo(0.881373, 0.00001));
    });

    test('Physical Constants Evaluation', () {
      // epsilon0 approx 8.854e-12
      String? resE = MathSolverNew.solve('\u03B5\u2080'); // ε₀
      expect(_parse(resE), closeTo(8.854187e-12, 1e-17));

      // mu0 approx 1.2566e-6
      String? resM = MathSolverNew.solve('\u03BC\u2080'); // μ₀
      expect(
        _parse(resM),
        closeTo(1.256637e-6, 1e-9),
      ); // Reduced precision expectation because > 1e-6 triggers toStringAsFixed(10)

      // c0 = 299792458
      expect(MathSolverNew.solve('c\u2080'), equals('2.99792458\u1D078'));
    });

    test('Implicit Multiplication with Constants', () {
      // 2 * pi
      String? res2Pi = MathSolverNew.solve('2\u03C0');
      expect(_parse(res2Pi), closeTo(6.283185, 0.00001));

      // pi * e
      String? resPiE = MathSolverNew.solve('\u03C0e');
      expect(_parse(resPiE), closeTo(8.539734, 0.00001));

      // eps0 * mu0 = 1/c0^2
      String? resEm = MathSolverNew.solve('\u03B5\u2080\u03BC\u2080');
      double c = 299792458;
      expect(_parse(resEm), closeTo(1 / (c * c), 1e-25));
    });

    test('Complex Combinations', () {
      // sinh(pi/2) approx 2.3012989
      String? res = MathSolverNew.solve('sinh(\u03C0/2)');
      expect(_parse(res), closeTo(2.301298, 0.00001));
    });
  });
}
