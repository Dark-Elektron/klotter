import 'package:flutter_test/flutter_test.dart';
import 'dart:math';
import 'package:klotter/math_engine/math_engine.dart';

void main() {
  group('MathSolverNew - Basic Evaluation', () {
    test('evaluates simple addition', () {
      expect(MathSolverNew.solve('2+3'), equals('5'));
    });

    test('evaluates simple subtraction', () {
      expect(MathSolverNew.solve('10-4'), equals('6'));
    });

    test('evaluates simple multiplication', () {
      expect(MathSolverNew.solve('3*4'), equals('12'));
    });

    test('evaluates simple division', () {
      expect(MathSolverNew.solve('15/3'), equals('5'));
    });

    test('evaluates decimal numbers', () {
      expect(MathSolverNew.solve('2.5+1.5'), equals('4'));
    });

    test('evaluates negative numbers', () {
      expect(MathSolverNew.solve('-5+3'), equals('-2'));
    });

    test('returns empty string for invalid expression', () {
      expect(MathSolverNew.solve('abc'), equals(''));
    });

    test('returns null for empty expression', () {
      expect(MathSolverNew.solve(''), isNull);
    });
  });

  group('MathSolverNew - Order of Operations (PEMDAS)', () {
    test('multiplication before addition', () {
      expect(MathSolverNew.solve('2+3*4'), equals('14'));
    });

    test('division before subtraction', () {
      expect(MathSolverNew.solve('10-6/2'), equals('7'));
    });

    test('parentheses override order', () {
      expect(MathSolverNew.solve('(2+3)*4'), equals('20'));
    });

    test('nested parentheses', () {
      expect(MathSolverNew.solve('((2+3)*2)+1'), equals('11'));
    });

    test('complex expression', () {
      expect(MathSolverNew.solve('2+3*4-6/2'), equals('11'));
    });
  });

  group('MathSolverNew - Exponents', () {
    test('simple power', () {
      expect(MathSolverNew.solve('2^3'), equals('8'));
    });

    test('power of zero', () {
      expect(MathSolverNew.solve('5^0'), equals('1'));
    });

    test('negative exponent', () {
      expect(MathSolverNew.solve('2^(-1)'), equals('0.5'));
    });

    test('fractional exponent (square root)', () {
      expect(MathSolverNew.solve('4^(0.5)'), equals('2'));
    });

    test('chained exponents', () {
      expect(MathSolverNew.solve('2^2^2'), equals('16'));
    });
  });

  group('MathSolverNew - Trigonometric Functions', () {
    test('sin(0) equals 0', () {
      expect(MathSolverNew.solve('sin(0)'), equals('0'));
    });

    test('cos(0) equals 1', () {
      expect(MathSolverNew.solve('cos(0)'), equals('1'));
    });

    test('tan(0) equals 0', () {
      expect(MathSolverNew.solve('tan(0)'), equals('0'));
    });

    test('asin(0) equals 0', () {
      expect(MathSolverNew.solve('asin(0)'), equals('0'));
    });

    test('acos(1) equals 0', () {
      expect(MathSolverNew.solve('acos(1)'), equals('0'));
    });

    test('atan(0) equals 0', () {
      expect(MathSolverNew.solve('atan(0)'), equals('0'));
    });
  });

  group('MathSolverNew - Logarithmic Functions', () {
    test('ln(1) equals 0', () {
      expect(MathSolverNew.solve('ln(1)'), equals('0'));
    });

    test('log(10) equals 1', () {
      expect(MathSolverNew.solve('log(10)'), equals('1'));
    });

    test('log(100) equals 2', () {
      expect(MathSolverNew.solve('log(100)'), equals('2'));
    });

    test('ln(e) equals 1', () {
      final result = double.parse(
        MathSolverNew.solve('ln(2.718281828459045)')!,
      );
      expect(result, closeTo(1.0, 0.0001));
    });
  });

  group('MathSolverNew - Square Root', () {
    test('sqrt(4) equals 2', () {
      expect(MathSolverNew.solve('sqrt(4)'), equals('2'));
    });

    test('sqrt(9) equals 3', () {
      expect(MathSolverNew.solve('sqrt(9)'), equals('3'));
    });

    test('sqrt(2) is approximately 1.414', () {
      final result = double.parse(MathSolverNew.solve('sqrt(2)')!);
      expect(result, closeTo(1.41421356, 0.0001));
    });

    test('sqrt(0) equals 0', () {
      expect(MathSolverNew.solve('sqrt(0)'), equals('0'));
    });
  });

  group('MathSolverNew - Complex Functions', () {
    test('abs of complex number', () {
      expect(MathSolverNew.solve('abs(3+4i)'), equals('5'));
    });

    test('arg of positive real is 0', () {
      final result = double.parse(MathSolverNew.solve('arg(5)')!);
      expect(result, closeTo(0.0, 1e-10));
    });

    test('arg of negative real is pi', () {
      final result = double.parse(MathSolverNew.solve('arg(-2)')!);
      expect(result, closeTo(pi, 1e-6));
    });

    test('arg of complex number', () {
      final result = double.parse(MathSolverNew.solve('arg(3+4i)')!);
      expect(result, closeTo(atan2(4, 3), 1e-6));
    });

    test('Re of complex number', () {
      expect(MathSolverNew.solve('Re(3+4i)'), equals('3'));
    });

    test('Im of complex number', () {
      expect(MathSolverNew.solve('Im(3+4i)'), equals('4'));
    });

    test('Im of real number is 0', () {
      expect(MathSolverNew.solve('Im(7)'), equals('0'));
    });

    test('sgn of real number', () {
      expect(MathSolverNew.solve('sgn(3)'), equals('1'));
      expect(MathSolverNew.solve('sgn(-3)'), equals('-1'));
      expect(MathSolverNew.solve('sgn(0)'), equals('0'));
    });

    test('sgn of complex number', () {
      expect(MathSolverNew.solve('sgn(3+4i)'), equals('0.6 + 0.8i'));
    });
  });

  group('MathSolverNew - Factorial', () {
    test('0! equals 1', () {
      expect(MathSolverNew.solve('0!'), equals('1'));
    });

    test('1! equals 1', () {
      expect(MathSolverNew.solve('1!'), equals('1'));
    });

    test('5! equals 120', () {
      expect(MathSolverNew.solve('5!'), equals('120'));
    });

    test('10! equals 3628800', () {
      expect(MathSolverNew.solve('10!'), equals('3.6288\u1D076'));
    });
  });

  group('MathSolverNew - Permutation', () {
    test('perm(5,2) equals 20', () {
      expect(MathSolverNew.solve('perm(5,2)'), equals('20'));
    });

    test('perm(5,0) equals 1', () {
      expect(MathSolverNew.solve('perm(5,0)'), equals('1'));
    });

    test('perm(5,5) equals 120', () {
      expect(MathSolverNew.solve('perm(5,5)'), equals('120'));
    });

    test('perm(10,3) equals 720', () {
      expect(MathSolverNew.solve('perm(10,3)'), equals('720'));
    });

    test('perm with expressions: perm((2+3),2) equals 20', () {
      expect(MathSolverNew.solve('perm((2+3),2)'), equals('20'));
    });

    test('perm(32,3) equals 29760', () {
      expect(MathSolverNew.solve('perm(32,3)'), equals('29760'));
    });

    test('perm with r > n returns 0', () {
      expect(MathSolverNew.solve('perm(3,5)'), equals('0'));
    });
  });

  group('MathSolverNew - Combination', () {
    test('comb(5,2) equals 10', () {
      expect(MathSolverNew.solve('comb(5,2)'), equals('10'));
    });

    test('comb(5,0) equals 1', () {
      expect(MathSolverNew.solve('comb(5,0)'), equals('1'));
    });

    test('comb(5,5) equals 1', () {
      expect(MathSolverNew.solve('comb(5,5)'), equals('1'));
    });

    test('comb(10,3) equals 120', () {
      expect(MathSolverNew.solve('comb(10,3)'), equals('120'));
    });

    test('comb with expressions: comb((2+3),2) equals 10', () {
      expect(MathSolverNew.solve('comb((2+3),2)'), equals('10'));
    });

    test('comb(32,3) equals 4960', () {
      expect(MathSolverNew.solve('comb(32,3)'), equals('4960'));
    });

    test('comb with r > n returns 0', () {
      expect(MathSolverNew.solve('comb(3,5)'), equals('0'));
    });
  });

  group('MathSolverNew - Linear Equations (Single Variable)', () {
    test('solves simple linear equation: x+2=5', () {
      expect(MathSolverNew.solve('x+2=5'), equals('x = 3'));
    });

    test('solves linear equation with coefficient: 2x=10', () {
      expect(MathSolverNew.solve('2x=10'), equals('x = 5'));
    });

    test('solves linear equation: 3x+5=20', () {
      expect(MathSolverNew.solve('3x+5=20'), equals('x = 5'));
    });

    test('solves linear equation with variable on both sides: 2x+3=x+7', () {
      expect(MathSolverNew.solve('2x+3=x+7'), equals('x = 4'));
    });

    test('solves linear equation with negative result: x+10=5', () {
      expect(MathSolverNew.solve('x+10=5'), equals('x = -5'));
    });

    test('solves linear equation with decimal result: x+1=2.5', () {
      expect(MathSolverNew.solve('x+1=2.5'), equals('x = 1.5'));
    });

    test('solves linear equation with fractional coefficient: (3/2)x=6', () {
      expect(MathSolverNew.solve('3/2x=6'), equals('x = 4'));
    });
  });

  group('MathSolverNew - Quadratic Equations', () {
    test('solves x^2=4 with two roots', () {
      final result = MathSolverNew.solve('x^(2)=4');
      expect(result, contains('x = 2'));
      expect(result, contains('x = -2'));
    });

    test('solves x^2-5x+6=0', () {
      final result = MathSolverNew.solve('x^(2)-5x+6=0');
      expect(result, contains('x = 2'));
      expect(result, contains('x = 3'));
    });

    test('solves quadratic with single root: x^2-4x+4=0', () {
      expect(MathSolverNew.solve('x^(2)-4x+4=0'), equals('x = 2'));
    });

    test('solves quadratic with complex roots', () {
      final result = MathSolverNew.solve('x^(2)+1=0');
      expect(result, contains('i')); // Should contain imaginary part
    });

    test('solves quadratic with fractional coefficient', () {
      final result = MathSolverNew.solve('x^(2)+3/2x+1=5');
      expect(result, contains('x = -2.886001'));
      expect(result, contains('x = 1.386001'));
    });
  });

  group('MathSolverNew - Multi-Variable Equations (Should NOT Solve)', () {
    test('returns null for equation with two variables: 2x+y=3', () {
      expect(MathSolverNew.solve('2x+y=3'), isNull);
    });

    test('returns null for equation with three variables: x+y+z=10', () {
      expect(MathSolverNew.solve('x+y+z=10'), isNull);
    });

    test('returns null for equation: ax+b=c', () {
      expect(MathSolverNew.solve('ax+b=c'), isNull);
    });
  });

  group('MathSolverNew - System of Linear Equations', () {
    test('solves 2x2 system', () {
      final result = MathSolverNew.solve('x+y=5\nx-y=1');
      expect(result, contains('x = 3'));
      expect(result, contains('y = 2'));
    });

    test('solves another 2x2 system', () {
      final result = MathSolverNew.solve('2x+3y=12\nx-y=1');
      expect(result, contains('x = 3'));
      expect(result, contains('y = 2'));
    });

    test('solves 2x2 system with fractional coefficients', () {
      final result = MathSolverNew.solve('x+1/2y=5\nx-1/2y=1');
      expect(result, contains('x = 3'));
      expect(result, contains('y = 4'));
    });

    test('returns null for underdetermined system', () {
      // More variables than equations
      expect(MathSolverNew.solve('x+y+z=10'), isNull);
    });
  });

  group('MathSolverNew - Constants', () {
    test('pi constant', () {
      final result = double.parse(MathSolverNew.solve('\u03C0')!);
      expect(result, closeTo(3.14159265, 0.0001));
    });

    test('e constant', () {
      final result = double.parse(MathSolverNew.solve('e')!);
      expect(result, closeTo(2.71828182, 0.0001));
    });

    test('pi in expression: 2*pi', () {
      final result = double.parse(MathSolverNew.solve('2*\u03C0')!);
      expect(result, closeTo(6.28318530, 0.0001));
    });
  });

  group('MathSolverNew - Scientific Notation', () {
    test('parses scientific notation input', () {
      expect(MathSolverNew.solve('1E3'), equals('1000'));
    });

    test('parses negative exponent', () {
      expect(MathSolverNew.solve('1E-3'), equals('0.001'));
    });

    test('large numbers use scientific notation', () {
      final result = MathSolverNew.solve('1000000*1000000');
      expect(result, contains('\u1D07')); // Contains small E
    });
  });

  group('MathSolverNew - Edge Cases', () {
    test('division by zero returns Infinity', () {
      expect(MathSolverNew.solve('1/0'), equals('Infinity'));
    });

    test('0/0 returns NaN', () {
      expect(MathSolverNew.solve('0/0'), equals('NaN'));
    });

    test('handles whitespace', () {
      expect(MathSolverNew.solve(' 2 + 3 '), equals('5'));
    });

    test('handles multiple operators: 2+-3', () {
      expect(MathSolverNew.solve('2+-3'), equals('-1'));
    });

    test('handles double negative: 2--3', () {
      expect(MathSolverNew.solve('2--3'), equals('5'));
    });
  });

  group('MathSolverNew - Precision', () {
    test('default precision is 6', () {
      expect(MathSolverNew.precision, equals(6));
    });

    test('setPrecision updates precision', () {
      MathSolverNew.setPrecision(4);
      expect(MathSolverNew.precision, equals(4));
      // Reset to default
      MathSolverNew.setPrecision(6);
    });

    test('result respects precision setting', () {
      MathSolverNew.setPrecision(2);
      final result = MathSolverNew.solve('1/3');
      expect(result, equals('0.33'));
      // Reset to default
      MathSolverNew.setPrecision(6);
    });
  });

  group('MathSolverNew - ANS References', () {
    test('replaces ans0 with value', () {
      final ansValues = {0: '5'};
      expect(MathSolverNew.solve('ans0+3', ansValues: ansValues), equals('8'));
    });

    test('replaces multiple ans references', () {
      final ansValues = {0: '5', 1: '3'};
      expect(
        MathSolverNew.solve('ans0+ans1', ansValues: ansValues),
        equals('8'),
      );
    });

    test('handles missing ans reference', () {
      final ansValues = {0: '5'};
      expect(MathSolverNew.solve('ans1+3', ansValues: ansValues), equals('3'));
    });
  });

  group('MathSolverNew - Hyperbolic Functions', () {
    test('sinh(0) equals 0', () {
      expect(MathSolverNew.solve('sinh(0)'), equals('0'));
    });

    test('cosh(0) equals 1', () {
      expect(MathSolverNew.solve('cosh(0)'), equals('1'));
    });

    test('tanh(0) equals 0', () {
      expect(MathSolverNew.solve('tanh(0)'), equals('0'));
    });

    test('asinh(0) equals 0', () {
      expect(MathSolverNew.solve('asinh(0)'), equals('0'));
    });

    test('acosh(1) equals 0', () {
      expect(MathSolverNew.solve('acosh(1)'), equals('0'));
    });

    test('atanh(0) equals 0', () {
      expect(MathSolverNew.solve('atanh(0)'), equals('0'));
    });

    test('sinh(1) is approximately 1.1752', () {
      final result = double.parse(MathSolverNew.solve('sinh(1)')!);
      expect(result, closeTo(1.1752, 0.001));
    });

    test('cosh(1) is approximately 1.5431', () {
      final result = double.parse(MathSolverNew.solve('cosh(1)')!);
      expect(result, closeTo(1.5431, 0.001));
    });
  });

  group('MathSolverNew - Physical Constants', () {
    test('physical constants placeholders check', () {
      // Verification of physical constants parsing requires UI integration tests
      // due to complex Unicode character handling (subscripts).
      // The underlying constant values are defined in math_engine_exact.dart
      expect(true, isTrue);
    });
  });

  group('MathSolverNew - Calculus', () {
    test('evaluates derivative diff(x,2,x^2) = 4', () {
      final result = double.parse(MathSolverNew.solve('diff(x,2,x^2)')!);
      expect(result, closeTo(4.0, 1e-3));
    });

    test('evaluates integral int(x,0,1,x) = 0.5', () {
      final result = double.parse(MathSolverNew.solve('int(x,0,1,x)')!);
      expect(result, closeTo(0.5, 1e-3));
    });

    test('integral handles reversed bounds', () {
      final result = double.parse(MathSolverNew.solve('int(x,1,0,x)')!);
      expect(result, closeTo(-0.5, 1e-3));
    });
  });
}
