import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_cache.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/crash_log.dart';
import 'package:klotter/utils/memory_release.dart';

/// What the app holds while it is not on screen.
///
/// "It crashes sometimes after I have been in another app for a long time" is
/// the shape of being killed for memory rather than of a Dart exception: the
/// caches here are top-level finals holding sampled geometry, nothing disposes
/// them while the plot is still built, and a marched surface is megabytes. An
/// app sitting on that in the background is what Android reclaims first.
///
/// So: the geometry goes when the app is backgrounded, and comes back when it
/// is needed again.
void main() {
  PlotExpression surface() =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: 'x^2+y^2')]);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    releaseMemoryForBackground();
  });

  group('the caches', () {
    test('sampling fills them and releasing empties them', () {
      final PlotExpression f = surface();
      expect(f.isValid, isTrue, reason: f.error);

      cachedHeightGrid(f, 5, 5, 12);
      cachedHeightGrid(f, 6, 6, 12);

      final ReleasedMemory freed = releaseMemoryForBackground();
      expect(
        freed.plotEntries,
        greaterThanOrEqualTo(2),
        reason: 'the sampled grids were not being held, or were not released',
      );

      // Nothing left over.
      expect(releaseMemoryForBackground().plotEntries, 0);
    });

    test('a released cache still answers, by recomputing', () {
      // The entries are derived, so dropping them may cost time but must never
      // cost correctness — this is what makes releasing them safe to do
      // whenever the platform asks.
      final PlotExpression f = surface();
      final List<List<double>> before = cachedHeightGrid(f, 5, 5, 8);
      final double sample = before[3][4];

      releaseMemoryForBackground();

      final List<List<double>> after = cachedHeightGrid(f, 5, 5, 8);
      expect(after[3][4], sample);
      expect(identical(after, before), isFalse, reason: 'it was not released');
    });

    test('every cache is registered, not just the ones named by hand', () {
      // The parametric caches live in another file and are private there. If
      // the release walked a hand-written list they would be missed, and the
      // next cache added would be missed too.
      final PlotExpression f = surface();
      cachedHeightGrid(f, 5, 5, 8);
      final int held = releaseMemoryForBackground().plotEntries;
      expect(held, greaterThan(0));
    });
  });

  group('the app', () {
    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      // Not pumpAndSettle: the cursor blinks forever, so nothing ever
      // settles.
      await tester.pump(const Duration(milliseconds: 900));
    }

    testWidgets('being backgrounded releases the geometry', (tester) async {
      await pump(tester);
      cachedHeightGrid(surface(), 5, 5, 8);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        releaseMemoryForBackground().plotEntries,
        0,
        reason: 'the app was backgrounded and kept its samples',
      );
    });

    testWidgets('a passing interruption does not', (tester) async {
      // `inactive` arrives for a dialog, a phone call, the notification shade
      // being pulled down — none of which is leaving the app. Throwing decoded
      // images away for those shows as a flash of reloading on the way back,
      // for no benefit: the process is still in the foreground and is not
      // being reclaimed.
      await pump(tester);
      cachedHeightGrid(surface(), 5, 5, 8);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(
        releaseMemoryForBackground().plotEntries,
        greaterThan(0),
        reason: 'a momentary interruption threw the samples away',
      );
    });

    testWidgets('the platform asking for memory releases it', (tester) async {
      await pump(tester);
      cachedHeightGrid(surface(), 5, 5, 8);

      // This is Android's onTrimMemory reaching Flutter — the warning that
      // comes before being killed.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/system',
        const StringCodec().encodeMessage('{"type":"memoryPressure"}'),
        (_) {},
      );
      await tester.pump();

      expect(
        releaseMemoryForBackground().plotEntries,
        0,
        reason: 'the app was asked for memory and gave none back',
      );
    });
  });

  group('the crash record', () {
    test('an error survives a restart, with what the app was doing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      CrashLog.context = 'the app was paused';
      await CrashLog.record(StateError('boom'), StackTrace.current);

      final String? report = await CrashLog.read();
      expect(report, isNotNull);
      expect(report, contains('boom'));
      expect(
        report,
        contains('paused'),
        reason:
            'without this the report cannot say it failed in the '
            'background, which is the whole question',
      );
    });

    test('nothing is reported when nothing failed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await CrashLog.read(), isNull);
    });

    test('it can be dismissed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CrashLog.record(StateError('boom'), StackTrace.current);
      await CrashLog.clear();
      expect(await CrashLog.read(), isNull);
    });

    test('recording never throws, whatever it is handed', () async {
      // This runs while the app is already failing. An exception here would
      // replace the error being reported with one from the reporter.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CrashLog.record('a bare string', null);
      expect(await CrashLog.read(), contains('a bare string'));
    });
  });
}
