// Tests for the definite/indefinite split of integral and derivative nodes.

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/expression_selection.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';

void main() {
  group('isDefinite persistence (JSON round-trip)', () {
    test('indefinite integral round-trips isDefinite=false', () {
      final nodes = <MathNode>[
        IntegralNode(body: [LiteralNode(text: 'x')], isDefinite: false),
      ];
      final json = MathExpressionSerializer.serializeToJson(nodes);
      final restored = MathExpressionSerializer.deserializeFromJson(json);
      expect(restored.first, isA<IntegralNode>());
      expect((restored.first as IntegralNode).isDefinite, isFalse);
    });

    test('definite integral round-trips isDefinite=true', () {
      final nodes = <MathNode>[IntegralNode(isDefinite: true)];
      final restored = MathExpressionSerializer.deserializeFromJson(
        MathExpressionSerializer.serializeToJson(nodes),
      );
      expect((restored.first as IntegralNode).isDefinite, isTrue);
    });

    test('indefinite derivative round-trips isDefinite=false', () {
      final nodes = <MathNode>[
        DerivativeNode(body: [LiteralNode(text: 'x')], isDefinite: false),
      ];
      final restored = MathExpressionSerializer.deserializeFromJson(
        MathExpressionSerializer.serializeToJson(nodes),
      );
      expect((restored.first as DerivativeNode).isDefinite, isFalse);
    });

    test('legacy JSON without isDefinite defaults to definite', () {
      // Old persisted data had no isDefinite field.
      const legacy =
          '[{"type":"integral","variable":[],"lower":[],"upper":[],"body":[]}]';
      final restored = MathExpressionSerializer.deserializeFromJson(legacy);
      expect((restored.first as IntegralNode).isDefinite, isTrue);
    });
  });

  group('deep copy preserves isDefinite', () {
    test('MathClipboard.deepCopyNode keeps indefinite integral', () {
      final original = IntegralNode(isDefinite: false);
      final copy = MathClipboard.deepCopyNode(original);
      expect(copy, isA<IntegralNode>());
      expect((copy as IntegralNode).isDefinite, isFalse);
    });

    test('MathClipboard.deepCopyNode keeps indefinite derivative', () {
      final copy = MathClipboard.deepCopyNode(
        DerivativeNode(isDefinite: false),
      );
      expect((copy as DerivativeNode).isDefinite, isFalse);
    });
  });

  group('engine treats an indefinite integral as symbolic', () {
    test('indefinite integral of x is a finite (non-empty) exact result', () {
      final result = ExactMathEngine.evaluate(<MathNode>[
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          body: [LiteralNode(text: 'x')],
          isDefinite: false,
        ),
      ]);
      // The engine drives definite/indefinite off the (empty) bounds, so an
      // indefinite integral evaluates to the antiderivative rather than erroring.
      expect(result.hasError, isFalse);
      expect(result.isEmpty, isFalse);
    });
  });
}
