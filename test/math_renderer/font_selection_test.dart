import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

      // Change to STIX Two Math
      MathTextStyle.setFontFamily('STIXTwoMath');
      expect(MathTextStyle.fontFamily, equals('STIXTwoMath'));
      expect(MathTextStyle.getStyle(32).fontFamily, equals('STIXTwoMath'));

      // Change to Rosemary
      MathTextStyle.setFontFamily('Rosemary');
      expect(MathTextStyle.fontFamily, equals('Rosemary'));
      expect(MathTextStyle.getStyle(32).fontFamily, equals('Rosemary'));
    });

    test('SettingsProvider.forTesting respects fontFamily parameter', () {
      final defaultProvider = SettingsProvider.forTesting();
      expect(defaultProvider.fontFamily, equals('OpenSans'));

      final stixProvider = SettingsProvider.forTesting(
        fontFamily: 'STIXTwoMath',
      );
      expect(stixProvider.fontFamily, equals('STIXTwoMath'));

      final rosemaryProvider = SettingsProvider.forTesting(
        fontFamily: 'Rosemary',
      );
      expect(rosemaryProvider.fontFamily, equals('Rosemary'));
    });

    test(
      'MathTextStyle getStyle preserves other properties after font change',
      () {
        MathTextStyle.setFontFamily('STIXTwoMath');
        final style = MathTextStyle.getStyle(24);
        expect(style.fontFamily, equals('STIXTwoMath'));
        expect(style.fontSize, equals(24));
        expect(style.height, equals(1.0));
      },
    );
  });

  group('a saved font', () {
    tearDown(() => MathTextStyle.setFontFamily('OpenSans'));

    test('Cambria carries over to STIX Two Math', () async {
      // Cambria Math is Microsoft's and had to leave the app. Someone who
      // chose it gets the free font that replaced it, not a family name that
      // resolves to nothing.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'fontFamily': 'Cambria',
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      expect(settings.fontFamily, 'STIXTwoMath');
      expect(MathTextStyle.fontFamily, 'STIXTwoMath');
    });

    test('one that is no longer offered falls back to the default', () async {
      // The settings menu cannot show a value it does not list.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'fontFamily': 'NoSuchFont',
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      expect(settings.fontFamily, 'OpenSans');
      expect(SettingsProvider.availableFonts, contains(settings.fontFamily));
    });
  });
}
