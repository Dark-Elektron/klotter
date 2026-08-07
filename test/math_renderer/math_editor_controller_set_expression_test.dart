import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  group('MathEditorController.setExpression', () {
    test('updates serialized expr for loaded ans references', () {
      final controller = MathEditorController();

      controller.setExpression([
        AnsNode(index: [LiteralNode(text: '0')]),
        LiteralNode(text: '+2'),
      ]);

      expect(controller.expr, equals('ans0+2'));
    });
  });
}
