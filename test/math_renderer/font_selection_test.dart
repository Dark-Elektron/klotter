import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_text_style.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  group('Font Selection', () {
    tearDown(() {
      // Reset to default after each test
      MathTextStyle.setFontFamily('OpenSans');
    });

    test('MathTextStyle.setFontFamily changes getStyle() fontFamily', () {
      // Default
      expect(MathTextStyle.fontFamily, equals('OpenSans'));
      expect(MathTextStyle.getStyle(32).fontFamily, equals('OpenSans'));

      // Change to Cambria
      MathTextStyle.setFontFamily('Cambria');
      expect(MathTextStyle.fontFamily, equals('Cambria'));
      expect(MathTextStyle.getStyle(32).fontFamily, equals('Cambria'));

      // Change to Rosemary
      MathTextStyle.setFontFamily('Rosemary');
      expect(MathTextStyle.fontFamily, equals('Rosemary'));
      expect(MathTextStyle.getStyle(32).fontFamily, equals('Rosemary'));
    });

    test('SettingsProvider.forTesting respects fontFamily parameter', () {
      final defaultProvider = SettingsProvider.forTesting();
      expect(defaultProvider.fontFamily, equals('OpenSans'));

      final cambriaProvider = SettingsProvider.forTesting(
        fontFamily: 'Cambria',
      );
      expect(cambriaProvider.fontFamily, equals('Cambria'));

      final rosemaryProvider = SettingsProvider.forTesting(
        fontFamily: 'Rosemary',
      );
      expect(rosemaryProvider.fontFamily, equals('Rosemary'));
    });

    test(
      'MathTextStyle getStyle preserves other properties after font change',
      () {
        MathTextStyle.setFontFamily('Cambria');
        final style = MathTextStyle.getStyle(24);
        expect(style.fontFamily, equals('Cambria'));
        expect(style.fontSize, equals(24));
        expect(style.height, equals(1.0));
      },
    );
  });
}
