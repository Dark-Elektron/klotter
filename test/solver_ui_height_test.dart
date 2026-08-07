import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_result_display.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  test('Exact Result Height Estimation Logic', () {
    final singleLine = [LiteralNode(text: 'x = 3')];
    final h1 = MathResultDisplay.calculateTotalHeight(singleLine, 20.0);

    final quadratic = [
      LiteralNode(text: 'x = -1 + '),
      RootNode(radicand: [LiteralNode(text: '2')], isSquareRoot: true),
      NewlineNode(),
      LiteralNode(text: 'x = -1 - '),
      RootNode(radicand: [LiteralNode(text: '2')], isSquareRoot: true),
    ];
    final h2 = MathResultDisplay.calculateTotalHeight(quadratic, 20.0);

    expect(h1 > 0, isTrue);
    expect(h2 > h1, isTrue);
    // ignore: avoid_print
    print('ESTIMATED HEIGHTS: 1-line: $h1, 2-line-root: $h2');
  });

  test('Decimal Result Height Estimation Logic (multi-line text)', () {
    const singleLine = 'x = 3';
    const multiLine = 'x = 3\ny = -1\nz = 2';

    final h1 = MathResultDisplay.calculateTextHeight(singleLine, 20.0);
    final h3 = MathResultDisplay.calculateTextHeight(multiLine, 20.0);

    expect(h1 > 0, isTrue);
    expect(h3 > h1, isTrue);
  });

  testWidgets('Exact Result Display Widget Rendering', (
    WidgetTester tester,
  ) async {
    final nodes = [
      LiteralNode(text: 'x = '),
      FractionNode(
        num: [LiteralNode(text: '1')],
        den: [LiteralNode(text: '2')],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathResultDisplay(
            nodes: nodes,
            fontSize: 20.0,
            textColor: Colors.black,
          ),
        ),
      ),
    );

    expect(find.byType(MathResultDisplay), findsOneWidget);
  });
}
