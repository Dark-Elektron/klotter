import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/math_renderer/decimal_result_nodes.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  setUp(() {
    MathSolverNew.setPrecision(7);
    MathSolverNew.setNumberFormat(NumberFormat.automatic);
  });

  test('Converts numeric fraction coefficient and keeps variable fraction', () {
    final nodes = [
      FractionNode(
        num: [LiteralNode(text: '10'), LiteralNode(text: 'x')],
        den: [LiteralNode(text: '6'), LiteralNode(text: 'y')],
      ),
    ];

    final converted = decimalizeExactNodes(nodes);

    expect(converted.length, 2);
    expect(converted[0], isA<LiteralNode>());
    expect((converted[0] as LiteralNode).text, '1.6666667');

    final frac = converted[1] as FractionNode;
    expect(frac.numerator.length, 1);
    expect(frac.denominator.length, 1);
    expect((frac.numerator.first as LiteralNode).text, 'x');
    expect((frac.denominator.first as LiteralNode).text, 'y');
  });

  test('Keeps exponent in variable denominator', () {
    final nodes = [
      FractionNode(
        num: [LiteralNode(text: '10'), LiteralNode(text: 'x')],
        den: [
          LiteralNode(text: '6'),
          ExponentNode(
            base: [LiteralNode(text: 'y')],
            power: [LiteralNode(text: '2')],
          ),
        ],
      ),
    ];

    final converted = decimalizeExactNodes(nodes);

    expect(converted.length, 2);
    expect((converted[0] as LiteralNode).text, '1.6666667');

    final frac = converted[1] as FractionNode;
    expect(frac.numerator.length, 1);
    expect((frac.numerator.first as LiteralNode).text, 'x');
    expect(frac.denominator.length, 1);
    expect(frac.denominator.first, isA<ExponentNode>());
    final exp = frac.denominator.first as ExponentNode;
    expect((exp.base.first as LiteralNode).text, 'y');
    expect((exp.power.first as LiteralNode).text, '2');
  });

  test('Converts pure numeric fraction to decimal literal', () {
    final nodes = [
      FractionNode(
        num: [LiteralNode(text: '10')],
        den: [LiteralNode(text: '6')],
      ),
    ];

    final converted = decimalizeExactNodes(nodes);

    expect(converted.length, 1);
    expect(converted.first, isA<LiteralNode>());
    expect((converted.first as LiteralNode).text, '1.6666667');
  });

  test('Keeps variable-only fraction', () {
    final nodes = [
      FractionNode(
        num: [LiteralNode(text: 'x')],
        den: [LiteralNode(text: 'y')],
      ),
    ];

    final converted = decimalizeExactNodes(nodes);

    expect(converted.length, 1);
    expect(converted.first, isA<FractionNode>());
    final frac = converted.first as FractionNode;
    expect((frac.numerator.first as LiteralNode).text, 'x');
    expect((frac.denominator.first as LiteralNode).text, 'y');
  });
}
