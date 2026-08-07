// Regression tests for factorial of parenthesized expressions in both engines.
//
// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

void main() {
  double? _dec(String e) {
    final r = MathSolverNew.solve(e);
    if (r == null || r.isEmpty) return null;
    return double.tryParse(
      r.replaceAll('ᴇ', 'E').replaceAll('−', '-').replaceAll(',', ''),
    );
  }

  group('decimal engine: postfix factorial on parentheses', () {
    test('(19+2)! == 21!', () {
      expect(_dec('(19+2)!'), closeTo(51090942171709440000.0, 1e15));
    });
    test('(3+1)! == 24', () {
      expect(MathSolverNew.solve('(3+1)!'), equals('24'));
    });
    test('(5)! == 120', () {
      expect(MathSolverNew.solve('(5)!'), equals('120'));
    });
    test('plain 5! still works', () {
      expect(MathSolverNew.solve('5!'), equals('120'));
    });
  });

  group('exact engine: postfix factorial on parentheses', () {
    ExactResult _eval(List<MathNode> nodes) => ExactMathEngine.evaluate(nodes);

    test('(3+1)! evaluates to 24 exactly', () {
      final r = _eval([
        ParenthesisNode(content: [LiteralNode(text: '3+1')]),
        LiteralNode(text: '!'),
      ]);
      expect(r.hasError, isFalse);
      expect(r.numerical, closeTo(24, 1e-9));
    });

    test('exact factorial no longer ignores the ! (not 4)', () {
      final r = _eval([
        ParenthesisNode(content: [LiteralNode(text: '3+1')]),
        LiteralNode(text: '!'),
      ]);
      expect(r.numerical, isNot(closeTo(4, 1e-9)));
    });
  });
}
