import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_text_style.dart';

void main() {
  group('MathTextStyle', () {
    test(
      'Measurement and display text respect multiplication sign setting',
      () {
        // Default should be valid (check what it is currently)
        // ignore: unused_local_variable
        String defaultOutput = MathTextStyle.toDisplayText('2*3');
        // We expect it to be either dot or times, but consistent.

        // Test setting to Times (×)
        MathTextStyle.setMultiplySign('\u00D7');
        String timesOutput = MathTextStyle.toDisplayText('2*3');
        expect(
          timesOutput,
          contains('\u00D7'),
          reason: 'Should contain × when set to ×',
        );
        expect(
          timesOutput,
          isNot(contains('\u00B7')),
          reason: 'Should NOT contain · when set to ×',
        );

        // Test setting to Dot (·)
        MathTextStyle.setMultiplySign('\u00B7');
        String dotOutput = MathTextStyle.toDisplayText('2*3');
        expect(
          dotOutput,
          contains('\u00B7'),
          reason: 'Should contain · when set to ·',
        );
        expect(
          dotOutput,
          isNot(contains('\u00D7')),
          reason: 'Should NOT contain × when set to ·',
        );
      },
    );
  });
}
