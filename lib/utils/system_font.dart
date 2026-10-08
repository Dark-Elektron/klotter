import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's own font, where Flutter cannot find it for itself.
///
/// Flutter draws with the fonts the system lists in its font configuration,
/// and on most phones the system font is one of those: no family at all means
/// the platform's default, and that is the system font. Samsung's FlipFont is
/// the exception. A font chosen in a Galaxy phone's settings — Rosemary, say —
/// lives in an app of its own and reaches other apps through Android's
/// Typeface, which Flutter does not use, so Flutter goes on drawing in the
/// default (flutter/flutter#48381). The Android side finds the chosen font's
/// file in the app it came in and hands it over (`SystemFont.kt`), and it is
/// loaded here.
///
/// Everything is on the phone: the font is read from an app already on it.
class SystemFont {
  const SystemFont._();

  static const MethodChannel _channel = MethodChannel('klotter/system_font');

  /// The name the phone's font is loaded under.
  static const String loadedFamily = 'SystemFont';

  static Future<bool>? _loading;
  static bool _loaded = false;

  /// The family to draw in for the phone's font: the one loaded here, or
  /// null — the platform's default — when there was none to load.
  static String? get family => _loaded ? loadedFamily : null;

  /// Find and load the phone's font, once; true when one was loaded.
  static Future<bool> load() => _loading ??= _load();

  static Future<bool> _load() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'flipFont',
      );
      if (bytes == null || bytes.isEmpty) return false;
      final FontLoader loader = FontLoader(loadedFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      return _loaded = true;
    } on Object {
      // No FlipFont, a phone that is not a Galaxy, or a file that would not
      // load: the platform default is the system font then, or the nearest
      // thing to it there is.
      return false;
    }
  }
}
