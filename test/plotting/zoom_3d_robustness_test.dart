import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Free zoom in 3D, which measured a pinch the same wrong way the 2D one did.
///
/// Both axes were driven by horizontalScale / verticalScale: ratios against the
/// finger separation at the moment the gesture started. For a pinch along one
/// axis the separation across it is a pixel or two, so the cross-axis ratio is
/// noise, and when the fingers line up it is a division by zero.
///
/// It fails differently here than in 2D. `xRange /= Infinity` is 0, which the
/// clamp lifts to 50 — so a vertical pinch threw the x axis to maximum
/// zoom-out — and the NaN from the reading after that is dropped by the
/// `> 0.001` test, since every comparison against NaN is false. 2D had no such
/// clamp, so there the bad window reached the painter and threw.
void main() {
  late GlobalKey<Plot3DScreenState> key;

  setUp(() => key = GlobalKey<Plot3DScreenState>());

  Future<Widget> host() async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
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
                child: Plot3DScreen(
                  key: key,
                  function: PlotExpression.compile(<MathNode>[
                    LiteralNode(text: 'xy'),
                  ]),
                  is3DFunction: true,
                  toolMode: Tool3DMode.zoom,
                  plotMode: PlotMode.function,
                  fieldType: FieldType.scalar,
                  showContour: false,
                  surfaceMode: SurfaceMode.magnitude,
                  zoomAxis: ZoomAxis.free,
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

  Future<void> pinch(
    WidgetTester tester, {
    required bool vertical,
    required double from,
    required double to,
    double jitter = 0,
    double jitterDrift = 0,
    int levelTail = 0,
  }) async {
    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    Offset along(double d) => vertical ? Offset(0, d) : Offset(d, 0);
    Offset across(double d) => vertical ? Offset(d, 0) : Offset(0, d);

    final a = await tester.startGesture(centre - along(from) - across(jitter));
    final b = await tester.startGesture(centre + along(from));

    Duration t = Duration.zero;
    const int steps = 8;
    // [levelTail] extra updates with the fingers exactly level, so the
    // cross-axis separation stays at zero for several readings rather than
    // touching it once on the way past.
    for (int i = 1; i <= steps + levelTail; i++) {
      final double p = (i < steps ? i : steps) / steps;
      final double d = from + (to - from) * p;
      final double j = i <= steps ? jitter + jitterDrift * p : 0;
      t += const Duration(milliseconds: 16);
      await a.moveTo(centre - along(d) - across(j), timeStamp: t);
      await b.moveTo(centre + along(d), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
  }

  void expectBoxUsable() {
    final s = key.currentState!;
    for (final MapEntry<String, double> e
        in <String, double>{
          'xRange': s.xRange,
          'yRange': s.yRange,
          'zRange': s.zRange,
        }.entries) {
      expect(
        e.value.isFinite,
        isTrue,
        reason: '${e.key} went non-finite: ${e.value}',
      );
      expect(e.value, greaterThan(0), reason: '${e.key} collapsed');
    }
  }

  testWidgets('a horizontal pinch zooms x and leaves y alone', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final s = key.currentState!;
    final beforeY = s.yRange;
    await pinch(
      tester,
      vertical: false,
      from: 30,
      to: 90,
      jitter: 2,
      jitterDrift: 3,
    );

    expectBoxUsable();
    expect(s.xRange, lessThan(5.0), reason: 'spreading sideways zooms x in');
    expect(s.yRange, closeTo(beforeY, beforeY * 0.05), reason: 'y unchanged');
  });

  testWidgets('a vertical pinch zooms y and leaves x alone', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final s = key.currentState!;
    final beforeX = s.xRange;
    await pinch(
      tester,
      vertical: true,
      from: 30,
      to: 90,
      jitter: 2,
      jitterDrift: 3,
    );

    expectBoxUsable();
    expect(s.yRange, lessThan(5.0), reason: 'spreading up and down zooms y in');
    expect(s.xRange, closeTo(beforeX, beforeX * 0.05), reason: 'x unchanged');
  });

  testWidgets('fingers levelling out do not slam x to the zoom limit', (
    tester,
  ) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    // Here the horizontal separation reaches zero mid-gesture. Dividing by it
    // gave an Infinity delta, and `xRange /= Infinity` is 0, which the clamp
    // lifted to the far end of its range: a vertical pinch threw the x axis
    // straight to maximum zoom-out. The NaN from the reading after that was
    // then silently dropped by the `> 0.001` test, since NaN compares false —
    // so in 3D this misbehaved rather than throwing the way 2D did.
    await pinch(
      tester,
      vertical: true,
      from: 30,
      to: 90,
      jitter: 6,
      jitterDrift: -6,
      levelTail: 3,
    );

    expectBoxUsable();
    expect(tester.takeException(), isNull);
    expect(
      key.currentState!.xRange,
      closeTo(5.0, 0.5),
      reason: 'a vertical pinch must leave x where it was',
    );
  });
}
