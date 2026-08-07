import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('IntExpr', () {
    test('creates integer from BigInt', () {
      final expr = IntExpr(BigInt.from(42));
      expect(expr.value, BigInt.from(42));
    });

    test('creates integer from int', () {
      final expr = IntExpr.from(42);
      expect(expr.value, BigInt.from(42));
    });

    test('simplify returns self', () {
      final expr = IntExpr.from(42);
      expect(expr.simplify(), expr);
    });

    test('toDouble returns correct value', () {
      expect(IntExpr.from(42).toDouble(), 42.0);
      expect(IntExpr.from(-17).toDouble(), -17.0);
      expect(IntExpr.from(0).toDouble(), 0.0);
    });

    test('isZero', () {
      expect(IntExpr.zero.isZero, true);
      expect(IntExpr.from(0).isZero, true);
      expect(IntExpr.from(1).isZero, false);
      expect(IntExpr.from(-1).isZero, false);
    });

    test('isOne', () {
      expect(IntExpr.one.isOne, true);
      expect(IntExpr.from(1).isOne, true);
      expect(IntExpr.from(0).isOne, false);
      expect(IntExpr.from(2).isOne, false);
    });

    test('isRational', () {
      expect(IntExpr.from(42).isRational, true);
    });

    test('isInteger', () {
      expect(IntExpr.from(42).isInteger, true);
    });

    test('negate', () {
      expect((IntExpr.from(5).negate() as IntExpr).value, BigInt.from(-5));
      expect((IntExpr.from(-3).negate() as IntExpr).value, BigInt.from(3));
      expect((IntExpr.from(0).negate() as IntExpr).value, BigInt.zero);
    });

    test('structurallyEquals', () {
      expect(IntExpr.from(5).structurallyEquals(IntExpr.from(5)), true);
      expect(IntExpr.from(5).structurallyEquals(IntExpr.from(6)), false);
    });

    test('toMathNode', () {
      final nodes = IntExpr.from(42).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '42');
    });

    test('negative integer toMathNode', () {
      final nodes = IntExpr.from(-42).toMathNode();
      expect(nodes.length, 1);
      expect((nodes[0] as LiteralNode).text, '\u221242');
    });

    test('add integers', () {
      final a = IntExpr.from(5);
      final b = IntExpr.from(3);
      final result = a.add(b);
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(8));
    });

    test('subtract integers', () {
      final a = IntExpr.from(5);
      final b = IntExpr.from(3);
      final result = a.subtract(b);
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(2));
    });

    test('multiply integers', () {
      final a = IntExpr.from(5);
      final b = IntExpr.from(3);
      final result = a.multiply(b);
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(15));
    });

    test('divide integers to fraction', () {
      final a = IntExpr.from(5);
      final b = IntExpr.from(3);
      final result = a.divide(b).simplify();
      expect(result, isA<FracExpr>());
    });

    test('divide integers to integer when divisible', () {
      final a = IntExpr.from(6);
      final b = IntExpr.from(3);
      final result = a.divide(b).simplify();
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(2));
    });

    test('power of integers', () {
      final result = IntExpr.from(2).power(IntExpr.from(3));
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(8));
    });

    test('power of zero', () {
      final result = IntExpr.from(5).power(IntExpr.zero);
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.one);
    });

    test('power of one', () {
      final result = IntExpr.from(5).power(IntExpr.one);
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(5));
    });

    test('negative power', () {
      final result = IntExpr.from(2).power(IntExpr.from(-2)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), 0.25);
    });

    test('copy', () {
      final original = IntExpr.from(42);
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('termSignature', () {
      expect(IntExpr.from(5).termSignature, 'int:1');
      expect(IntExpr.from(100).termSignature, 'int:1');
    });

    test('coefficient and baseExpr', () {
      final expr = IntExpr.from(5);
      expect(expr.coefficient, expr);
      expect(expr.baseExpr.isOne, true);
    });

    test('toString', () {
      expect(IntExpr.from(42).toString(), '42');
      expect(IntExpr.from(-7).toString(), '\u22127');
    });

    test('add integer to fraction', () {
      final a = IntExpr.from(2);
      final b = FracExpr.from(1, 4);
      final result = a.add(b).simplify();
      expect(result.toDouble(), 2.25);
    });

    test('multiply integer by fraction', () {
      final a = IntExpr.from(3);
      final b = FracExpr.from(1, 2);
      final result = a.multiply(b).simplify();
      expect(result.toDouble(), 1.5);
    });

    test('divide integer by fraction', () {
      final a = IntExpr.from(2);
      final b = FracExpr.from(1, 2);
      final result = a.divide(b).simplify();
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(4));
    });

    test('large power', () {
      final result = IntExpr.from(2).power(IntExpr.from(10));
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(1024));
    });
  });

  group('FracExpr', () {
    test('creates fraction', () {
      final frac = FracExpr.from(3, 4);
      expect(frac.numerator.value, BigInt.from(3));
      expect(frac.denominator.value, BigInt.from(4));
    });

    test('simplify reduces to lowest terms', () {
      final frac = FracExpr.from(6, 8).simplify();
      expect(frac, isA<FracExpr>());
      final f = frac as FracExpr;
      expect(f.numerator.value, BigInt.from(3));
      expect(f.denominator.value, BigInt.from(4));
    });

    test('simplify returns integer when denominator is 1', () {
      final frac = FracExpr.from(6, 3).simplify();
      expect(frac, isA<IntExpr>());
      expect((frac as IntExpr).value, BigInt.from(2));
    });

    test('simplify zero numerator', () {
      final frac = FracExpr.from(0, 5).simplify();
      expect(frac, isA<IntExpr>());
      expect(frac.isZero, true);
    });

    test('simplify negative denominator', () {
      final frac = FracExpr.from(3, -4).simplify() as FracExpr;
      expect(frac.numerator.value, BigInt.from(-3));
      expect(frac.denominator.value, BigInt.from(4));
    });

    test('simplify negative numerator and denominator', () {
      final frac = FracExpr.from(-3, -4).simplify() as FracExpr;
      expect(frac.numerator.value, BigInt.from(3));
      expect(frac.denominator.value, BigInt.from(4));
    });

    test('toDouble', () {
      expect(FracExpr.from(1, 2).toDouble(), 0.5);
      expect(FracExpr.from(3, 4).toDouble(), 0.75);
      expect(FracExpr.from(1, 3).toDouble(), closeTo(0.3333, 0.001));
    });

    test('isZero', () {
      expect(FracExpr.from(0, 5).isZero, true);
      expect(FracExpr.from(1, 5).isZero, false);
    });

    test('isOne', () {
      expect(FracExpr.from(3, 3).isOne, true);
      expect(FracExpr.from(5, 5).isOne, true);
      expect(FracExpr.from(1, 2).isOne, false);
    });

    test('isRational', () {
      expect(FracExpr.from(1, 2).isRational, true);
    });

    test('isInteger', () {
      expect(FracExpr.from(4, 2).isInteger, true);
      expect(FracExpr.from(3, 2).isInteger, false);
    });

    test('negate', () {
      final frac = FracExpr.from(3, 4).negate() as FracExpr;
      expect(frac.numerator.value, BigInt.from(-3));
    });

    test('structurallyEquals', () {
      expect(FracExpr.from(1, 2).structurallyEquals(FracExpr.from(1, 2)), true);
      expect(FracExpr.from(1, 2).structurallyEquals(FracExpr.from(2, 4)), true);
      expect(
        FracExpr.from(1, 2).structurallyEquals(FracExpr.from(1, 3)),
        false,
      );
    });

    test('structurallyEquals with integer', () {
      expect(FracExpr.from(4, 2).structurallyEquals(IntExpr.from(2)), true);
      expect(FracExpr.from(3, 2).structurallyEquals(IntExpr.from(1)), false);
    });

    test('toMathNode', () {
      final nodes = FracExpr.from(3, 4).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<FractionNode>());
    });

    test('toMathNode for integer result', () {
      final nodes = FracExpr.from(6, 3).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '2');
    });

    test('add fractions', () {
      final result = FracExpr.from(1, 4).add(FracExpr.from(1, 4)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), 0.5);
    });

    test('add fraction and integer', () {
      final result = FracExpr.from(1, 2).add(IntExpr.from(1)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), 1.5);
    });

    test('subtract fractions', () {
      final result =
          FracExpr.from(3, 4).subtract(FracExpr.from(1, 4)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), 0.5);
    });

    test('multiply fractions', () {
      final result =
          FracExpr.from(1, 2).multiply(FracExpr.from(2, 3)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), closeTo(0.3333, 0.001));
    });

    test('multiply fraction by integer', () {
      final result = FracExpr.from(1, 2).multiply(IntExpr.from(4)).simplify();
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(2));
    });

    test('divide fractions', () {
      final result = FracExpr.from(1, 2).divide(FracExpr.from(1, 4)).simplify();
      expect(result, isA<IntExpr>());
      expect(result.toDouble(), 2.0);
    });

    test('divide fraction by integer', () {
      final result = FracExpr.from(1, 2).divide(IntExpr.from(2)).simplify();
      expect(result, isA<FracExpr>());
      expect(result.toDouble(), 0.25);
    });

    test('copy', () {
      final original = FracExpr.from(3, 4);
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('termSignature', () {
      expect(FracExpr.from(1, 2).termSignature, 'int:1');
    });

    test('toString', () {
      expect(FracExpr.from(3, 4).toString(), '3/4');
      expect(FracExpr.from(6, 3).simplify().toString(), '2');
    });

    test('coefficient and baseExpr', () {
      final frac = FracExpr.from(3, 4);
      expect(frac.coefficient, frac);
      expect(frac.baseExpr.isOne, true);
    });
  });

  group('ConstExpr', () {
    test('pi value', () {
      expect(ConstExpr.pi.toDouble(), closeTo(3.14159, 0.00001));
    });

    test('e value', () {
      expect(ConstExpr.e.toDouble(), closeTo(2.71828, 0.00001));
    });

    test('phi value', () {
      expect(ConstExpr.phi.toDouble(), closeTo(1.61803, 0.00001));
    });

    test('isRational', () {
      expect(ConstExpr.pi.isRational, false);
      expect(ConstExpr.e.isRational, false);
    });

    test('isZero', () {
      expect(ConstExpr.pi.isZero, false);
    });

    test('isOne', () {
      expect(ConstExpr.pi.isOne, false);
    });

    test('isInteger', () {
      expect(ConstExpr.pi.isInteger, false);
    });

    test('simplify returns self', () {
      expect(ConstExpr.pi.simplify(), ConstExpr.pi);
    });

    test('toMathNode for pi', () {
      final nodes = ConstExpr.pi.toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, 'π');
    });

    test('toMathNode for e', () {
      final nodes = ConstExpr.e.toMathNode();
      expect(nodes.length, 1);
      expect((nodes[0] as LiteralNode).text, 'e');
    });

    test('toMathNode for phi', () {
      final nodes = ConstExpr.phi.toMathNode();
      expect(nodes.length, 1);
      expect((nodes[0] as LiteralNode).text, 'φ');
    });

    test('structurallyEquals', () {
      expect(ConstExpr.pi.structurallyEquals(ConstExpr.pi), true);
      expect(ConstExpr.pi.structurallyEquals(ConstExpr.e), false);
    });

    test('copy', () {
      final copied = ConstExpr.pi.copy();
      expect(copied.structurallyEquals(ConstExpr.pi), true);
    });

    test('negate', () {
      final negPi = ConstExpr.pi.negate();
      expect(negPi, isA<ProdExpr>());
      expect(negPi.toDouble(), closeTo(-3.14159, 0.00001));
    });

    test('termSignature', () {
      expect(ConstExpr.pi.termSignature, 'const:pi');
      expect(ConstExpr.e.termSignature, 'const:e');
    });

    test('coefficient and baseExpr', () {
      expect(ConstExpr.pi.coefficient.isOne, true);
      expect(ConstExpr.pi.baseExpr, ConstExpr.pi);
    });

    test('toString', () {
      expect(ConstExpr.pi.toString(), 'π');
      expect(ConstExpr.e.toString(), 'e');
      expect(ConstExpr.phi.toString(), 'φ');
    });

    test('epsilon0 value', () {
      expect(ConstExpr.epsilon0.toDouble(), closeTo(8.854e-12, 1e-15));
    });

    test('mu0 value', () {
      expect(ConstExpr.mu0.toDouble(), closeTo(1.256e-6, 1e-9));
    });
  });

  group('MathNodeToExpr Integration', () {
    test('converts ConstantNode(mu0)', () {
      final nodes = [ConstantNode('\u03BC\u2080')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<ConstExpr>());
      expect((expr as ConstExpr).type, ConstType.mu0);
    });

    test('1/mu0 in ExactMathEngine', () {
      final nodes = [
        LiteralNode(text: '1'),
        LiteralNode(text: '/'),
        ConstantNode('\u03BC\u2080'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, isNotNull);
      expect(result.numerical!.isInfinite, isFalse);
      expect(result.toExactString(), contains('μ₀'));
    });

    test('implicit multiplication with ConstantNode', () {
      // 2 mu0
      final nodes = [LiteralNode(text: '2'), ConstantNode('\u03BC\u2080')];
      final result = ExactMathEngine.evaluate(nodes);
      final expectedValue = 2 * 1.25663706212e-6;
      expect(result.numerical, closeTo(expectedValue, 1e-12));
      // Result string may have middle dot for multiplication: 2·μ₀
      expect(result.toExactString().replaceAll('\u00B7', ''), contains('2μ₀'));
    });

    test('handles mu0 in LiteralNode', () {
      final nodes = [LiteralNode(text: '1/\u03BC\u2080')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, isNotNull);
      expect(result.numerical!.isInfinite, isFalse);
      expect(result.toExactString(), contains('μ₀'));
    });
  });

  group('SumExpr', () {
    test('simplify empty sum', () {
      expect(SumExpr([]).simplify(), isA<IntExpr>());
      expect(SumExpr([]).simplify().isZero, true);
    });

    test('simplify single term sum', () {
      final term = IntExpr.from(5);
      final sum = SumExpr([term]).simplify();
      expect(sum, isA<IntExpr>());
      expect((sum as IntExpr).value, BigInt.from(5));
    });

    test('add integers', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]).simplify();
      expect(sum, isA<IntExpr>());
      expect((sum as IntExpr).value, BigInt.from(7));
    });

    test('add fractions', () {
      final sum =
          SumExpr([FracExpr.from(1, 2), FracExpr.from(1, 3)]).simplify();
      expect(sum.toDouble(), closeTo(0.8333, 0.001));
    });

    test('add integer and fraction', () {
      final sum = SumExpr([IntExpr.from(1), FracExpr.from(1, 2)]).simplify();
      expect(sum.toDouble(), 1.5);
    });

    test('combine like terms - integers', () {
      final sum =
          SumExpr([
            IntExpr.from(3),
            IntExpr.from(4),
            IntExpr.from(5),
          ]).simplify();
      expect(sum, isA<IntExpr>());
      expect((sum as IntExpr).value, BigInt.from(12));
    });

    test('combine like surds', () {
      // √2 + √2 = 2√2
      final sum =
          SumExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            RootExpr.sqrt(IntExpr.from(2)),
          ]).simplify();
      expect(sum.toDouble(), closeTo(2.828, 0.001));
    });

    test('combine like surds with coefficients', () {
      // 2√2 + 3√2 = 5√2
      final sum =
          SumExpr([
            ProdExpr([IntExpr.from(2), RootExpr.sqrt(IntExpr.from(2))]),
            ProdExpr([IntExpr.from(3), RootExpr.sqrt(IntExpr.from(2))]),
          ]).simplify();
      expect(sum.toDouble(), closeTo(7.071, 0.001));
    });

    test('factor common variable', () {
      final sum =
          SumExpr([
            ProdExpr([VarExpr('x'), VarExpr('y')]),
            ProdExpr([VarExpr('x'), VarExpr('z')]),
          ]).simplify();
      expect(sum, isA<ProdExpr>());
      final prod = sum as ProdExpr;
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
      );
      final sumFactor = prod.factors.firstWhere((f) => f is SumExpr) as SumExpr;
      expect(sumFactor.terms.length, equals(2));
      expect(
        sumFactor.terms.any((term) => term is VarExpr && term.name == 'y'),
        isTrue,
      );
      expect(
        sumFactor.terms.any((term) => term is VarExpr && term.name == 'z'),
        isTrue,
      );
    });

    test('factor common variable powers', () {
      final sum =
          SumExpr([
            ProdExpr([PowExpr(VarExpr('x'), IntExpr.from(2)), VarExpr('y')]),
            ProdExpr([VarExpr('x'), VarExpr('y')]),
          ]).simplify();
      expect(sum, isA<ProdExpr>());
      final prod = sum as ProdExpr;
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'y'),
        isTrue,
      );
      final sumFactor = prod.factors.firstWhere((f) => f is SumExpr) as SumExpr;
      expect(sumFactor.terms.length, equals(2));
    });

    test('preserve order of unlike terms', () {
      // √2 + 3 + log(7) should stay in that order
      final sum =
          SumExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            IntExpr.from(3),
            LogExpr(IntExpr.from(10), IntExpr.from(7)),
          ]).simplify();

      expect(sum, isA<SumExpr>());
      final s = sum as SumExpr;
      expect(s.terms.length, 3);
      expect(s.terms[0], isA<RootExpr>());
      expect(s.terms[1], isA<IntExpr>());
      expect(s.terms[2], isA<LogExpr>());
    });

    test('combine like terms preserving first occurrence position', () {
      // √5 + 3 + 1 should give √5 + 4 (not 4 + √5)
      final sum =
          SumExpr([
            RootExpr.sqrt(IntExpr.from(5)),
            IntExpr.from(3),
            IntExpr.from(1),
          ]).simplify();

      expect(sum, isA<SumExpr>());
      final s = sum as SumExpr;
      expect(s.terms.length, 2);
      expect(s.terms[0], isA<RootExpr>()); // √5 first
      expect(s.terms[1], isA<IntExpr>()); // 4 second
      expect((s.terms[1] as IntExpr).value, BigInt.from(4));
    });

    test('terms cancel to zero', () {
      final sum = SumExpr([IntExpr.from(5), IntExpr.from(-5)]).simplify();
      expect(sum.isZero, true);
    });

    test('flatten nested sums', () {
      final inner = SumExpr([IntExpr.from(1), IntExpr.from(2)]);
      final outer = SumExpr([inner, IntExpr.from(3)]).simplify();
      expect(outer, isA<IntExpr>());
      expect((outer as IntExpr).value, BigInt.from(6));
    });

    test('remove zeros', () {
      final sum =
          SumExpr([IntExpr.from(5), IntExpr.zero, IntExpr.from(3)]).simplify();
      expect(sum, isA<IntExpr>());
      expect((sum as IntExpr).value, BigInt.from(8));
    });

    test('toDouble', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      expect(sum.toDouble(), 7.0);
    });

    test('negate', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      final negated = sum.negate().simplify();
      expect(negated.toDouble(), -7.0);
    });

    test('toMathNode with positive terms', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      final nodes = sum.toMathNode();
      expect(nodes.any((n) => n is LiteralNode && (n).text == '+'), true);
    });

    test('toMathNode with negative term', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(-4)]);
      final nodes = sum.toMathNode();
      expect(nodes.any((n) => n is LiteralNode && (n).text == '−'), true);
    });

    test('copy', () {
      final original = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('isZero', () {
      expect(SumExpr([IntExpr.zero, IntExpr.zero]).isZero, true);
      expect(SumExpr([IntExpr.from(1), IntExpr.zero]).isZero, false);
    });

    test('isOne', () {
      expect(SumExpr([IntExpr.from(1)]).isOne, false);
    });

    test('isRational', () {
      expect(SumExpr([IntExpr.from(1), FracExpr.from(1, 2)]).isRational, true);
      expect(
        SumExpr([IntExpr.from(1), RootExpr.sqrt(IntExpr.from(2))]).isRational,
        false,
      );
    });

    test('termSignature', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      expect(sum.termSignature.startsWith('sum:'), true);
    });

    test('coefficient and baseExpr', () {
      final sum = SumExpr([IntExpr.from(3), IntExpr.from(4)]);
      expect(sum.coefficient.isOne, true);
      expect(sum.baseExpr, sum);
    });
  });

  group('ProdExpr', () {
    test('simplify empty product', () {
      expect(ProdExpr([]).simplify().isOne, true);
    });

    test('simplify single factor product', () {
      final prod = ProdExpr([IntExpr.from(5)]).simplify();
      expect(prod, isA<IntExpr>());
      expect((prod as IntExpr).value, BigInt.from(5));
    });

    test('multiply integers', () {
      final prod = ProdExpr([IntExpr.from(3), IntExpr.from(4)]).simplify();
      expect(prod, isA<IntExpr>());
      expect((prod as IntExpr).value, BigInt.from(12));
    });

    test('multiply fractions', () {
      final prod =
          ProdExpr([FracExpr.from(1, 2), FracExpr.from(2, 3)]).simplify();
      expect(prod.toDouble(), closeTo(0.3333, 0.001));
    });

    test('multiply with zero', () {
      final prod = ProdExpr([IntExpr.from(5), IntExpr.zero]).simplify();
      expect(prod.isZero, true);
    });

    test('multiply with one', () {
      final prod = ProdExpr([IntExpr.from(5), IntExpr.one]).simplify();
      expect(prod, isA<IntExpr>());
      expect((prod as IntExpr).value, BigInt.from(5));
    });

    test('combine numeric factors', () {
      // 2 * 3 * √5 = 6√5
      final prod =
          ProdExpr([
            IntExpr.from(2),
            IntExpr.from(3),
            RootExpr.sqrt(IntExpr.from(5)),
          ]).simplify();
      expect(prod.toDouble(), closeTo(13.416, 0.001));
    });

    test('combine same roots', () {
      // √2 * √3 = √6
      final prod =
          ProdExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            RootExpr.sqrt(IntExpr.from(3)),
          ]).simplify();

      // Result should be √6
      expect(prod.toDouble(), closeTo(2.449, 0.001));
    });

    test('√2 * √2 = 2', () {
      final prod =
          ProdExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            RootExpr.sqrt(IntExpr.from(2)),
          ]).simplify();
      expect(prod, isA<IntExpr>());
      expect((prod as IntExpr).value, BigInt.from(2));
    });

    test('flatten nested products', () {
      final inner = ProdExpr([IntExpr.from(2), IntExpr.from(3)]);
      final outer = ProdExpr([inner, IntExpr.from(4)]).simplify();
      expect(outer, isA<IntExpr>());
      expect((outer as IntExpr).value, BigInt.from(24));
    });

    test('toDouble', () {
      final prod = ProdExpr([IntExpr.from(3), IntExpr.from(4)]);
      expect(prod.toDouble(), 12.0);
    });

    test('negate', () {
      final prod = ProdExpr([IntExpr.from(3), IntExpr.from(4)]);
      final negated = prod.negate().simplify();
      expect(negated.toDouble(), -12.0);
    });

    test('coefficient and baseExpr', () {
      // 3 * √2
      final prod =
          ProdExpr([
            IntExpr.from(3),
            RootExpr.sqrt(IntExpr.from(2)),
          ]).simplify();

      expect(prod.coefficient.toDouble(), 3.0);
      expect(prod.baseExpr, isA<RootExpr>());
    });

    test('toMathNode', () {
      final prod = ProdExpr([IntExpr.from(3), IntExpr.from(4)]);
      final nodes = prod.toMathNode();
      expect(nodes.isNotEmpty, true);
    });

    test('toMathNode omits explicit multiply for c₀xy', () {
      final prod = ProdExpr([VarExpr('c₀'), VarExpr('x'), VarExpr('y')]);
      final nodes = prod.toMathNode();
      final literalTexts = nodes.whereType<LiteralNode>().map((n) => n.text);

      expect(literalTexts.contains('·'), isFalse);
      expect(literalTexts.toList(), equals(['c₀', 'x', 'y']));
    });

    test('toMathNode omits explicit multiply for x²y', () {
      final prod = ProdExpr([
        PowExpr(VarExpr('x'), IntExpr.from(2)),
        VarExpr('y'),
      ]);
      final nodes = prod.toMathNode();
      final hasDot = nodes.whereType<LiteralNode>().any((n) => n.text == '·');
      expect(hasDot, isFalse);
    });

    test(
      'toMathNode keeps explicit multiply between variable and function',
      () {
        final prod = ProdExpr([
          VarExpr('x'),
          TrigExpr(TrigFunc.sin, VarExpr('x')),
        ]);
        final nodes = prod.toMathNode();
        final hasDot = nodes.whereType<LiteralNode>().any((n) => n.text == '·');
        expect(hasDot, isTrue);
      },
    );

    test('copy', () {
      final original = ProdExpr([IntExpr.from(3), IntExpr.from(4)]);
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('termSignature for numeric product', () {
      final prod = ProdExpr([IntExpr.from(3), IntExpr.from(4)]);
      expect(prod.termSignature, 'int:1');
    });

    test('termSignature for product with surd', () {
      final prod =
          ProdExpr([
            IntExpr.from(3),
            RootExpr.sqrt(IntExpr.from(2)),
          ]).simplify();
      expect(prod.termSignature.contains('root'), true);
    });

    test('isZero', () {
      expect(ProdExpr([IntExpr.from(5), IntExpr.zero]).isZero, true);
      expect(ProdExpr([IntExpr.from(5), IntExpr.from(3)]).isZero, false);
    });

    test('isOne', () {
      expect(ProdExpr([IntExpr.one, IntExpr.one]).isOne, true);
      expect(ProdExpr([IntExpr.from(2), IntExpr.one]).isOne, false);
    });

    test('isRational', () {
      expect(ProdExpr([IntExpr.from(2), FracExpr.from(1, 2)]).isRational, true);
      expect(
        ProdExpr([IntExpr.from(2), RootExpr.sqrt(IntExpr.from(2))]).isRational,
        false,
      );
    });
  });

  group('PowExpr', () {
    test('x^0 = 1', () {
      final pow = PowExpr(IntExpr.from(5), IntExpr.zero).simplify();
      expect(pow.isOne, true);
    });

    test('x^1 = x', () {
      final pow = PowExpr(IntExpr.from(5), IntExpr.one).simplify();
      expect(pow, isA<IntExpr>());
      expect((pow as IntExpr).value, BigInt.from(5));
    });

    test('0^n = 0', () {
      final pow = PowExpr(IntExpr.zero, IntExpr.from(5)).simplify();
      expect(pow.isZero, true);
    });

    test('1^n = 1', () {
      final pow = PowExpr(IntExpr.one, IntExpr.from(100)).simplify();
      expect(pow.isOne, true);
    });

    test('integer power', () {
      final pow = PowExpr(IntExpr.from(2), IntExpr.from(10)).simplify();
      expect(pow, isA<IntExpr>());
      expect((pow as IntExpr).value, BigInt.from(1024));
    });

    test('negative power gives fraction', () {
      final pow = PowExpr(IntExpr.from(2), IntExpr.from(-3)).simplify();
      expect(pow.toDouble(), 0.125);
    });

    test('fractional power gives root', () {
      // 8^(1/3) = cube root of 8 = 2
      final pow = PowExpr(IntExpr.from(8), FracExpr.from(1, 3)).simplify();
      expect(pow.toDouble(), closeTo(2.0, 0.001));
    });

    test('(a^m)^n = a^(m*n)', () {
      // (2^2)^3 = 2^6 = 64
      final inner = PowExpr(IntExpr.from(2), IntExpr.from(2));
      final outer = PowExpr(inner, IntExpr.from(3)).simplify();
      expect(outer, isA<IntExpr>());
      expect((outer as IntExpr).value, BigInt.from(64));
    });

    test('toDouble', () {
      final pow = PowExpr(IntExpr.from(2), IntExpr.from(3));
      expect(pow.toDouble(), 8.0);
    });

    test('toMathNode', () {
      final pow = PowExpr(IntExpr.from(2), IntExpr.from(3));
      final nodes = pow.toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<ExponentNode>());
    });

    test('copy', () {
      final original = PowExpr(IntExpr.from(2), IntExpr.from(3));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = PowExpr(IntExpr.from(2), IntExpr.from(3));
      final b = PowExpr(IntExpr.from(2), IntExpr.from(3));
      final c = PowExpr(IntExpr.from(2), IntExpr.from(4));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(PowExpr(IntExpr.zero, IntExpr.from(5)).isZero, true);
      expect(PowExpr(IntExpr.from(2), IntExpr.from(3)).isZero, false);
    });

    test('isOne', () {
      expect(PowExpr(IntExpr.one, IntExpr.from(100)).isOne, true);
      expect(PowExpr(IntExpr.from(5), IntExpr.zero).isOne, true);
    });

    test('isRational', () {
      expect(PowExpr(IntExpr.from(2), IntExpr.from(3)).isRational, true);
      expect(PowExpr(IntExpr.from(2), IntExpr.from(-1)).isRational, false);
    });

    test('isInteger', () {
      expect(PowExpr(IntExpr.from(2), IntExpr.from(3)).isInteger, true);
      expect(PowExpr(IntExpr.from(2), IntExpr.from(-1)).isInteger, false);
    });

    test('negate', () {
      final pow = PowExpr(IntExpr.from(2), IntExpr.from(3));
      final negated = pow.negate().simplify();
      expect(negated.toDouble(), -8.0);
    });

    test('a^(m/n) simplification', () {
      // 4^(3/2) = (4^3)^(1/2) = √64 = 8
      final pow = PowExpr(IntExpr.from(4), FracExpr.from(3, 2)).simplify();
      expect(pow.toDouble(), closeTo(8.0, 0.001));
    });
  });

  group('RootExpr', () {
    test('√1 = 1', () {
      final root = RootExpr.sqrt(IntExpr.one).simplify();
      expect(root.isOne, true);
    });

    test('√0 = 0', () {
      final root = RootExpr.sqrt(IntExpr.zero).simplify();
      expect(root.isZero, true);
    });

    test('√4 = 2', () {
      final root = RootExpr.sqrt(IntExpr.from(4)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(2));
    });

    test('√9 = 3', () {
      final root = RootExpr.sqrt(IntExpr.from(9)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(3));
    });

    test('√8 = 2√2', () {
      final root = RootExpr.sqrt(IntExpr.from(8)).simplify();
      expect(root.toDouble(), closeTo(2.828, 0.001));
      expect(root, isA<ProdExpr>());
    });

    test('√72 = 6√2', () {
      final root = RootExpr.sqrt(IntExpr.from(72)).simplify();
      expect(root.toDouble(), closeTo(8.485, 0.001));
    });

    test('√18 = 3√2', () {
      final root = RootExpr.sqrt(IntExpr.from(18)).simplify();
      expect(root.toDouble(), closeTo(4.243, 0.001));
    });

    test('√2 stays as √2', () {
      final root = RootExpr.sqrt(IntExpr.from(2)).simplify();
      expect(root, isA<RootExpr>());
    });

    test('cube root of 8 = 2', () {
      final root = RootExpr(IntExpr.from(8), IntExpr.from(3)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(2));
    });

    test('cube root of 27 = 3', () {
      final root = RootExpr(IntExpr.from(27), IntExpr.from(3)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(3));
    });

    test('4th root of 16 = 2', () {
      final root = RootExpr(IntExpr.from(16), IntExpr.from(4)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(2));
    });

    test('toDouble', () {
      expect(RootExpr.sqrt(IntExpr.from(2)).toDouble(), closeTo(1.414, 0.001));
      expect(RootExpr.sqrt(IntExpr.from(3)).toDouble(), closeTo(1.732, 0.001));
    });

    test('isRational for perfect square', () {
      expect(RootExpr.sqrt(IntExpr.from(4)).isRational, true);
    });

    test('isRational for non-perfect square', () {
      expect(RootExpr.sqrt(IntExpr.from(2)).isRational, false);
    });

    test('toMathNode for unsimplified root', () {
      final nodes = RootExpr.sqrt(IntExpr.from(2)).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<RootNode>());
    });

    test('toMathNode for simplified perfect square', () {
      final nodes = RootExpr.sqrt(IntExpr.from(4)).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '2');
    });

    test('copy', () {
      final original = RootExpr.sqrt(IntExpr.from(2));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('termSignature', () {
      final root1 = RootExpr.sqrt(IntExpr.from(2)).simplify();
      final root2 = RootExpr.sqrt(IntExpr.from(2)).simplify();
      final root3 = RootExpr.sqrt(IntExpr.from(3)).simplify();

      expect(root1.termSignature, root2.termSignature);
      expect(root1.termSignature != root3.termSignature, true);
    });

    test('structurallyEquals', () {
      final a = RootExpr.sqrt(IntExpr.from(2));
      final b = RootExpr.sqrt(IntExpr.from(2));
      final c = RootExpr.sqrt(IntExpr.from(3));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(RootExpr.sqrt(IntExpr.zero).isZero, true);
      expect(RootExpr.sqrt(IntExpr.from(2)).isZero, false);
    });

    test('isOne', () {
      expect(RootExpr.sqrt(IntExpr.one).isOne, true);
      expect(RootExpr.sqrt(IntExpr.from(2)).isOne, false);
    });

    test('isInteger for perfect square', () {
      expect(RootExpr.sqrt(IntExpr.from(4)).isInteger, true);
    });

    test('isInteger for non-perfect square', () {
      expect(RootExpr.sqrt(IntExpr.from(2)).isInteger, false);
    });

    test('negate', () {
      final root = RootExpr.sqrt(IntExpr.from(2));
      final negated = root.negate().simplify();
      expect(negated.toDouble(), closeTo(-1.414, 0.001));
    });

    test('√(a/b) = √a / √b', () {
      final root = RootExpr.sqrt(FracExpr.from(1, 4)).simplify();
      expect(root.toDouble(), closeTo(0.5, 0.001));
    });

    test('√(a/b) with rationalization: √(56/5) = 2/5·√70', () {
      final root = RootExpr.sqrt(FracExpr.from(56, 5)).simplify();
      expect(root.toDouble(), closeTo(3.3466, 0.001));
      // Result is simplified to DivExpr(numerator:2√70, denominator:5)
      expect(root, isA<ProdExpr>());
    });

    test('√(a/b) with perfect square denominator: √(2/9) = 1/3·√2', () {
      final root = RootExpr.sqrt(FracExpr.from(2, 9)).simplify();
      expect(root.toDouble(), closeTo(0.4714, 0.001));
      // Result is simplified to DivExpr(numerator:√2, denominator:3)
      expect(root, isA<ProdExpr>());
    });

    test('cube root of negative number', () {
      final root = RootExpr(IntExpr.from(-8), IntExpr.from(3)).simplify();
      expect(root, isA<IntExpr>());
      expect((root as IntExpr).value, BigInt.from(-2));
    });
  });

  group('LogExpr', () {
    test('log_a(1) = 0', () {
      final log = LogExpr(IntExpr.from(10), IntExpr.one).simplify();
      expect(log.isZero, true);
    });

    test('log_a(a) = 1', () {
      final log = LogExpr(IntExpr.from(10), IntExpr.from(10)).simplify();
      expect(log.isOne, true);
    });

    test('log_2(8) = 3', () {
      final log = LogExpr(IntExpr.from(2), IntExpr.from(8)).simplify();
      expect(log, isA<IntExpr>());
      expect((log as IntExpr).value, BigInt.from(3));
    });

    test('log_10(100) = 2', () {
      final log = LogExpr(IntExpr.from(10), IntExpr.from(100)).simplify();
      expect(log, isA<IntExpr>());
      expect((log as IntExpr).value, BigInt.from(2));
    });

    test('log_10(1000) = 3', () {
      final log = LogExpr(IntExpr.from(10), IntExpr.from(1000)).simplify();
      expect(log, isA<IntExpr>());
      expect((log as IntExpr).value, BigInt.from(3));
    });

    test('log that cannot be simplified stays as log', () {
      final log = LogExpr(IntExpr.from(10), IntExpr.from(7)).simplify();
      expect(log, isA<LogExpr>());
    });

    test('natural log', () {
      final ln = LogExpr.ln(IntExpr.from(1)).simplify();
      expect(ln.isZero, true);
    });

    test('common log constructor', () {
      final log = LogExpr.log10(IntExpr.from(100)).simplify();
      expect(log, isA<IntExpr>());
      expect((log as IntExpr).value, BigInt.from(2));
    });

    test('toDouble', () {
      expect(
        LogExpr(IntExpr.from(10), IntExpr.from(100)).toDouble(),
        closeTo(2.0, 0.001),
      );
    });

    test('toDouble for natural log', () {
      expect(LogExpr.ln(ConstExpr.e).toDouble(), closeTo(1.0, 0.001));
    });

    test('isRational when simplifies to integer', () {
      expect(LogExpr(IntExpr.from(2), IntExpr.from(8)).isRational, true);
    });

    test('isRational when cannot simplify', () {
      expect(LogExpr(IntExpr.from(10), IntExpr.from(7)).isRational, false);
    });

    test('toMathNode for unsimplified log', () {
      final nodes = LogExpr(IntExpr.from(5), IntExpr.from(7)).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LogNode>());
    });

    test('toMathNode for simplified log', () {
      final nodes =
          LogExpr(IntExpr.from(2), IntExpr.from(8)).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '3');
    });

    test('copy', () {
      final original = LogExpr(IntExpr.from(10), IntExpr.from(7));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = LogExpr(IntExpr.from(10), IntExpr.from(7));
      final b = LogExpr(IntExpr.from(10), IntExpr.from(7));
      final c = LogExpr(IntExpr.from(10), IntExpr.from(8));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(LogExpr(IntExpr.from(10), IntExpr.one).isZero, true);
      expect(LogExpr(IntExpr.from(10), IntExpr.from(10)).isZero, false);
    });

    test('isOne', () {
      expect(LogExpr(IntExpr.from(10), IntExpr.from(10)).isOne, true);
      expect(LogExpr(IntExpr.from(10), IntExpr.from(100)).isOne, false);
    });

    test('isInteger', () {
      expect(LogExpr(IntExpr.from(2), IntExpr.from(8)).isInteger, true);
      expect(LogExpr(IntExpr.from(10), IntExpr.from(7)).isInteger, false);
    });

    test('negate', () {
      final log = LogExpr(IntExpr.from(2), IntExpr.from(8));
      final negated = log.negate().simplify();
      expect(negated.toDouble(), -3.0);
    });

    test('log_a(a^n) = n', () {
      final arg = PowExpr(IntExpr.from(2), IntExpr.from(5));
      final log = LogExpr(IntExpr.from(2), arg).simplify();
      expect(log, isA<IntExpr>());
      expect((log as IntExpr).value, BigInt.from(5));
    });

    test('toString', () {
      expect(
        LogExpr(IntExpr.from(10), IntExpr.from(7)).toString(),
        'log_10(7)',
      );
      expect(LogExpr.ln(IntExpr.from(7)).toString(), 'ln(7)');
    });
  });

  group('TrigExpr', () {
    test('sin(0) = 0', () {
      final sin = TrigExpr(TrigFunc.sin, IntExpr.zero).simplify();
      expect(sin.isZero, true);
    });

    test('cos(0) = 1', () {
      final cos = TrigExpr(TrigFunc.cos, IntExpr.zero).simplify();
      expect(cos.isOne, true);
    });

    test('tan(0) = 0', () {
      final tan = TrigExpr(TrigFunc.tan, IntExpr.zero).simplify();
      expect(tan.isZero, true);
    });

    test('asin(0) = 0', () {
      final asin = TrigExpr(TrigFunc.asin, IntExpr.zero).simplify();
      expect(asin.isZero, true);
    });

    test('atan(0) = 0', () {
      final atan = TrigExpr(TrigFunc.atan, IntExpr.zero).simplify();
      expect(atan.isZero, true);
    });

    test('acos(1) = 0', () {
      final acos = TrigExpr(TrigFunc.acos, IntExpr.one).simplify();
      expect(acos.isZero, true);
    });

    test('asin(1) = π/2', () {
      final asin = TrigExpr(TrigFunc.asin, IntExpr.one).simplify();
      expect(asin.toDouble(), closeTo(1.5708, 0.001));
    });

    test('acos(0) = π/2', () {
      final acos = TrigExpr(TrigFunc.acos, IntExpr.zero).simplify();
      expect(acos.toDouble(), closeTo(1.5708, 0.001));
    });

    test('sin(π/6) = 1/2', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(6)).simplify();
      final sin = TrigExpr(TrigFunc.sin, arg).simplify();
      expect(sin.toDouble(), closeTo(0.5, 0.001));
    });

    test('cos(π/3) = 1/2', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(3)).simplify();
      final cos = TrigExpr(TrigFunc.cos, arg).simplify();
      expect(cos.toDouble(), closeTo(0.5, 0.001));
    });

    test('sin(π/4) = √2/2', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(4)).simplify();
      final sin = TrigExpr(TrigFunc.sin, arg).simplify();
      expect(sin.toDouble(), closeTo(0.7071, 0.001));
    });

    test('cos(π/4) = √2/2', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(4)).simplify();
      final cos = TrigExpr(TrigFunc.cos, arg).simplify();
      expect(cos.toDouble(), closeTo(0.7071, 0.001));
    });

    test('sin(π/2) = 1', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(2)).simplify();
      final sin = TrigExpr(TrigFunc.sin, arg).simplify();
      expect(sin.isOne, true);
    });

    test('cos(π/2) = 0', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(2)).simplify();
      final cos = TrigExpr(TrigFunc.cos, arg).simplify();
      expect(cos.isZero, true);
    });

    test('sin that cannot be simplified stays as sin', () {
      final sin = TrigExpr(TrigFunc.sin, IntExpr.from(2)).simplify();
      expect(sin, isA<TrigExpr>());
    });

    test('toDouble', () {
      expect(TrigExpr(TrigFunc.sin, IntExpr.zero).toDouble(), 0.0);
      expect(TrigExpr(TrigFunc.cos, IntExpr.zero).toDouble(), 1.0);
    });

    test('toMathNode', () {
      final nodes = TrigExpr(TrigFunc.sin, IntExpr.from(2)).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<TrigNode>());
    });

    test('copy', () {
      final original = TrigExpr(TrigFunc.sin, IntExpr.from(2));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = TrigExpr(TrigFunc.sin, IntExpr.from(2));
      final b = TrigExpr(TrigFunc.sin, IntExpr.from(2));
      final c = TrigExpr(TrigFunc.cos, IntExpr.from(2));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(TrigExpr(TrigFunc.sin, IntExpr.zero).isZero, true);
      expect(TrigExpr(TrigFunc.cos, IntExpr.zero).isZero, false);
    });

    test('isOne', () {
      expect(TrigExpr(TrigFunc.cos, IntExpr.zero).isOne, true);
      expect(TrigExpr(TrigFunc.sin, IntExpr.zero).isOne, false);
    });

    test('isRational', () {
      expect(TrigExpr(TrigFunc.sin, IntExpr.zero).isRational, true);
      expect(TrigExpr(TrigFunc.sin, IntExpr.from(2)).isRational, false);
    });

    test('isInteger', () {
      expect(TrigExpr(TrigFunc.sin, IntExpr.zero).isInteger, true);
      expect(TrigExpr(TrigFunc.sin, IntExpr.from(2)).isInteger, false);
    });

    test('negate', () {
      final sin = TrigExpr(TrigFunc.sin, IntExpr.from(1));
      final negated = sin.negate();
      expect(negated, isA<ProdExpr>());
    });

    test('tan(π/4) = 1', () {
      final arg = DivExpr(ConstExpr.pi, IntExpr.from(4)).simplify();
      final tan = TrigExpr(TrigFunc.tan, arg).simplify();
      expect(tan.toDouble(), closeTo(1.0, 0.001));
    });

    test('asin(-1) = -π/2', () {
      final asin = TrigExpr(TrigFunc.asin, IntExpr.negOne).simplify();
      expect(asin.toDouble(), closeTo(-1.5708, 0.001));
    });

    test('acos(-1) = π', () {
      final acos = TrigExpr(TrigFunc.acos, IntExpr.negOne).simplify();
      expect(acos.toDouble(), closeTo(3.14159, 0.001));
    });

    test('toString', () {
      expect(TrigExpr(TrigFunc.sin, IntExpr.from(2)).toString(), 'sin(2)');
      expect(TrigExpr(TrigFunc.cos, IntExpr.from(3)).toString(), 'cos(3)');
    });
  });

  group('AbsExpr', () {
    test('|5| = 5', () {
      final abs = AbsExpr(IntExpr.from(5)).simplify();
      expect(abs, isA<IntExpr>());
      expect((abs as IntExpr).value, BigInt.from(5));
    });

    test('|-5| = 5', () {
      final abs = AbsExpr(IntExpr.from(-5)).simplify();
      expect(abs, isA<IntExpr>());
      expect((abs as IntExpr).value, BigInt.from(5));
    });

    test('|0| = 0', () {
      final abs = AbsExpr(IntExpr.zero).simplify();
      expect(abs.isZero, true);
    });

    test('|-3/4| = 3/4', () {
      final abs = AbsExpr(FracExpr.from(-3, 4)).simplify();
      expect(abs.toDouble(), 0.75);
    });

    test('|√2| = √2', () {
      final abs = AbsExpr(RootExpr.sqrt(IntExpr.from(2))).simplify();
      expect(abs, isA<RootExpr>());
    });

    test('toDouble', () {
      expect(AbsExpr(IntExpr.from(-5)).toDouble(), 5.0);
    });

    test('copy', () {
      final original = AbsExpr(IntExpr.from(-5));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = AbsExpr(IntExpr.from(-5));
      final b = AbsExpr(IntExpr.from(-5));
      final c = AbsExpr(IntExpr.from(-6));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(AbsExpr(IntExpr.zero).isZero, true);
      expect(AbsExpr(IntExpr.from(-5)).isZero, false);
    });

    test('isOne', () {
      expect(AbsExpr(IntExpr.one).isOne, true);
      expect(AbsExpr(IntExpr.negOne).isOne, true);
      expect(AbsExpr(IntExpr.from(2)).isOne, false);
    });

    test('isRational', () {
      expect(AbsExpr(IntExpr.from(-5)).isRational, true);
      expect(AbsExpr(FracExpr.from(-3, 4)).isRational, true);
    });

    test('isInteger', () {
      expect(AbsExpr(IntExpr.from(-5)).isInteger, true);
      expect(AbsExpr(FracExpr.from(-3, 4)).isInteger, false);
    });

    test('negate', () {
      final abs = AbsExpr(IntExpr.from(5));
      final negated = abs.negate().simplify();
      expect(negated.toDouble(), -5.0);
    });

    test('toMathNode for simplified abs', () {
      final nodes = AbsExpr(IntExpr.from(-5)).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '5');
    });

    test('toString', () {
      expect(AbsExpr(IntExpr.from(-5)).toString(), '|\u22125|');
    });
  });

  group('DivExpr', () {
    test('0 / x = 0', () {
      final div = DivExpr(IntExpr.zero, IntExpr.from(5)).simplify();
      expect(div.isZero, true);
    });

    test('x / 1 = x', () {
      final div = DivExpr(IntExpr.from(5), IntExpr.one).simplify();
      expect(div, isA<IntExpr>());
      expect((div as IntExpr).value, BigInt.from(5));
    });

    test('x / x = 1', () {
      final div = DivExpr(IntExpr.from(5), IntExpr.from(5)).simplify();
      expect(div.isOne, true);
    });

    test('integer division', () {
      final div = DivExpr(IntExpr.from(10), IntExpr.from(4)).simplify();
      expect(div.toDouble(), 2.5);
    });

    test('√a / √b = √(a/b)', () {
      final div =
          DivExpr(
            RootExpr.sqrt(IntExpr.from(8)),
            RootExpr.sqrt(IntExpr.from(2)),
          ).simplify();
      expect(div.toDouble(), closeTo(2.0, 0.001));
    });

    test('toDouble', () {
      expect(DivExpr(IntExpr.from(10), IntExpr.from(4)).toDouble(), 2.5);
    });

    test('toMathNode', () {
      final nodes = DivExpr(IntExpr.from(3), IntExpr.from(4)).toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<FractionNode>());
    });

    test('copy', () {
      final original = DivExpr(IntExpr.from(3), IntExpr.from(4));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = DivExpr(IntExpr.from(3), IntExpr.from(4));
      final b = DivExpr(IntExpr.from(3), IntExpr.from(4));
      final c = DivExpr(IntExpr.from(3), IntExpr.from(5));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(DivExpr(IntExpr.zero, IntExpr.from(5)).isZero, true);
      expect(DivExpr(IntExpr.from(3), IntExpr.from(4)).isZero, false);
    });

    test('isOne', () {
      expect(DivExpr(IntExpr.from(5), IntExpr.from(5)).isOne, true);
      expect(DivExpr(IntExpr.from(3), IntExpr.from(4)).isOne, false);
    });

    test('isRational', () {
      expect(DivExpr(IntExpr.from(3), IntExpr.from(4)).isRational, true);
    });

    test('isInteger', () {
      expect(DivExpr(IntExpr.from(8), IntExpr.from(4)).isInteger, true);
      expect(DivExpr(IntExpr.from(3), IntExpr.from(4)).isInteger, false);
    });

    test('negate', () {
      final div = DivExpr(IntExpr.from(3), IntExpr.from(4));
      final negated = div.negate().simplify();
      expect(negated.toDouble(), -0.75);
    });

    test('fraction / fraction', () {
      final div = DivExpr(FracExpr.from(1, 2), FracExpr.from(1, 4)).simplify();
      expect(div, isA<IntExpr>());
      expect((div as IntExpr).value, BigInt.from(2));
    });

    test('integer / fraction', () {
      final div = DivExpr(IntExpr.from(2), FracExpr.from(1, 2)).simplify();
      expect(div, isA<IntExpr>());
      expect((div as IntExpr).value, BigInt.from(4));
    });

    test('fraction / integer', () {
      final div = DivExpr(FracExpr.from(1, 2), IntExpr.from(2)).simplify();
      expect(div.toDouble(), 0.25);
    });

    test('a√b / c simplification', () {
      final numerator = ProdExpr([
        IntExpr.from(6),
        RootExpr.sqrt(IntExpr.from(2)),
      ]);
      final div = DivExpr(numerator, IntExpr.from(2)).simplify();
      expect(div.toDouble(), closeTo(4.243, 0.001));
    });

    test('toString', () {
      expect(DivExpr(IntExpr.from(3), IntExpr.from(4)).toString(), '(3)/(4)');
    });
  });

  group('PermExpr', () {
    test('P(5,2) = 20', () {
      final perm = PermExpr(IntExpr.from(5), IntExpr.from(2)).simplify();
      expect(perm, isA<IntExpr>());
      expect((perm as IntExpr).value, BigInt.from(20));
    });

    test('P(5,0) = 1', () {
      final perm = PermExpr(IntExpr.from(5), IntExpr.zero).simplify();
      expect(perm.isOne, true);
    });

    test('P(5,5) = 120', () {
      final perm = PermExpr(IntExpr.from(5), IntExpr.from(5)).simplify();
      expect((perm as IntExpr).value, BigInt.from(120));
    });

    test('P(10,3) = 720', () {
      final perm = PermExpr(IntExpr.from(10), IntExpr.from(3)).simplify();
      expect((perm as IntExpr).value, BigInt.from(720));
    });

    test('toDouble', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).toDouble(), 20.0);
    });

    test('toMathNode for unsimplified', () {
      final perm = PermExpr(VarExpr('n'), VarExpr('r'));
      final nodes = perm.toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<PermutationNode>());
    });

    test('toMathNode for simplified', () {
      final nodes =
          PermExpr(IntExpr.from(5), IntExpr.from(2)).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '20');
    });

    test('copy', () {
      final original = PermExpr(IntExpr.from(5), IntExpr.from(2));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = PermExpr(IntExpr.from(5), IntExpr.from(2));
      final b = PermExpr(IntExpr.from(5), IntExpr.from(2));
      final c = PermExpr(IntExpr.from(5), IntExpr.from(3));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).isZero, false);
    });

    test('isOne', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.zero).isOne, true);
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).isOne, false);
    });

    test('isRational', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).isRational, true);
    });

    test('isInteger', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).isInteger, true);
    });

    test('negate', () {
      final perm = PermExpr(IntExpr.from(5), IntExpr.from(2));
      final negated = perm.negate().simplify();
      expect(negated.toDouble(), -20.0);
    });

    test('toString', () {
      expect(PermExpr(IntExpr.from(5), IntExpr.from(2)).toString(), 'P(5,2)');
    });

    test('P(1,1) = 1', () {
      final perm = PermExpr(IntExpr.from(1), IntExpr.from(1)).simplify();
      expect(perm.isOne, true);
    });

    test('P(n,1) = n', () {
      final perm = PermExpr(IntExpr.from(7), IntExpr.from(1)).simplify();
      expect((perm as IntExpr).value, BigInt.from(7));
    });
  });

  group('CombExpr', () {
    test('C(5,2) = 10', () {
      final comb = CombExpr(IntExpr.from(5), IntExpr.from(2)).simplify();
      expect(comb, isA<IntExpr>());
      expect((comb as IntExpr).value, BigInt.from(10));
    });

    test('C(5,0) = 1', () {
      final comb = CombExpr(IntExpr.from(5), IntExpr.zero).simplify();
      expect(comb.isOne, true);
    });

    test('C(5,5) = 1', () {
      final comb = CombExpr(IntExpr.from(5), IntExpr.from(5)).simplify();
      expect(comb.isOne, true);
    });

    test('C(10,3) = 120', () {
      final comb = CombExpr(IntExpr.from(10), IntExpr.from(3)).simplify();
      expect((comb as IntExpr).value, BigInt.from(120));
    });

    test('C(n,r) = C(n, n-r)', () {
      final comb1 = CombExpr(IntExpr.from(10), IntExpr.from(3)).simplify();
      final comb2 = CombExpr(IntExpr.from(10), IntExpr.from(7)).simplify();
      expect((comb1 as IntExpr).value, (comb2 as IntExpr).value);
    });

    test('toDouble', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).toDouble(), 10.0);
    });

    test('toMathNode for unsimplified', () {
      final comb = CombExpr(VarExpr('n'), VarExpr('r'));
      final nodes = comb.toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<CombinationNode>());
    });

    test('toMathNode for simplified', () {
      final nodes =
          CombExpr(IntExpr.from(5), IntExpr.from(2)).simplify().toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, '10');
    });

    test('copy', () {
      final original = CombExpr(IntExpr.from(5), IntExpr.from(2));
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('structurallyEquals', () {
      final a = CombExpr(IntExpr.from(5), IntExpr.from(2));
      final b = CombExpr(IntExpr.from(5), IntExpr.from(2));
      final c = CombExpr(IntExpr.from(5), IntExpr.from(3));
      expect(a.structurallyEquals(b), true);
      expect(a.structurallyEquals(c), false);
    });

    test('isZero', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).isZero, false);
    });

    test('isOne', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.zero).isOne, true);
      expect(CombExpr(IntExpr.from(5), IntExpr.from(5)).isOne, true);
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).isOne, false);
    });

    test('isRational', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).isRational, true);
    });

    test('isInteger', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).isInteger, true);
    });

    test('negate', () {
      final comb = CombExpr(IntExpr.from(5), IntExpr.from(2));
      final negated = comb.negate().simplify();
      expect(negated.toDouble(), -10.0);
    });

    test('toString', () {
      expect(CombExpr(IntExpr.from(5), IntExpr.from(2)).toString(), 'C(5,2)');
    });

    test('C(n,1) = n', () {
      final comb = CombExpr(IntExpr.from(7), IntExpr.from(1)).simplify();
      expect((comb as IntExpr).value, BigInt.from(7));
    });

    test('large combination', () {
      final comb = CombExpr(IntExpr.from(20), IntExpr.from(10)).simplify();
      expect((comb as IntExpr).value, BigInt.from(184756));
    });
  });

  group('VarExpr', () {
    test('creates variable', () {
      final v = VarExpr('x');
      expect(v.name, 'x');
    });

    test('simplify returns self', () {
      final v = VarExpr('x');
      expect(v.simplify(), v);
    });

    test('toDouble throws', () {
      expect(() => VarExpr('x').toDouble(), throwsA(isA<UnsupportedError>()));
    });

    test('isRational', () {
      expect(VarExpr('x').isRational, false);
    });

    test('isInteger', () {
      expect(VarExpr('x').isInteger, false);
    });

    test('isZero', () {
      expect(VarExpr('x').isZero, false);
    });

    test('isOne', () {
      expect(VarExpr('x').isOne, false);
    });

    test('structurallyEquals', () {
      expect(VarExpr('x').structurallyEquals(VarExpr('x')), true);
      expect(VarExpr('x').structurallyEquals(VarExpr('y')), false);
    });

    test('toMathNode', () {
      final nodes = VarExpr('x').toMathNode();
      expect(nodes.length, 1);
      expect(nodes[0], isA<LiteralNode>());
      expect((nodes[0] as LiteralNode).text, 'x');
    });

    test('copy', () {
      final original = VarExpr('x');
      final copied = original.copy();
      expect(copied.structurallyEquals(original), true);
      expect(identical(copied, original), false);
    });

    test('negate', () {
      final v = VarExpr('x');
      final negated = v.negate();
      expect(negated, isA<ProdExpr>());
    });

    test('termSignature', () {
      expect(VarExpr('x').termSignature, 'var:x');
      expect(VarExpr('y').termSignature, 'var:y');
    });

    test('coefficient and baseExpr', () {
      final v = VarExpr('x');
      expect(v.coefficient.isOne, true);
      expect(v.baseExpr, v);
    });

    test('toString', () {
      expect(VarExpr('x').toString(), 'x');
      expect(VarExpr('myVar').toString(), 'myVar');
    });
  });

  group('MathNodeToExpr', () {
    test('convert integer literal', () {
      final nodes = [LiteralNode(text: '42')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(42));
    });

    test('convert negative integer literal', () {
      final nodes = [LiteralNode(text: '-42')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(-42));
    });

    test('convert decimal literal', () {
      final nodes = [LiteralNode(text: '0.5')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.toDouble(), 0.5);
    });

    test('convert fraction node', () {
      final nodes = [
        FractionNode(
          num: [LiteralNode(text: '3')],
          den: [LiteralNode(text: '4')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.toDouble(), 0.75);
    });

    test('convert root node', () {
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '4')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(2));
    });

    test('convert nth root node', () {
      final nodes = [
        RootNode(
          isSquareRoot: false,
          index: [LiteralNode(text: '3')],
          radicand: [LiteralNode(text: '8')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(2));
    });

    test('convert exponent node', () {
      final nodes = [
        ExponentNode(
          base: [LiteralNode(text: '2')],
          power: [LiteralNode(text: '3')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(8));
    });

    test('convert log node', () {
      final nodes = [
        LogNode(
          base: [LiteralNode(text: '2')],
          argument: [LiteralNode(text: '8')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(3));
    });

    test('convert natural log node', () {
      final nodes = [
        LogNode(isNaturalLog: true, argument: [LiteralNode(text: '1')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert trig node sin', () {
      final nodes = [
        TrigNode(function: 'sin', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert trig node cos', () {
      final nodes = [
        TrigNode(function: 'cos', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isOne, true);
    });

    test('convert trig node tan', () {
      final nodes = [
        TrigNode(function: 'tan', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert trig node asin', () {
      final nodes = [
        TrigNode(function: 'asin', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert trig node acos', () {
      final nodes = [
        TrigNode(function: 'acos', argument: [LiteralNode(text: '1')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert trig node atan', () {
      final nodes = [
        TrigNode(function: 'atan', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr.isZero, true);
    });

    test('convert abs node', () {
      final nodes = [
        TrigNode(function: 'abs', argument: [LiteralNode(text: '-5')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(5));
    });

    test('convert arg node', () {
      final nodes = [
        TrigNode(function: 'arg', argument: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.zero);
    });

    test('convert Re node', () {
      final nodes = [
        TrigNode(function: 'Re', argument: [LiteralNode(text: '5')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(5));
    });

    test('convert Im node', () {
      final nodes = [
        TrigNode(function: 'Im', argument: [LiteralNode(text: '5')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.zero);
    });

    test('convert sgn node', () {
      final nodes = [
        TrigNode(function: 'sgn', argument: [LiteralNode(text: '-3')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(-1));
    });

    test('convert addition', () {
      final nodes = [
        LiteralNode(text: '3'),
        LiteralNode(text: '+'),
        LiteralNode(text: '4'),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(7));
    });

    test('convert addition in single literal', () {
      final nodes = [LiteralNode(text: '3+4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(7));
    });

    test('convert subtraction', () {
      final nodes = [
        LiteralNode(text: '10'),
        LiteralNode(text: '-'),
        LiteralNode(text: '3'),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(7));
    });

    test('convert multiplication', () {
      final nodes = [
        LiteralNode(text: '3'),
        LiteralNode(text: '*'),
        LiteralNode(text: '4'),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(12));
    });

    test('convert division', () {
      final nodes = [
        LiteralNode(text: '12'),
        LiteralNode(text: '/'),
        LiteralNode(text: '4'),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(3));
    });

    test('convert power operator', () {
      final nodes = [LiteralNode(text: '2^3')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(8));
    });

    test('convert pi', () {
      final nodes = [LiteralNode(text: 'π')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<ConstExpr>());
      expect((expr as ConstExpr).type, ConstType.pi);
    });

    test('convert pi spelled out', () {
      final nodes = [LiteralNode(text: 'pi')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<ConstExpr>());
      expect((expr as ConstExpr).type, ConstType.pi);
    });

    test('convert e', () {
      final nodes = [LiteralNode(text: 'e')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<ConstExpr>());
      expect((expr as ConstExpr).type, ConstType.e);
    });

    test('convert phi', () {
      final nodes = [LiteralNode(text: 'φ')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<ConstExpr>());
      expect((expr as ConstExpr).type, ConstType.phi);
    });

    test('convert permutation node', () {
      final nodes = [
        PermutationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(20));
    });

    test('convert combination node', () {
      final nodes = [
        CombinationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(10));
    });

    test('convert parenthesis node', () {
      final nodes = [
        ParenthesisNode(content: [LiteralNode(text: '42')]),
      ];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(42));
    });

    test('convert empty nodes', () {
      final expr = MathNodeToExpr.convert([]);
      expect(expr.isZero, true);
    });

    test('convert variable', () {
      final nodes = [LiteralNode(text: 'x')];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<VarExpr>());
      expect((expr as VarExpr).name, 'x');
    });

    test('convert complex expression', () {
      // 2 + 3 * 4 = 14 (respecting order of operations)
      final nodes = [LiteralNode(text: '2+3*4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(14));
    });

    test('convert parenthesized expression', () {
      // (2 + 3) * 4 = 20
      final nodes = [LiteralNode(text: '(2+3)*4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(20));
    });

    test('convert middle dot multiplication', () {
      final nodes = [LiteralNode(text: '3·4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(12));
    });

    test('convert times sign multiplication', () {
      final nodes = [LiteralNode(text: '3×4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(12));
    });

    test('convert minus sign', () {
      final nodes = [LiteralNode(text: '5−3')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(2));
    });

    test('convert division sign', () {
      final nodes = [LiteralNode(text: '8÷4')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(2));
    });

    test('implicit multiplication number and parenthesis', () {
      // 2(3) = 6
      final nodes = [
        LiteralNode(text: '2'),
        ParenthesisNode(content: [LiteralNode(text: '3')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(6));
    });

    test('implicit multiplication number and root', () {
      // 2√4 = 4
      final nodes = [
        LiteralNode(text: '2'),
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '4')]),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(4));
    });

    test('ans node conversion', () {
      final nodes = [
        AnsNode(index: [LiteralNode(text: '0')]),
      ];
      final expr = MathNodeToExpr.convert(nodes);
      expect(expr, isA<VarExpr>());
      expect((expr as VarExpr).name, 'ans0');
    });

    test('newline node is ignored', () {
      final nodes = [
        LiteralNode(text: '5'),
        NewlineNode(),
        LiteralNode(text: '+3'),
      ];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(8));
    });
  });

  group('ExactMathEngine', () {
    test('evaluate simple integer', () {
      final nodes = [LiteralNode(text: '42')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isEmpty, false);
      expect(result.numerical, 42.0);
    });

    test('evaluate addition', () {
      final nodes = [LiteralNode(text: '3+4')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 7.0);
    });

    test('evaluate fraction', () {
      final nodes = [
        FractionNode(
          num: [LiteralNode(text: '1')],
          den: [LiteralNode(text: '2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 0.5);
      expect(result.mathNodes?[0], isA<FractionNode>());
    });

    test('evaluate square root', () {
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '8')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, closeTo(2.828, 0.001));
    });

    test('evaluate √8 + √2 = 3√2', () {
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '8')]),
        LiteralNode(text: '+'),
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '2')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, closeTo(4.243, 0.001));
    });

    test('evaluate log_10(100) = 2', () {
      final nodes = [
        LogNode(
          base: [LiteralNode(text: '10')],
          argument: [LiteralNode(text: '100')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 2.0);
      expect(result.mathNodes?[0], isA<LiteralNode>());
      expect((result.mathNodes?[0] as LiteralNode).text, '2');
    });

    test('evaluate cos(0) = 1', () {
      final nodes = [
        TrigNode(function: 'cos', argument: [LiteralNode(text: '0')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 1.0);
    });

    test('empty expression returns empty result', () {
      final result = ExactMathEngine.evaluate([]);
      expect(result.isEmpty, true);
    });

    test('empty literal returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (trailing +) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3+')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (trailing -) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3-')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (trailing *) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3*')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (trailing /) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3/')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (trailing ^) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3^')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (leading *) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '*3')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (leading /) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '/3')]);
      expect(result.isEmpty, true);
    });

    test('incomplete expression (leading ^) returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '^3')]);
      expect(result.isEmpty, true);
    });

    test('consecutive operators returns empty result', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '3**4')]);
      expect(result.isEmpty, true);
    });

    test('empty fraction numerator returns empty result', () {
      final result = ExactMathEngine.evaluate([
        FractionNode(
          num: [LiteralNode(text: '')],
          den: [LiteralNode(text: '4')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty fraction denominator returns empty result', () {
      final result = ExactMathEngine.evaluate([
        FractionNode(
          num: [LiteralNode(text: '3')],
          den: [LiteralNode(text: '')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty root radicand returns empty result', () {
      final result = ExactMathEngine.evaluate([
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '')]),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty exponent base returns empty result', () {
      final result = ExactMathEngine.evaluate([
        ExponentNode(
          base: [LiteralNode(text: '')],
          power: [LiteralNode(text: '2')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty exponent power returns empty result', () {
      final result = ExactMathEngine.evaluate([
        ExponentNode(
          base: [LiteralNode(text: '2')],
          power: [LiteralNode(text: '')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty log argument returns empty result', () {
      final result = ExactMathEngine.evaluate([
        LogNode(
          base: [LiteralNode(text: '10')],
          argument: [LiteralNode(text: '')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty trig argument returns empty result', () {
      final result = ExactMathEngine.evaluate([
        TrigNode(function: 'sin', argument: [LiteralNode(text: '')]),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty parenthesis returns empty result', () {
      final result = ExactMathEngine.evaluate([
        ParenthesisNode(content: [LiteralNode(text: '')]),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty permutation n returns empty result', () {
      final result = ExactMathEngine.evaluate([
        PermutationNode(
          n: [LiteralNode(text: '')],
          r: [LiteralNode(text: '2')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty permutation r returns empty result', () {
      final result = ExactMathEngine.evaluate([
        PermutationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty combination n returns empty result', () {
      final result = ExactMathEngine.evaluate([
        CombinationNode(
          n: [LiteralNode(text: '')],
          r: [LiteralNode(text: '2')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('empty combination r returns empty result', () {
      final result = ExactMathEngine.evaluate([
        CombinationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '')],
        ),
      ]);
      expect(result.isEmpty, true);
    });

    test('division by zero returns infinity', () {
      final result = ExactMathEngine.evaluate([LiteralNode(text: '1/0')]);
      expect(result.numerical?.isInfinite, true);
    });

    test('evaluateToMathNode returns nodes', () {
      final nodes = [LiteralNode(text: '42')];
      final result = ExactMathEngine.evaluateToMathNode(nodes);
      expect(result, isNotNull);
      expect(result!.length, 1);
      expect((result[0] as LiteralNode).text, '42');
    });

    test('evaluateToMathNode returns null for empty', () {
      final result = ExactMathEngine.evaluateToMathNode([]);
      expect(result, isNull);
    });

    test('evaluateToDouble returns double', () {
      final nodes = [LiteralNode(text: '42')];
      final result = ExactMathEngine.evaluateToDouble(nodes);
      expect(result, 42.0);
    });

    test('evaluateToDouble returns null for empty', () {
      final result = ExactMathEngine.evaluateToDouble([]);
      expect(result, isNull);
    });

    test('complex nested expression', () {
      // √(4 + 5) = √9 = 3
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '4+5')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 3.0);
    });

    test('fraction with expressions', () {
      // (2+3)/(4+1) = 5/5 = 1
      final nodes = [
        FractionNode(
          num: [LiteralNode(text: '2+3')],
          den: [LiteralNode(text: '4+1')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 1.0);
    });

    test('isExact for irrational result', () {
      final nodes = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '2')]),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isExact, true);
    });

    test('isExact for rational result', () {
      final nodes = [LiteralNode(text: '42')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.isExact, false);
    });

    test('solves quadratic equation exactly', () {
      final nodes = [LiteralNode(text: 'x^2+2x=1')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final serialized = MathExpressionSerializer.serialize(result.mathNodes!);
      final normalized = serialized.replaceAll(' ', '');
      expect(normalized.split('\n').length, 2);
      expect(normalized, contains('x='));
      expect(normalized, contains('sqrt(2)'));
      expect(normalized, contains('-1+'));
      expect(normalized, contains('-1-'));
      expect(normalized.contains('x^2'), isFalse);
    });

    test(
      'quadratic simplifies discriminant and uses coefficient before root',
      () {
        final nodes = [LiteralNode(text: 'x^2+2/3x=1')];
        final result = ExactMathEngine.evaluate(nodes);
        expect(result.expr, isNotNull);
        expect(result.expr, isA<SumExpr>());
        final sum = result.expr as SumExpr;
        final prodTerms = sum.terms.whereType<ProdExpr>().toList();
        expect(prodTerms, isNotEmpty);
        final rootProd = prodTerms.firstWhere(
          (prod) => prod.factors.any((f) => f is RootExpr),
        );
        final root =
            rootProd.factors.firstWhere((f) => f is RootExpr) as RootExpr;
        expect(root.radicand, isA<IntExpr>());
        expect((root.radicand as IntExpr).value, BigInt.from(10));
        expect(rootProd.factors.any((f) => f is FracExpr), isTrue);
      },
    );

    test('solves linear system with fractional coefficients', () {
      final nodes = [
        LiteralNode(text: 'x+1/2y=5'),
        NewlineNode(),
        LiteralNode(text: 'x-1/2y=1'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final serialized = MathExpressionSerializer.serialize(result.mathNodes!);
      final normalized = serialized.replaceAll(' ', '');
      expect(normalized, contains('x=3'));
      expect(normalized, contains('y=4'));
      expect(normalized.contains('='), isTrue);
    });
  });

  group('ExactResult', () {
    test('empty result properties', () {
      final result = ExactResult.empty();
      expect(result.isEmpty, true);
      expect(result.hasError, false);
      expect(result.expr, isNull);
      expect(result.mathNodes, isNull);
      expect(result.numerical, isNull);
    });

    test('error result properties', () {
      final result = ExactResult.error('Test error');
      expect(result.isEmpty, false);
      expect(result.hasError, true);
      expect(result.error, 'Test error');
    });

    test('toExactString for error', () {
      final result = ExactResult.error('Test error');
      expect(result.toExactString(), 'Test error');
    });

    test('toExactString for empty', () {
      final result = ExactResult.empty();
      expect(result.toExactString(), '');
    });

    test('toExactString for valid result', () {
      final result = ExactResult(
        expr: IntExpr.from(42),
        mathNodes: [LiteralNode(text: '42')],
        numerical: 42.0,
      );
      expect(result.toExactString(), '42');
    });

    test('toNumericalString for empty', () {
      final result = ExactResult.empty();
      expect(result.toNumericalString(), '');
    });

    test('toNumericalString for integer', () {
      final result = ExactResult(
        expr: IntExpr.from(42),
        mathNodes: [LiteralNode(text: '42')],
        numerical: 42.0,
      );
      expect(result.toNumericalString(), '42');
    });

    test('toNumericalString for decimal', () {
      final result = ExactResult(
        expr: FracExpr.from(1, 3),
        mathNodes: [LiteralNode(text: '1/3')],
        numerical: 0.333333,
      );
      expect(result.toNumericalString(precision: 4), '0.3333');
    });

    test('toNumericalString for infinity', () {
      final result = ExactResult(
        expr: IntExpr.one,
        mathNodes: [LiteralNode(text: '∞')],
        numerical: double.infinity,
      );
      expect(result.toNumericalString(), '∞');
    });

    test('toNumericalString for negative infinity', () {
      final result = ExactResult(
        expr: IntExpr.one,
        mathNodes: [LiteralNode(text: '\u2212∞')],
        numerical: double.negativeInfinity,
      );
      expect(result.toNumericalString(), '\u2212∞');
    });

    test('toNumericalString strips trailing zeros', () {
      final result = ExactResult(
        expr: FracExpr.from(1, 2),
        mathNodes: [LiteralNode(text: '1/2')],
        numerical: 0.5,
      );
      expect(result.toNumericalString(), '0.5');
    });
  });

  group('Helper functions', () {
    test('frac helper', () {
      final f = frac(3, 4);
      expect(f, isA<FracExpr>());
      expect(f.toDouble(), 0.75);
    });

    test('sqrt helper', () {
      final r = sqrt(IntExpr.from(4)).simplify();
      expect(r, isA<IntExpr>());
      expect((r as IntExpr).value, BigInt.from(2));
    });

    test('sqrtInt helper', () {
      final r = sqrtInt(4).simplify();
      expect(r, isA<IntExpr>());
      expect((r as IntExpr).value, BigInt.from(2));
    });

    test('sum helper', () {
      final s = sum([IntExpr.from(3), IntExpr.from(4)]).simplify();
      expect(s, isA<IntExpr>());
      expect((s as IntExpr).value, BigInt.from(7));
    });

    test('prod helper', () {
      final p = prod([IntExpr.from(3), IntExpr.from(4)]).simplify();
      expect(p, isA<IntExpr>());
      expect((p as IntExpr).value, BigInt.from(12));
    });

    test('pow helper', () {
      final p = pow(IntExpr.from(2), IntExpr.from(3)).simplify();
      expect(p, isA<IntExpr>());
      expect((p as IntExpr).value, BigInt.from(8));
    });

    test('ln helper', () {
      final l = ln(IntExpr.one).simplify();
      expect(l.isZero, true);
    });

    test('log helper', () {
      final l = log(IntExpr.from(2), IntExpr.from(8)).simplify();
      expect(l, isA<IntExpr>());
      expect((l as IntExpr).value, BigInt.from(3));
    });
  });

  group('Extension methods', () {
    test('int toExpr extension', () {
      final expr = 42.toExpr();
      expect(expr, isA<IntExpr>());
      expect(expr.value, BigInt.from(42));
    });

    test('BigInt toExpr extension', () {
      final expr = BigInt.from(42).toExpr();
      expect(expr, isA<IntExpr>());
      expect(expr.value, BigInt.from(42));
    });
  });

  group('Edge cases', () {
    test('very large integer', () {
      final big = IntExpr(BigInt.parse('123456789012345678901234567890'));
      expect(big.value, BigInt.parse('123456789012345678901234567890'));
    });

    test('nested fractions simplify', () {
      // (1/2) / (1/4) = 2
      final result =
          DivExpr(FracExpr.from(1, 2), FracExpr.from(1, 4)).simplify();
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(2));
    });

    test('multiple root simplification', () {
      // √2 * √8 = √16 = 4
      final result =
          ProdExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            RootExpr.sqrt(IntExpr.from(8)),
          ]).simplify();
      expect(result, isA<IntExpr>());
      expect((result as IntExpr).value, BigInt.from(4));
    });

    test('sum with all zeros', () {
      final sum =
          SumExpr([IntExpr.zero, IntExpr.zero, IntExpr.zero]).simplify();
      expect(sum.isZero, true);
    });

    test('product with multiple ones', () {
      final prod =
          ProdExpr([IntExpr.one, IntExpr.one, IntExpr.from(5)]).simplify();
      expect(prod, isA<IntExpr>());
      expect((prod as IntExpr).value, BigInt.from(5));
    });

    test('deeply nested expression', () {
      // ((2^2)^2)^2 = 256
      final expr =
          PowExpr(
            PowExpr(PowExpr(IntExpr.from(2), IntExpr.from(2)), IntExpr.from(2)),
            IntExpr.from(2),
          ).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(256));
    });

    test('combining different surds does not combine', () {
      // √2 + √3 should not combine
      final sum =
          SumExpr([
            RootExpr.sqrt(IntExpr.from(2)),
            RootExpr.sqrt(IntExpr.from(3)),
          ]).simplify();
      expect(sum, isA<SumExpr>());
      expect((sum as SumExpr).terms.length, 2);
    });

    test('order of operations respected', () {
      // 2 + 3 * 4 - 5 = 2 + 12 - 5 = 9
      final nodes = [LiteralNode(text: '2+3*4-5')];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, 9.0);
    });

    test('unary minus', () {
      final nodes = [LiteralNode(text: '-5')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(-5));
    });

    test('unary plus', () {
      final nodes = [LiteralNode(text: '+5')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(5));
    });

    test('double negation', () {
      final nodes = [LiteralNode(text: '--5')];
      final expr = MathNodeToExpr.convert(nodes).simplify();
      expect(expr, isA<IntExpr>());
      expect((expr as IntExpr).value, BigInt.from(5));
    });
  });
}
