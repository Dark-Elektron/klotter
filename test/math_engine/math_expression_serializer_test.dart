import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/renderer.dart';

void main() {
  group('MathExpressionSerializer - Basic Serialization', () {
    test('serializes simple literal', () {
      final expression = [LiteralNode(text: '123')];
      expect(MathExpressionSerializer.serialize(expression), equals('123'));
    });

    test('serializes expression with operators', () {
      final expression = [LiteralNode(text: '2+3')];
      expect(MathExpressionSerializer.serialize(expression), equals('2+3'));
    });

    test('serializes multiple literals', () {
      final expression = [LiteralNode(text: '2'), LiteralNode(text: '+3')];
      expect(MathExpressionSerializer.serialize(expression), equals('2+3'));
    });
  });

  group('MathExpressionSerializer - Fraction Serialization', () {
    test('serializes simple fraction', () {
      final expression = [
        FractionNode(
          num: [LiteralNode(text: '1')],
          den: [LiteralNode(text: '2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('((1)/(2))'),
      );
    });

    test('serializes fraction with expressions', () {
      final expression = [
        FractionNode(
          num: [LiteralNode(text: '2+3')],
          den: [LiteralNode(text: '4')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('((2+3)/(4))'),
      );
    });

    test('serializes nested fractions', () {
      final expression = [
        FractionNode(
          num: [
            FractionNode(
              num: [LiteralNode(text: '1')],
              den: [LiteralNode(text: '2')],
            ),
          ],
          den: [LiteralNode(text: '3')],
        ),
      ];
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, contains('((1)/(2))'));
    });
  });

  group('MathExpressionSerializer - Exponent Serialization', () {
    test('serializes simple exponent', () {
      final expression = [
        ExponentNode(
          base: [LiteralNode(text: '2')],
          power: [LiteralNode(text: '3')],
        ),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('2^(3)'));
    });

    test('serializes exponent with expression in base', () {
      final expression = [
        ExponentNode(
          base: [LiteralNode(text: '2+1')],
          power: [LiteralNode(text: '2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('(2+1)^(2)'),
      );
    });
  });

  group('MathExpressionSerializer - Parenthesis Serialization', () {
    test('serializes parentheses', () {
      final expression = [
        ParenthesisNode(content: [LiteralNode(text: '2+3')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('(2+3)'));
    });

    test('serializes nested parentheses', () {
      final expression = [
        ParenthesisNode(
          content: [
            ParenthesisNode(content: [LiteralNode(text: '1+2')]),
            LiteralNode(text: '+3'),
          ],
        ),
      ];
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, contains('((1+2)+3)'));
    });
  });

  group('MathExpressionSerializer - Trig Function Serialization', () {
    test('serializes sin function', () {
      final expression = [
        TrigNode(function: 'sin', argument: [LiteralNode(text: '30')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('sin(30)'));
    });

    test('serializes cos function', () {
      final expression = [
        TrigNode(function: 'cos', argument: [LiteralNode(text: '60')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('cos(60)'));
    });

    test('serializes tan function', () {
      final expression = [
        TrigNode(function: 'tan', argument: [LiteralNode(text: '45')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('tan(45)'));
    });

    test('serializes arg function', () {
      final expression = [
        TrigNode(function: 'arg', argument: [LiteralNode(text: '3+4i')]),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('arg(3+4*i)'),
      );
    });

    test('serializes Re/Im/sgn functions', () {
      final reExpr = [
        TrigNode(function: 'Re', argument: [LiteralNode(text: '3+4i')]),
      ];
      final imExpr = [
        TrigNode(function: 'Im', argument: [LiteralNode(text: '3+4i')]),
      ];
      final sgnExpr = [
        TrigNode(function: 'sgn', argument: [LiteralNode(text: '3+4i')]),
      ];
      expect(MathExpressionSerializer.serialize(reExpr), equals('Re(3+4*i)'));
      expect(MathExpressionSerializer.serialize(imExpr), equals('Im(3+4*i)'));
      expect(MathExpressionSerializer.serialize(sgnExpr), equals('sgn(3+4*i)'));
    });
  });

  group('MathExpressionSerializer - Root Serialization', () {
    test('serializes square root', () {
      final expression = [
        RootNode(isSquareRoot: true, radicand: [LiteralNode(text: '4')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('sqrt(4)'));
    });

    test('serializes nth root', () {
      final expression = [
        RootNode(
          isSquareRoot: false,
          index: [LiteralNode(text: '3')],
          radicand: [LiteralNode(text: '8')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('((8)^(1/(3)))'),
      );
    });
  });

  group('MathExpressionSerializer - Log Serialization', () {
    test('serializes natural log', () {
      final expression = [
        LogNode(isNaturalLog: true, argument: [LiteralNode(text: '10')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('ln(10)'));
    });

    test('serializes log base 10', () {
      final expression = [
        LogNode(
          isNaturalLog: false,
          base: [LiteralNode(text: '10')],
          argument: [LiteralNode(text: '100')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('(ln(100)/ln(10))'),
      );
    });

    test('serializes log with custom base', () {
      final expression = [
        LogNode(
          isNaturalLog: false,
          base: [LiteralNode(text: '2')],
          argument: [LiteralNode(text: '8')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('(ln(8)/ln(2))'),
      );
    });
  });

  group('MathExpressionSerializer - Permutation/Combination Serialization', () {
    test('serializes permutation', () {
      final expression = [
        PermutationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('perm(5,2)'),
      );
    });

    test('serializes combination', () {
      final expression = [
        CombinationNode(
          n: [LiteralNode(text: '5')],
          r: [LiteralNode(text: '2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('comb(5,2)'),
      );
    });

    test('serializes permutation with expressions', () {
      final expression = [
        PermutationNode(
          n: [
            ParenthesisNode(content: [LiteralNode(text: '2+3')]),
          ],
          r: [LiteralNode(text: '2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('perm((2+3),2)'),
      );
    });
  });

  group('MathExpressionSerializer - Calculus Serialization', () {
    test('serializes derivative', () {
      final expression = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '2')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('diff(x,2,x^2)'),
      );
    });

    test('serializes integral', () {
      final expression = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('int(x,0,1,x)'),
      );
    });
  });

  group('MathExpressionSerializer - ANS Serialization', () {
    test('serializes ans node', () {
      final expression = [
        AnsNode(index: [LiteralNode(text: '0')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('ans0'));
    });

    test('serializes ans with index', () {
      final expression = [
        AnsNode(index: [LiteralNode(text: '5')]),
      ];
      expect(MathExpressionSerializer.serialize(expression), equals('ans5'));
    });
  });

  group('MathExpressionSerializer - Newline Serialization', () {
    test('serializes newline', () {
      final expression = [
        LiteralNode(text: 'x+y=5'),
        NewlineNode(),
        LiteralNode(text: 'x-y=1'),
      ];
      expect(
        MathExpressionSerializer.serialize(expression),
        equals('x+y=5\nx-y=1'),
      );
    });
  });

  group('MathExpressionSerializer - JSON Serialization', () {
    test('serializes and deserializes simple expression', () {
      final original = [LiteralNode(text: '123')];
      final json = MathExpressionSerializer.serializeToJson(original);
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      expect(restored.length, equals(1));
      expect((restored[0] as LiteralNode).text, equals('123'));
    });

    test('serializes and deserializes fraction', () {
      final original = [
        FractionNode(
          num: [LiteralNode(text: '1')],
          den: [LiteralNode(text: '2')],
        ),
      ];
      final json = MathExpressionSerializer.serializeToJson(original);
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      expect(restored.length, equals(1));
      expect(restored[0], isA<FractionNode>());

      final fraction = restored[0] as FractionNode;
      expect((fraction.numerator[0] as LiteralNode).text, equals('1'));
      expect((fraction.denominator[0] as LiteralNode).text, equals('2'));
    });

    test('serializes and deserializes complex expression', () {
      final original = [
        LiteralNode(text: '2'),
        FractionNode(
          num: [LiteralNode(text: '3')],
          den: [LiteralNode(text: '4')],
        ),
        LiteralNode(text: '+5'),
      ];
      final json = MathExpressionSerializer.serializeToJson(original);
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      expect(restored.length, equals(3));
      expect(restored[0], isA<LiteralNode>());
      expect(restored[1], isA<FractionNode>());
      expect(restored[2], isA<LiteralNode>());
    });

    test('serializes and deserializes calculus nodes', () {
      final original = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x^2')],
        ),
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '2')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final json = MathExpressionSerializer.serializeToJson(original);
      final restored = MathExpressionSerializer.deserializeFromJson(json);

      expect(restored.length, equals(2));
      expect(restored[0], isA<DerivativeNode>());
      expect(restored[1], isA<IntegralNode>());
    });

    test('handles empty json', () {
      final restored = MathExpressionSerializer.deserializeFromJson('');
      expect(restored.length, equals(1));
      expect(restored[0], isA<LiteralNode>());
    });

    test('handles invalid json', () {
      final restored = MathExpressionSerializer.deserializeFromJson('invalid');
      expect(restored.length, equals(1));
      expect(restored[0], isA<LiteralNode>());
    });
  });

  group('MathExpressionSerializer - Unicode Conversion', () {
    test('converts multiplication sign', () {
      final expression = [LiteralNode(text: '2\u00B73')]; // 2·3
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, equals('2*3'));
    });

    test('converts minus sign', () {
      final expression = [LiteralNode(text: '5\u22122')]; // 5−2
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, equals('5-2'));
    });

    test('converts plus sign', () {
      final expression = [LiteralNode(text: '2\u002B3')]; // 2+3
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, equals('2+3'));
    });
  });

  group('MathExpressionSerializer - Implicit Multiplication', () {
    test('adds implicit multiplication: 2(3)', () {
      final expression = [LiteralNode(text: '2(3)')];
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, contains('*'));
    });

    test('adds implicit multiplication: (2)(3)', () {
      final expression = [
        ParenthesisNode(content: [LiteralNode(text: '2')]),
        ParenthesisNode(content: [LiteralNode(text: '3')]),
      ];
      final result = MathExpressionSerializer.serialize(expression);
      expect(result, contains('*'));
    });
  });
}
