import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_text_style.dart';
import 'package:klotter/settings/settings.dart';
import 'package:klotter/settings/settings_provider.dart';

/// A font the settings screen offers has to be a font the app actually has.
///
/// Two of the three did not. `pubspec.yaml` declared only OpenSans — Cambria
/// was commented out and Rosemary was neither declared nor even present in
/// `assets/fonts` — so choosing either set a family name that resolves to
/// nothing, and Flutter falls back to the default without complaint. The
/// setting worked perfectly and changed nothing anyone could see.
///
/// Nothing caught it because every layer downstream was correct: the provider
/// stored the choice, `MathTextStyle` used it, the screen rebuilt. The failure
/// was the absence of a declaration in a file no test read.
void main() {
  /// The `fonts:` families declared in pubspec, with the asset each names.
  ///
  /// Parsed rather than hardcoded — a copy of the list here would be one more
  /// thing to keep in step, and it is exactly a list drifting out of step that
  /// this is about.
  Map<String, List<String>> declaredFonts() {
    final List<String> lines = File('pubspec.yaml').readAsLinesSync();
    final Map<String, List<String>> families = <String, List<String>>{};
    String? current;
    bool inFonts = false;

    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('#')) continue;

      if (trimmed == 'fonts:' && line.startsWith('  fonts:')) {
        inFonts = true;
        continue;
      }
      // The top-level `assets:` key ends the font block.
      if (inFonts && line.startsWith('  assets:')) break;
      if (!inFonts) continue;

      final RegExpMatch? family = RegExp(
        r'^\s*-\s*family:\s*(.+)$',
      ).firstMatch(trimmed);
      if (family != null) {
        current = family.group(1)!.trim();
        families[current] = <String>[];
        continue;
      }
      final RegExpMatch? asset = RegExp(
        r'^-?\s*asset:\s*(.+)$',
      ).firstMatch(trimmed);
      if (asset != null && current != null) {
        families[current]!.add(asset.group(1)!.trim());
      }
    }
    return families;
  }

  test('pubspec really does declare some fonts', () {
    // Guards the parser: if it silently returned nothing, every test below
    // would pass by finding no fonts to check.
    expect(
      declaredFonts(),
      isNotEmpty,
      reason: 'the pubspec font block was not read',
    );
  });

  test('every font on offer is declared and its file exists', () {
    final Map<String, List<String>> declared = declaredFonts();

    expect(
      SettingsScreen.availableFonts,
      isNotEmpty,
      reason: 'the settings screen offers no fonts at all',
    );

    for (final String family in SettingsScreen.availableFonts) {
      expect(
        declared.keys,
        contains(family),
        reason:
            '$family is offered in Settings but not declared in pubspec.yaml, '
            'so choosing it falls back to the default and appears to do '
            'nothing',
      );
      for (final String asset in declared[family]!) {
        expect(
          File(asset).existsSync(),
          isTrue,
          reason: '$family names $asset, which is not in the repository',
        );
      }
    }
  });

  test('the default font is one of them', () {
    expect(SettingsScreen.availableFonts, contains(MathTextStyle.fontFamily));
  });

  testWidgets('choosing a font reaches the app theme, not just the maths', (
    tester,
  ) async {
    // The other half of the same bug: the expression asks MathTextStyle for its
    // font, but every button, label and result takes it from the app theme —
    // and the theme was built from the compile-time constant, so half the
    // screen ignored the setting.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    // Read the theme the app builds, not the one on screen: MaterialApp
    // animates between themes, so Theme.of during the crossfade returns an
    // interpolated value and the assertion would depend on pump timing.
    String themeFont() {
      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      return app.theme?.textTheme.bodyMedium?.fontFamily ?? '';
    }

    final String before = themeFont();
    final String other = SettingsScreen.availableFonts.firstWhere(
      (String f) => f != before,
    );

    await settings.setFontFamily(other);
    await tester.pump(const Duration(milliseconds: 900));

    expect(
      themeFont(),
      other,
      reason: 'the app theme kept the old font after the setting changed',
    );
  });
}
