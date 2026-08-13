import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// A pinch made by real fingers, which are never perfectly level.
///
/// directional_zoom_test.dart moves both fingers at exactly the same x for a
/// vertical pinch. Flutter's ScaleGestureRecognizer special-cases that: an
/// initial span of exactly 0 makes horizontalScale a constant 1.0, so the
/// horizontal ratio is never actually exercised. A hand cannot hold that, and
/// on a device the ratio between two near-zero spans is either noise or a
/// division by zero — which is how the window became NaN and the painter threw
/// "Unsupported operation: Infinity or NaN toInt" on every frame.
void main() {
  late GlobalKey<Plot2DScreenState> key;

  setUp(() {
    key = GlobalKey<Plot2DScreenState>();
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
  });

  Future<Widget> host() async {
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final colors = AppColors.of(context);
              return SizedBox(
                width: 300,
                height: 300,
                child: Plot2DScreen(
                  key: key,
                  function: PlotExpression.compile(<MathNode>[
                    LiteralNode(text: '2x'),
                  ]),
                  is3DFunction: false,
                  plotMode: PlotMode.function,
                  fieldType: FieldType.scalar,
                  showContour: false,
                  surfaceMode: SurfaceMode.none,
                  colors: colors,
                  plotTheme: PlotThemeData.fromColors(colors),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Pinch along one axis, with [jitter] logical pixels of cross-axis offset
  /// between the two fingers — what a hand actually produces.
  Future<void> pinch(
    WidgetTester tester, {
    required bool vertical,
    required double from,
    required double to,
    double jitter = 0,
    double jitterDrift = 0,
  }) async {
    final Offset centre = tester.getCenter(find.byType(Plot2DScreen));
    Offset along(double d) => vertical ? Offset(0, d) : Offset(d, 0);
    Offset across(double d) => vertical ? Offset(d, 0) : Offset(0, d);

    final a = await tester.startGesture(centre - along(from) - across(jitter));
    final b = await tester.startGesture(centre + along(from));

    Duration t = Duration.zero;
    const int steps = 8;
    for (int i = 1; i <= steps; i++) {
      final double d = from + (to - from) * i / steps;
      // The cross-axis offset wanders during the gesture, as fingers do.
      final double j = jitter + jitterDrift * i / steps;
      t += const Duration(milliseconds: 16);
      await a.moveTo(centre - along(d) - across(j), timeStamp: t);
      await b.moveTo(centre + along(d), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
  }

  ({double x, double y}) spans() {
    final (xMin, xMax, yMin, yMax) = key.currentState!.ranges;
    return (x: xMax - xMin, y: yMax - yMin);
  }

  void expectWindowUsable() {
    final (xMin, xMax, yMin, yMax) = key.currentState!.ranges;
    for (final v in <double>[xMin, xMax, yMin, yMax]) {
      expect(v.isFinite, isTrue, reason: 'window went non-finite: $v');
    }
    expect(xMax - xMin, greaterThan(0), reason: 'x window collapsed');
    expect(yMax - yMin, greaterThan(0), reason: 'y window collapsed');
  }

  testWidgets('a vertical pinch by unlevel fingers leaves x alone', (
    tester,
  ) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final before = spans();
    // 2px apart horizontally, drifting to 5px: a tiny baseline that a ratio
    // magnifies into a large bogus x zoom.
    await pinch(
      tester,
      vertical: true,
      from: 30,
      to: 90,
      jitter: 2,
      jitterDrift: 3,
    );
    expectWindowUsable();

    final after = spans();
    expect(after.y, lessThan(before.y * 0.9), reason: 'y zoomed in');
    expect(
      after.x,
      closeTo(before.x, before.x * 0.05),
      reason: 'fingers 2px out of level must not zoom x',
    );
  });

  testWidgets('a horizontal pinch by unlevel fingers leaves y alone', (
    tester,
  ) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final before = spans();
    await pinch(
      tester,
      vertical: false,
      from: 30,
      to: 90,
      jitter: 2,
      jitterDrift: 3,
    );
    expectWindowUsable();

    final after = spans();
    expect(after.x, lessThan(before.x * 0.9), reason: 'x zoomed in');
    expect(
      after.y,
      closeTo(before.y, before.y * 0.05),
      reason: 'fingers 2px out of level must not zoom y',
    );
  });

  testWidgets('fingers converging to level does not produce a NaN window', (
    tester,
  ) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    // Starts 6px out of level and ends exactly level. The cross-axis span
    // reaches zero mid-gesture, so the per-axis ratio divides by it.
    await pinch(
      tester,
      vertical: true,
      from: 30,
      to: 90,
      jitter: 6,
      jitterDrift: -6,
    );

    expectWindowUsable();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a diagonal pinch still scales both axes', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final before = spans();
    final Offset centre = tester.getCenter(find.byType(Plot2DScreen));
    final a = await tester.startGesture(centre - const Offset(30, 30));
    final b = await tester.startGesture(centre + const Offset(30, 30));

    Duration t = Duration.zero;
    for (int i = 1; i <= 8; i++) {
      final double d = 30 + 60 * i / 8;
      t += const Duration(milliseconds: 16);
      await a.moveTo(centre - Offset(d, d), timeStamp: t);
      await b.moveTo(centre + Offset(d, d), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();

    expectWindowUsable();
    final after = spans();
    expect(after.x, lessThan(before.x * 0.9), reason: 'diagonal zooms x');
    expect(after.y, lessThan(before.y * 0.9), reason: 'diagonal zooms y');
  });

  testWidgets('zooming far in keeps the window paintable', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    // Repeated hard zoom-in: the span shrinks toward zero, and a grid spacing
    // of zero divides the axis bounds by it.
    for (int i = 0; i < 25; i++) {
      await pinch(tester, vertical: false, from: 10, to: 140, jitter: 1);
      expectWindowUsable();
    }
    expect(tester.takeException(), isNull);
  });
}
