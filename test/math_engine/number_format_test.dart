import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  group('Number Formatting', () {
    setUp(() {
      MathSolverNew.precision = 10;
    });

    test(
      'NumberFormat.plain formats with commas and no scientific notation',
      () {
        MathSolverNew.setNumberFormat(NumberFormat.plain);

        expect(MathSolverNew.formatResult(2000), equals('2,000'));
        expect(MathSolverNew.formatResult(3000.09), equals('3,000.09'));
        expect(MathSolverNew.formatResult(1000000000), equals('1,000,000,000'));
        expect(MathSolverNew.formatResult(-50000), equals('-50,000'));
        expect(MathSolverNew.formatResult(0.0000001), equals('0.0000001'));
        expect(MathSolverNew.formatResult(999), equals('999'));
        expect(MathSolverNew.formatResult(0), equals('0'));
      },
    );

    test(
      'NumberFormat.automatic uses scientific notation only outside 1e-6 to 1e6',
      () {
        MathSolverNew.setNumberFormat(NumberFormat.automatic);

        // Inside range: no scientific, NO COMMAS
        expect(MathSolverNew.formatResult(2000), equals('2000'));
        expect(MathSolverNew.formatResult(999999), equals('999999'));
        expect(
          MathSolverNew.formatResult(0.000001001),
          equals('0.000001001'),
        ); // > 1e-6

        // Outside range: scientific
        expect(
          MathSolverNew.formatResult(1000000),
          equals('1\u1D076'),
        ); // 1e6 starts scientific
        expect(MathSolverNew.formatResult(3000.09), equals('3000.09'));
        expect(
          MathSolverNew.formatResult(0.000001),
          equals('1\u1D07-6'),
        ); // <= 1e-6
        expect(
          MathSolverNew.formatResult(0.0000009),
          equals('9\u1D07-7'),
        ); // <= 1e-6
      },
    );

    test('NumberFormat.scientific always uses scientific notation', () {
      MathSolverNew.setNumberFormat(NumberFormat.scientific);

      expect(MathSolverNew.formatResult(2000), equals('2\u1D073'));
      expect(MathSolverNew.formatResult(20), equals('2\u1D071'));
      expect(MathSolverNew.formatResult(3000.09), equals('3.00009\u1D073'));
      expect(MathSolverNew.formatResult(0.05), equals('5\u1D07-2'));
      // Zero is special
      expect(MathSolverNew.formatResult(0), equals('0'));
    });

    group('Exact Engine Formatting', () {
      test('NumberFormat.plain formats BigInt with commas', () {
        MathSolverNew.setNumberFormat(NumberFormat.plain);

        expect(IntExpr(BigInt.from(2000)).toString(), equals('2,000'));
        expect(IntExpr(BigInt.from(3000000)).toString(), equals('3,000,000'));
      });

      test(
        'NumberFormat.automatic formats BigInt with scientific if >= 1e6',
        () {
          MathSolverNew.setNumberFormat(NumberFormat.automatic);

          expect(IntExpr(BigInt.from(2000)).toString(), equals('2000'));
          expect(IntExpr(BigInt.from(999999)).toString(), equals('999999'));
          expect(IntExpr(BigInt.from(1000000)).toString(), equals('1\u1D076'));
        },
      );

      test('NumberFormat.scientific always formats BigInt scientifically', () {
        MathSolverNew.setNumberFormat(NumberFormat.scientific);

        expect(IntExpr(BigInt.from(2000)).toString(), equals('2\u1D073'));
        expect(IntExpr(BigInt.from(1)).toString(), equals('1\u1D070'));
      });
    });
  });
}
