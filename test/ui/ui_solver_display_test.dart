import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/math_result_display.dart';

void main() {
  group('MathResultDisplay Exact Solver Integration', () {
    testWidgets('should display quadratic solution', (
      WidgetTester tester,
    ) async {
      try {
        // Create expression: x^2 - 4 = 0
        final nodes = [
          ExponentNode(
            base: [LiteralNode(text: 'x')],
            power: [LiteralNode(text: '2')],
          ),
          LiteralNode(text: ' - 4 = 0'),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.isEmpty, isFalse);
        expect(result.mathNodes, isNotNull);
        // ignore: avoid_print
        print(
          'DEBUG: mathNodes content: ${result.mathNodes!.map((n) => n is LiteralNode ? n.text : n.runtimeType).toList()}',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MathResultDisplay(
                nodes: result.mathNodes!,
                textColor: Colors.black,
              ),
            ),
          ),
        );

        final textWidgets = tester.widgetList<Text>(find.byType(Text));
        for (var tw in textWidgets) {
          // ignore: avoid_print
          print('DEBUG: Found text: "${tw.data}"');
        }

        // Check for basic presence of components
        expect(find.textContaining('x'), findsWidgets);
        expect(find.textContaining('='), findsWidgets);
      } catch (e, stack) {
        // ignore: avoid_print
        print('TEST ERROR: $e');
        // ignore: avoid_print
        print('STACK: $stack');
        rethrow;
      }
    });

    testWidgets('should display system of equations solution', (
      WidgetTester tester,
    ) async {
      try {
        // x + y = 5
        // x - y = 1
        final nodes = [
          LiteralNode(text: 'x + y = 5'),
          NewlineNode(),
          LiteralNode(text: 'x - y = 1'),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.isEmpty, isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MathResultDisplay(
                nodes: result.mathNodes!,
                textColor: Colors.black,
              ),
            ),
          ),
        );

        expect(find.textContaining('x'), findsWidgets);
        expect(find.textContaining('y'), findsWidgets);
        expect(find.textContaining('='), findsWidgets);
      } catch (e, stack) {
        // ignore: avoid_print
        print('TEST ERROR: $e');
        // ignore: avoid_print
        print('STACK: $stack');
        rethrow;
      }
    });
  });
}
