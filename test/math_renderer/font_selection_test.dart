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

      // No family at all: the platform's default, which is what the System
      // choice draws in where there was nothing to load.
      MathTextStyle.setFontFamily(null);
      expect(MathTextStyle.fontFamily, isNull);
      expect(MathTextStyle.getStyle(32).fontFamily, isNull);
    });

    test('SettingsProvider.forTesting respects fontFamily parameter', () {
      final defaultProvider = SettingsProvider.forTesting();
      expect(defaultProvider.fontFamily, equals('OpenSans'));

      final stixProvider = SettingsProvider.forTesting(
        fontFamily: 'STIXTwoMath',
      );
      expect(stixProvider.fontFamily, equals('STIXTwoMath'));

      final systemProvider = SettingsProvider.forTesting(
        fontFamily: SettingsProvider.systemFont,
      );
      expect(systemProvider.fontFamily, equals(SettingsProvider.systemFont));
      // Nothing to load off a phone, so the platform's default.
      expect(systemProvider.textFontFamily, isNull);
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

    test("Rosemary carries over to the phone's own font", () async {
      // It was carried in the app for a phone whose own font it is, and the
      // phone's own font replaced it.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'fontFamily': 'Rosemary',
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      expect(settings.fontFamily, SettingsProvider.systemFont);
      expect(MathTextStyle.fontFamily, settings.textFontFamily);
    });

    test("choosing the phone's font reaches the maths", () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      await settings.setFontFamily(SettingsProvider.systemFont);
      expect(settings.fontFamily, SettingsProvider.systemFont);
      // Off a phone there is nothing to load: the platform's default.
      expect(settings.textFontFamily, isNull);
      expect(MathTextStyle.fontFamily, isNull);
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
