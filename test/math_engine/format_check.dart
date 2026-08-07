import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  test('Check current formatting', () {
    // Case 1: 2*sin(pi/9)/3
    final trigNodes = [
      FractionNode(
        num: [
          LiteralNode(text: '2'),
          TrigNode(
            function: 'sin',
            argument: [
              LiteralNode(text: 'pi'), // simplified will be pi
              LiteralNode(text: '/'),
              LiteralNode(text: '9'),
            ],
          ),
        ],
        den: [LiteralNode(text: '3')],
      ),
    ];
    final trigResult = ExactMathEngine.evaluate(trigNodes);
    // ignore: avoid_print
    print(
      'Trig Result Nodes: ${trigResult.mathNodes?.map((n) => n.runtimeType).toList()}',
    );
    if (trigResult.mathNodes != null && trigResult.mathNodes!.isNotEmpty) {
      // If it's FractionNode, it's NOT separated. If it's Literal/Row/Prod, it IS separated.
      // Actually evaluate returns MathNode list.
      // If separated, we expect something like (2/3) * sin(...) which renders as
      // FractionNode(2,3) followed by TrigNode.
      // ignore: avoid_print
      print('Trig First Node: ${trigResult.mathNodes![0].runtimeType}');
    }

    // Case 2: 2*x/3
    final varNodes = [
      FractionNode(
        num: [LiteralNode(text: '2x')],
        den: [LiteralNode(text: '3')],
      ),
    ];
    final varResult = ExactMathEngine.evaluate(varNodes);
    // ignore: avoid_print
    print(
      'Var Result Nodes: ${varResult.mathNodes?.map((n) => n.runtimeType).toList()}',
    );
    if (varResult.mathNodes != null && varResult.mathNodes!.isNotEmpty) {
      // ignore: avoid_print
      print('Var First Node: ${varResult.mathNodes![0].runtimeType}');
    }
  });
}
