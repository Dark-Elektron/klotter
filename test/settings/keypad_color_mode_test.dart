// Tests for the KeypadColorMode setting added for the keypad-color feature.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to themeBased when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = await SettingsProvider.create();
    expect(provider.keypadColorMode, KeypadColorMode.themeBased);
  });

  test('setKeypadColorMode persists and reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = await SettingsProvider.create();

    await provider.setKeypadColorMode(KeypadColorMode.dark);
    expect(provider.keypadColorMode, KeypadColorMode.dark);

    // A fresh provider reads the persisted value.
    final reloaded = await SettingsProvider.create();
    expect(reloaded.keypadColorMode, KeypadColorMode.dark);
  });

  test('unknown stored value falls back to themeBased', () async {
    SharedPreferences.setMockInitialValues({'keypadColorMode': 'bogus'});
    final provider = await SettingsProvider.create();
    expect(provider.keypadColorMode, KeypadColorMode.themeBased);
  });

  test('notifies listeners on change', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = await SettingsProvider.create();

    int notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setKeypadColorMode(KeypadColorMode.light);
    expect(notifications, greaterThan(0));
    expect(provider.keypadColorMode, KeypadColorMode.light);
  });
}
