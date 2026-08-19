import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last uncaught error, kept across restarts.
///
/// "It crashes sometimes after I have been away from it for a while" cannot be
/// investigated from a description. This is the smallest thing that turns the
/// next occurrence into evidence: the error and its stack are written where a
/// restart can still read them, along with what the app was doing at the time.
///
/// It also answers a question that decides where to look next. An uncaught Dart
/// exception leaves a record here. Being killed by Android for using too much
/// memory does not — the process is gone before any handler runs. So a return
/// from a crash with nothing recorded is itself the finding: it was not Dart
/// that failed, and the memory the app holds while backgrounded is the thing to
/// look at. A record, on the other hand, names the line.
class CrashLog {
  static const String _key = 'last_uncaught_error';

  /// What the app was doing when it failed, updated as the lifecycle changes.
  ///
  /// Held in memory rather than read back at failure time because a handler may
  /// have very little time to run.
  static String _context = 'starting up';

  static set context(String value) => _context = value;

  /// Route uncaught errors here.
  ///
  /// Both handlers keep the framework's own behaviour: [FlutterError.onError]
  /// still presents the error, and the platform handler reports itself as not
  /// having handled the error, so nothing that used to be printed stops being
  /// printed. This only watches.
  static void install() {
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(record(details.exception, details.stack));
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(record(error, stack));
      return false;
    };
  }

  /// Write [error] down. Never throws: a failure here must not become the
  /// crash being reported.
  static Future<void> record(Object error, StackTrace? stack) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Trimmed, because a stack can be long and this is stored in
      // preferences alongside the user's work.
      final String trace = stack?.toString() ?? '';
      await prefs.setString(
        _key,
        <String>[
          DateTime.now().toIso8601String(),
          'while $_context',
          '$error',
          trace.length > 4000 ? trace.substring(0, 4000) : trace,
        ].join('\n'),
      );
    } catch (_) {
      // Nothing useful to do; the app is already failing.
    }
  }

  /// The stored report, or null if the app has not failed since it was cleared.
  static Future<String?> read({SharedPreferences? prefs}) async {
    try {
      final SharedPreferences p =
          prefs ?? await SharedPreferences.getInstance();
      final String? value = p.getString(_key);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear({SharedPreferences? prefs}) async {
    try {
      final SharedPreferences p =
          prefs ?? await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {
      // As above.
    }
  }
}
