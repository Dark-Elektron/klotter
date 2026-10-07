import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// A compiled expression answers as the walk does.
///
/// The walk ([ExprNumericEval.evalWith]) is the reference: it is what plots
/// were drawn with before compiling existed. Every kind of node is compiled
/// here and read at a spread of points, ordinary and awkward, against it. The
/// one sanctioned difference is an unrolled whole power, which may differ in
/// its last bit, so values are compared to within rounding.
void main() {
  List<MathNode> lit(String text) => <MathNode>[LiteralNode(text: text)];
  MathNode call(String function, List<MathNode> argument) =>
      TrigNode(function: function, argument: argument);
  MathNode plus() => LiteralNode(text: '+');
  MathNode minus() => LiteralNode(text: '-');

  Expr compile(List<MathNode> nodes) =>
      MathNodeToExpr.convert(nodes).simplify();

  /// Real lines, with the variables they are functions of.
  final Map<String, List<MathNode>> real = <String, List<MathNode>>{
    'the tooth': lit('x^4+y^4+z^4-x^2-y^2-z^2+0.4'),
    'mixed powers': lit('x^3-2x^2y+5'),
    'negative and zero powers': <MathNode>[
      ExponentNode(base: lit('x'), power: lit('-2')),
      plus(),
      ExponentNode(base: lit('y'), power: lit('0')),
      plus(),
      ExponentNode(base: lit('z'), power: lit('-1')),
    ],
    'a large whole power': <MathNode>[
      ExponentNode(base: lit('x'), power: lit('7')),
      minus(),
      ExponentNode(base: lit('y'), power: lit('-5')),
    ],
    'a fractional power with an odd denominator': <MathNode>[
      ExponentNode(
        base: lit('x'),
        power: <MathNode>[FractionNode(num: lit('1'), den: lit('3'))],
      ),
    ],
    'a fractional power with an even denominator': <MathNode>[
      ExponentNode(
        base: lit('x'),
        power: <MathNode>[FractionNode(num: lit('3'), den: lit('2'))],
      ),
    ],
    'a variable power': <MathNode>[
      ExponentNode(base: lit('2'), power: lit('x')),
    ],
    'a power of a variable to a variable': <MathNode>[
      ExponentNode(base: lit('y'), power: lit('x')),
    ],
    'roots': <MathNode>[
      RootNode(index: lit('3'), radicand: lit('x')),
      plus(),
      RootNode(isSquareRoot: true, radicand: lit('y')),
      plus(),
      RootNode(index: lit('z'), radicand: lit('8')),
    ],
    'a fraction': <MathNode>[FractionNode(num: lit('x+1'), den: lit('y-2'))],
    'logarithms': <MathNode>[
      LogNode(base: lit('2'), argument: lit('x')),
      plus(),
      LogNode(isNaturalLog: true, argument: lit('y')),
      plus(),
      LogNode(base: lit('z'), argument: lit('3')),
    ],
    'trigonometry': <MathNode>[
      call('sin', lit('x')),
      plus(),
      call('cos', lit('y')),
      minus(),
      call('tan', lit('z')),
    ],
    'inverse trigonometry': <MathNode>[
      call('asin', lit('x/5')),
      plus(),
      call('acos', lit('y/5')),
      plus(),
      call('atan', lit('z')),
    ],
    'hyperbolic functions': <MathNode>[
      call('sinh', lit('x')),
      plus(),
      call('cosh', lit('y')),
      plus(),
      call('tanh', lit('100z')),
    ],
    'inverse hyperbolic functions': <MathNode>[
      call('asinh', lit('x')),
      plus(),
      call('acosh', lit('y')),
      plus(),
      call('atanh', lit('z/5')),
    ],
    'absolute values': <MathNode>[
      call('abs', lit('x-y')),
      plus(),
      call('abs', lit('-3')),
    ],
    'arg of a variable, which has no real value': <MathNode>[
      call('arg', lit('x')),
    ],
    'constants': <MathNode>[
      ConstantNode('π'),
      LiteralNode(text: 'x+'),
      ConstantNode('e'),
    ],
    'permutations and combinations': <MathNode>[
      PermutationNode(n: lit('7'), r: lit('x')),
      plus(),
      CombinationNode(n: lit('9'), r: lit('y')),
    ],
    'a definite integral with a variable around it': <MathNode>[
      IntegralNode(
        variable: lit('t'),
        lower: lit('0'),
        upper: lit('1'),
        body: lit('t^2'),
      ),
      LiteralNode(text: '+x'),
    ],
  };

  /// Points to read at: a spread, plus the values that break formulas.
  final math.Random random = math.Random(3);
  final List<double> special = <double>[0, -0.0, 1, -1, 2, 1e-9, -1e-9, 1e9];
  final List<(double, double, double)> points = <(double, double, double)>[
    for (final double a in special)
      for (final double b in <double>[0.5, -2, 3]) (a, b, a - b),
    for (int i = 0; i < 300; i++)
      (
        random.nextDouble() * 10 - 5,
        random.nextDouble() * 10 - 5,
        random.nextDouble() * 10 - 5,
      ),
  ];

  /// The same answer, or both undefined, or the same infinity.
  void expectSame(double compiled, double walked, String where) {
    if (walked.isNaN) {
      expect(compiled.isNaN, isTrue, reason: '$where: walk NaN, got $compiled');
      return;
    }
    if (walked.isInfinite) {
      expect(compiled, walked, reason: where);
      return;
    }
    expect(
      (compiled - walked).abs(),
      lessThanOrEqualTo(1e-12 * (1 + walked.abs())),
      reason: '$where: compiled $compiled, walked $walked',
    );
  }

  double guarded(double Function() read) {
    try {
      return read();
    } catch (_) {
      return double.nan;
    }
  }

  group('real', () {
    const List<String> xyz = <String>['x', 'y', 'z'];
    for (final MapEntry<String, List<MathNode>> line in real.entries) {
      test(line.key, () {
        final Expr e = compile(line.value);
        final RealFunction f = e.compileReal(xyz);
        final Float64List slots = Float64List(3);
        int defined = 0;
        for (final (double x, double y, double z) in points) {
          slots[0] = x;
          slots[1] = y;
          slots[2] = z;
          final double walked = guarded(
            () => e.evalWith(<String, double>{'x': x, 'y': y, 'z': z}),
          );
          if (walked.isFinite) defined++;
          expectSame(
            guarded(() => f(slots)),
            walked,
            '${line.key} at ($x, $y, $z)',
          );
        }
        // Agreement means nothing if both sides were undefined throughout.
        if (!line.key.startsWith('arg')) {
          expect(defined, greaterThan(points.length ~/ 10), reason: line.key);
        }
      });
    }

    test('in other coordinates, by slot rather than by name', () {
      final Expr e = compile(lit('r^2+θ'));
      final RealFunction f = e.compileReal(const <String>['r', 'θ', 'z']);
      expect(f(Float64List.fromList(<double>[3, 0.5, 9])), 9.5);
    });

    test('a variable not given a slot is unbound, as in the walk', () {
      final Expr e = compile(lit('x+y'));
      final RealFunction f = e.compileReal(const <String>['x']);
      expect(
        () => f(Float64List.fromList(<double>[1])),
        throwsA(isA<UnboundVariableError>()),
      );
      expect(
        () => e.evalWith(<String, double>{'x': 1}),
        throwsA(isA<UnboundVariableError>()),
      );
    });
  });

  group('complex', () {
    final Map<String, List<MathNode>> complex = <String, List<MathNode>>{
      'a polynomial': <MathNode>[
        ExponentNode(base: <MathNode>[ComplexVariableNode()], power: lit('3')),
        LiteralNode(text: '-1'),
      ],
      'a negative power': <MathNode>[
        ExponentNode(base: <MathNode>[ComplexVariableNode()], power: lit('-2')),
      ],
      'a fractional power': <MathNode>[
        ExponentNode(
          base: <MathNode>[ComplexVariableNode()],
          power: <MathNode>[FractionNode(num: lit('1'), den: lit('2'))],
        ),
      ],
      'a quotient': <MathNode>[
        FractionNode(num: lit('1'), den: <MathNode>[ComplexVariableNode()]),
      ],
      'functions': <MathNode>[
        call('sin', <MathNode>[ComplexVariableNode()]),
        plus(),
        call('cosh', <MathNode>[ComplexVariableNode()]),
        plus(),
        call('asin', <MathNode>[ComplexVariableNode()]),
        plus(),
        call('atanh', <MathNode>[ComplexVariableNode()]),
      ],
      'logs and roots': <MathNode>[
        LogNode(
          isNaturalLog: true,
          argument: <MathNode>[ComplexVariableNode()],
        ),
        plus(),
        RootNode(
          isSquareRoot: true,
          radicand: <MathNode>[ComplexVariableNode()],
        ),
      ],
      'readings of a complex number': <MathNode>[
        call('abs', <MathNode>[ComplexVariableNode()]),
        plus(),
        call('arg', <MathNode>[ComplexVariableNode()]),
        plus(),
        call('re', <MathNode>[ComplexVariableNode()]),
      ],
      'x + iy': lit('x+iy'),
    };

    void expectSameComplex(Complex compiled, Complex walked, String where) {
      expectSame(compiled.real, walked.real, '$where (real part)');
      expectSame(compiled.imag, walked.imag, '$where (imaginary part)');
    }

    Complex guardedComplex(Complex Function() read) {
      try {
        return read();
      } catch (_) {
        return const Complex(double.nan, double.nan);
      }
    }

    const List<String> plane = <String>['z', 'x', 'y', 'i'];
    for (final MapEntry<String, List<MathNode>> line in complex.entries) {
      test(line.key, () {
        final Expr e = compile(line.value);
        final ComplexFunction f = e.compileComplex(plane);
        int defined = 0;
        for (final (double x, double y, double _) in points) {
          final List<Complex> slots = <Complex>[
            Complex(x, y),
            Complex(x, 0),
            Complex(y, 0),
            const Complex(0, 1),
          ];
          final Complex walked = guardedComplex(
            () => e.evalComplexWith(<String, Complex>{
              'z': slots[0],
              'x': slots[1],
              'y': slots[2],
              'i': slots[3],
            }),
          );
          if (walked.real.isFinite && walked.imag.isFinite) defined++;
          expectSameComplex(
            guardedComplex(() => f(slots)),
            walked,
            '${line.key} at $x + ${y}i',
          );
        }
        expect(defined, greaterThan(points.length ~/ 10), reason: line.key);
      });
    }
  });
}
