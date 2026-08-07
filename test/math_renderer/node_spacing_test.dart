import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_text_style.dart';

void main() {
  group('toDisplayText operator spacing', () {
    // --- Default behavior (forceLeadingOperatorPadding = false) ---
    test('Plus at index 0 without flag: treated as unary, no spacing', () {
      final result = MathTextStyle.toDisplayText('+65');
      expect(result, equals('+65'));
    });

    test('Minus at index 0 without flag: treated as unary, no spacing', () {
      final result = MathTextStyle.toDisplayText('\u221265');
      expect(result, equals('\u221265'));
    });

    test('Multiply at index 0 without flag: trailing space only', () {
      final sign = MathTextStyle.multiplySign;
      final result = MathTextStyle.toDisplayText('\u00D765');
      expect(result, equals('$sign 65'));
    });

    test('Operators mid-text get full spacing', () {
      final result = MathTextStyle.toDisplayText('65+32');
      expect(result, equals('65 + 32'));
    });

    test('Minus mid-text gets full spacing', () {
      final result = MathTextStyle.toDisplayText('65\u221232');
      expect(result, equals('65 \u2212 32'));
    });

    // --- With forceLeadingOperatorPadding = true ---
    test('Plus at index 0 with flag: treated as binary, full spacing', () {
      final result = MathTextStyle.toDisplayText(
        '+65',
        forceLeadingOperatorPadding: true,
      );
      expect(result, equals(' + 65'));
    });

    test('Minus at index 0 with flag: treated as binary, full spacing', () {
      final result = MathTextStyle.toDisplayText(
        '\u221265',
        forceLeadingOperatorPadding: true,
      );
      expect(result, equals(' \u2212 65'));
    });

    test('Multiply at index 0 with flag: full leading + trailing space', () {
      final sign = MathTextStyle.multiplySign;
      final result = MathTextStyle.toDisplayText(
        '\u00D765',
        forceLeadingOperatorPadding: true,
      );
      expect(result, equals(' $sign 65'));
    });

    test('Equals at index 0 with flag: full spacing', () {
      final result = MathTextStyle.toDisplayText(
        '=5',
        forceLeadingOperatorPadding: true,
      );
      expect(result, equals(' = 5'));
    });

    test('Non-operator at index 0: flag has no effect', () {
      final withFlag = MathTextStyle.toDisplayText(
        '65+32',
        forceLeadingOperatorPadding: true,
      );
      final withoutFlag = MathTextStyle.toDisplayText('65+32');
      expect(withFlag, equals(withoutFlag));
    });

    // --- Scientific E special case ---
    test('Minus after scientific E: never padded regardless of flag', () {
      final result = MathTextStyle.toDisplayText(
        '1\u1D07\u221217',
        forceLeadingOperatorPadding: true,
      );
      // The minus after E should NOT be padded
      expect(result, contains('\u1D07\u2212'));
    });

    // --- Consistency tests: spacing matches regardless of node boundaries ---
    test('Spacing after complex node matches mid-text spacing', () {
      // Simulates: FractionNode followed by LiteralNode("+65")
      // The forceLeadingOperatorPadding ensures the leading + gets full spacing
      final afterNode = MathTextStyle.toDisplayText(
        '+65',
        forceLeadingOperatorPadding: true,
      );
      // Simulates: within a single LiteralNode("32+65")
      final midText = MathTextStyle.toDisplayText('32+65');
      // The part after the operator should be identical
      // afterNode = " + 65", midText = "32 + 65"
      // The operator+trailing part "+" should have same spacing
      expect(afterNode.contains(' + 65'), isTrue);
      expect(midText.contains(' + 65'), isTrue);
    });

    test('All binary operators get consistent spacing with flag', () {
      // Plus
      expect(
        MathTextStyle.toDisplayText('+5', forceLeadingOperatorPadding: true),
        equals(' + 5'),
      );

      // Unicode minus
      expect(
        MathTextStyle.toDisplayText(
          '\u22125',
          forceLeadingOperatorPadding: true,
        ),
        equals(' \u2212 5'),
      );

      // ASCII minus (not a padded operator in this system, only unicode minus is)
      expect(
        MathTextStyle.toDisplayText('-5', forceLeadingOperatorPadding: true),
        equals('-5'),
      );

      // Equals
      expect(
        MathTextStyle.toDisplayText('=5', forceLeadingOperatorPadding: true),
        equals(' = 5'),
      );
    });

    // --- Preserving existing behavior ---
    test('Leading unary minus inside sub-expression preserved', () {
      // Without the flag, leading minus should be unary (no spacing)
      final result = MathTextStyle.toDisplayText('-x+3');
      // -x should be attached, +3 should have spacing
      expect(result, startsWith('-x'));
      expect(result, contains(' + 3'));
    });

    test('Unary minus after operator preserved', () {
      // e.g. in "5+-3", the second minus is unary
      final result = MathTextStyle.toDisplayText('5+-3');
      expect(result, contains(' + -3'));
    });
  });
}
