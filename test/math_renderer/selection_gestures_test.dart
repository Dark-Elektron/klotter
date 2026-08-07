import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/expression_selection.dart';

void main() {
  group('MathEditor Gesture Tests', () {
    late MathEditorController controller;

    setUp(() {
      controller = MathEditorController();
      MathEditorController.setClipboard(null);
    });

    Widget buildTestWidget({double width = 400}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 200,
              child: MathEditorInline(controller: controller, showCursor: true),
            ),
          ),
        ),
      );
    }

    testWidgets('Double tap within expression triggers paste menu', (
      tester,
    ) async {
      controller.expression = [LiteralNode(text: '123')];
      MathEditorController.setClipboard(
        MathClipboard(nodes: [LiteralNode(text: '9')]),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final editor = find.byType(MathEditorInline);
      final center = tester.getCenter(editor);

      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('Double tap far left/right triggers paste menu', (
      tester,
    ) async {
      controller.expression = [LiteralNode(text: '23')];
      MathEditorController.setClipboard(
        MathClipboard(nodes: [LiteralNode(text: '9')]),
      );

      await tester.pumpWidget(buildTestWidget(width: 800));
      await tester.pump();

      final editor = find.byType(MathEditorInline);
      final center = tester.getCenter(editor);

      // Far Left
      final farLeft = center - const Offset(300, 0);
      await tester.tapAt(farLeft);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(farLeft);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('Paste'),
        findsOneWidget,
        reason: 'Paste menu missing at far left',
      );

      // Dismiss
      await tester.tapAt(const Offset(1, 1)); // Top left
      await tester.pump(const Duration(milliseconds: 100));

      // Far Right
      final farRight = center + const Offset(300, 0);
      await tester.tapAt(farRight);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(farRight);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('Paste'),
        findsOneWidget,
        reason: 'Paste menu missing at far right',
      );
    });
  });
}
