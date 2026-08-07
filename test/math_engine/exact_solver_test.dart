import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('Exact Equation Solving', () {
    test('Solve single linear equation: x + 1 = 3', () {
      final nodes = [
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '1'),
        LiteralNode(text: '='),
        LiteralNode(text: '3'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      // Result should be x = 2
      final resultString = _nodesToString(result.mathNodes!);
      expect(resultString, contains('x = 2'));
    });

    test('Solve quadratic equation: x^2 - 5x + 6 = 0', () {
      final nodes = [
        ExponentNode(
          base: [LiteralNode(text: 'x')],
          power: [LiteralNode(text: '2')],
        ),
        LiteralNode(text: '-'),
        LiteralNode(text: '5'),
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '6'),
        LiteralNode(text: '='),
        LiteralNode(text: '0'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final resultString = _nodesToString(result.mathNodes!);
      expect(resultString, contains('x = 2'));
      expect(resultString, contains('x = 3'));
    });

    test('Solve system of equations (2x2): x+y=3, x-y=1', () {
      final nodes = [
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '='),
        LiteralNode(text: '3'),
        NewlineNode(),
        LiteralNode(text: 'x'),
        LiteralNode(text: '-'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '='),
        LiteralNode(text: '1'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final resultString = _nodesToString(result.mathNodes!);
      expect(resultString, contains('x = 2'));
      expect(resultString, contains('y = 1'));
    });

    test('Solve system with fractions: x+y=1/2, x-y=0', () {
      final nodes = [
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '='),
        FractionNode(
          num: [LiteralNode(text: '1')],
          den: [LiteralNode(text: '2')],
        ),
        NewlineNode(),
        LiteralNode(text: 'x'),
        LiteralNode(text: '-'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '='),
        LiteralNode(text: '0'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final resultString = _nodesToString(result.mathNodes!);
      // x = 1/4, y = 1/4
      expect(resultString, contains('x = (1/4)'));
      expect(resultString, contains('y = (1/4)'));
    });

    test('Solve 3x3 system (from user image)', () {
      final nodes = [
        LiteralNode(text: 'x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '2'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '-'),
        LiteralNode(text: 'z'),
        LiteralNode(text: '='),
        LiteralNode(text: '1'),
        NewlineNode(),
        LiteralNode(text: '2'),
        LiteralNode(text: 'x'),
        LiteralNode(text: '-'),
        LiteralNode(text: '3'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '+'),
        LiteralNode(text: '6'),
        LiteralNode(text: 'z'),
        LiteralNode(text: '='),
        LiteralNode(text: '2'),
        NewlineNode(),
        LiteralNode(text: 'x'),
        LiteralNode(text: '-'),
        LiteralNode(text: '3'),
        LiteralNode(text: 'y'),
        LiteralNode(text: '+'),
        LiteralNode(text: '2'),
        LiteralNode(text: 'z'),
        LiteralNode(text: '='),
        LiteralNode(text: '-'),
        LiteralNode(text: '4'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final resultString = _nodesToString(result.mathNodes!);
      // Solutions: x = -26/19, y = 40/19, z = 35/19
      expect(resultString, contains('x = -(26/19)'));
      expect(resultString, contains('y = (40/19)'));
      expect(resultString, contains('z = (35/19)'));
    });
    test('Simplify sqrt(56/5) and sqrt(2/9)', () {
      // sqrt(56/5) = 2*sqrt(70)/5
      final nodes1 = [
        RootNode(
          isSquareRoot: true,
          radicand: [
            FractionNode(
              num: [LiteralNode(text: '56')],
              den: [LiteralNode(text: '5')],
            ),
          ],
        ),
      ];
      final result1 = ExactMathEngine.evaluate(nodes1);
      final nodes1Res = result1.mathNodes;
      if (nodes1Res == null) fail('nodes1Res is null');
      final resultString1 = _nodesToString(nodes1Res);

      // sqrt(2/9) = sqrt(2)/3
      final nodes2 = [
        RootNode(
          isSquareRoot: true,
          radicand: [
            FractionNode(
              num: [LiteralNode(text: '2')],
              den: [LiteralNode(text: '9')],
            ),
          ],
        ),
      ];
      final result2 = ExactMathEngine.evaluate(nodes2);
      final nodes2Res = result2.mathNodes;
      if (nodes2Res == null) fail('nodes2Res is null');
      final resultString2 = _nodesToString(nodes2Res);
      expect(resultString1, equals('(2/5)√(2)(70)'));
      expect(resultString2, equals('(1/3)√(2)(2)'));
    });
  });
}

String _nodesToString(List<MathNode> nodes) {
  StringBuffer sb = StringBuffer();
  for (var node in nodes) {
    if (node is LiteralNode) {
      sb.write(node.text.replaceAll('−', '-'));
    } else if (node is FractionNode) {
      sb.write('(');
      sb.write(_nodesToString(node.numerator));
      sb.write('/');
      sb.write(_nodesToString(node.denominator));
      sb.write(')');
    } else if (node is RootNode) {
      sb.write('√');
      if (node.index.isNotEmpty) {
        sb.write('(');
        sb.write(_nodesToString(node.index));
        sb.write(')');
      }
      sb.write('(');
      sb.write(_nodesToString(node.radicand));
      sb.write(')');
    } else if (node is NewlineNode) {
      sb.write('\n');
    }
  }
  return sb.toString();
}
