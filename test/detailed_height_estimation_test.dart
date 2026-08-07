import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_result_display.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  const fontSize = 20.0;

  test('ComplexNode Height Estimation', () {
    final literal = [LiteralNode(text: 'i')];
    final complex = [
      ComplexNode(content: [LiteralNode(text: 'x')]),
    ];

    final h1 = MathResultDisplay.calculateTotalHeight(literal, fontSize);
    final h2 = MathResultDisplay.calculateTotalHeight(complex, fontSize);

    // ComplexNode should be at least as tall as its content
    // In our implementation, it maps to the same height as its content (Row height)
    expect(h2, greaterThanOrEqualTo(h1));
    expect(h2, equals(fontSize + 6)); // fontSize + 6px padding
  });

  test('Calculus Nodes Padding Verification', () {
    final body = [LiteralNode(text: 'x')];

    final summation = [
      SummationNode(
        variable: [LiteralNode(text: 'i')],
        lower: [LiteralNode(text: '0')],
        upper: [LiteralNode(text: 'n')],
        body: body,
      ),
    ];

    final integral = [
      IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '0')],
        upper: [LiteralNode(text: '1')],
        body: body,
      ),
    ];

    final hSum = MathResultDisplay.calculateTotalHeight(summation, fontSize);
    final hInt = MathResultDisplay.calculateTotalHeight(integral, fontSize);

    // Summation height should include symbol (1.4*fs) + upper (0.7*fs) + lower (0.7*fs) + gaps (0.1*fs + 0.1*fs)
    // 1.4 + 0.7 + 0.7 + 0.2 = 3.0 * fontSize
    // Plus 6px padding
    expect(hSum, equals(3.0 * fontSize + 6));

    // Integral height should include symbol (1.4*fs) + upper (0.7*fs) + lower (0.7*fs) + gaps (0.05*fs + 0.18*fs)
    // 1.4 + 0.7 + 0.7 + 0.23 = 3.03 * fontSize
    // Plus 6px padding
    expect(hInt, equals(3.03 * fontSize + 6));
  });

  test('Empty Line Height Estimation', () {
    final nodes = [
      LiteralNode(text: 'line 1'),
      NewlineNode(),
      NewlineNode(),
      LiteralNode(text: 'line 3'),
    ];

    final totalHeight = MathResultDisplay.calculateTotalHeight(nodes, fontSize);
    final lineHeight = fontSize + 6; // Padded line height

    // Should be 3 lines total
    expect(totalHeight, equals(lineHeight * 3));
  });
}
