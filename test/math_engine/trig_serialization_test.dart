import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';

void main() {
  test('TrigNode Serialization Test', () {
    // Construct sin(6)
    // TrigNode(function: 'sin', argument: [LiteralNode('6')])
    final trigNode = TrigNode(
      function: 'sin',
      argument: [LiteralNode(text: '6')],
    );

    final serialized = MathExpressionSerializer.serialize([trigNode]);

    // print('Serialized TrigNode: "$serialized"');

    expect(serialized.trim(), equals('sin(6)'));
  });
}
