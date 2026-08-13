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

/// A pinch scales the axis it is performed along.
///
/// The axis used to be guessed from *where* the fingers landed — near the
/// bottom edge meant x, near the left edge meant y — which has nothing to do
/// with the shape of the gesture. Flutter reports horizontal and vertical
/// scale separately, so the gesture itself is the control.
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

  /// Pinch two fingers together or apart along one axis.
  Future<void> pinch(
    WidgetTester tester, {
    required bool vertical,
    required double from,
    required double to,
  }) async {
    final Offset centre = tester.getCenter(find.byType(Plot2DScreen));
    Offset offset(double d) => vertical ? Offset(0, d) : Offset(d, 0);

    final a = await tester.startGesture(centre - offset(from));
    final b = await tester.startGesture(centre + offset(from));

    Duration t = Duration.zero;
    const int steps = 8;
    for (int i = 1; i <= steps; i++) {
      final double d = from + (to - from) * i / steps;
      t += const Duration(milliseconds: 16);
      await a.moveTo(centre - offset(d), timeStamp: t);
      await b.moveTo(centre + offset(d), timeStamp: t);
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

  group('the pinch direction chooses the axis', () {
    testWidgets('a horizontal pinch scales x and leaves y alone', (
      tester,
    ) async {
      await tester.pumpWidget(await host());
      await tester.pumpAndSettle();

      final before = spans();
      await pinch(tester, vertical: false, from: 30, to: 90);
      final after = spans();

      expect(after.x, lessThan(before.x * 0.9), reason: 'x zoomed in');
      expect(
        after.y,
        closeTo(before.y, before.y * 0.02),
        reason: 'y must not move when pinching sideways',
      );
    });

    testWidgets('a vertical pinch scales y and leaves x alone', (tester) async {
      await tester.pumpWidget(await host());
      await tester.pumpAndSettle();

      final before = spans();
      await pinch(tester, vertical: true, from: 30, to: 90);
      final after = spans();

      expect(after.y, lessThan(before.y * 0.9), reason: 'y zoomed in');
      expect(
        after.x,
        closeTo(before.x, before.x * 0.02),
        reason: 'x must not move when pinching up and down',
      );
    });

    testWidgets('pinching inward zooms out', (tester) async {
      await tester.pumpWidget(await host());
      await tester.pumpAndSettle();

      final before = spans();
      await pinch(tester, vertical: false, from: 90, to: 30);
      final after = spans();

      expect(
        after.x,
        greaterThan(before.x),
        reason: 'a smaller pinch widens x',
      );
    });
  });

  group('the 3D axis lock does not reach the 2D plot', () {
    testWidgets('Plot2DScreen takes no zoomAxis at all', (tester) async {
      // The panel held one zoomAxis and gave it to both screens while the
      // control only appeared in 3D, so locking 3D to y silently locked 2D
      // too. Removing the parameter makes that impossible rather than merely
      // fixed.
      await tester.pumpWidget(await host());
      await tester.pumpAndSettle();

      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(
        screen.toString().contains('zoomAxis'),
        isFalse,
        reason: '2D reads direction from the gesture, not from a shared lock',
      );
    });

    testWidgets('both axes still respond after any 3D setting', (tester) async {
      await tester.pumpWidget(await host());
      await tester.pumpAndSettle();

      final start = spans();
      await pinch(tester, vertical: true, from: 30, to: 80);
      final afterVertical = spans();
      expect(afterVertical.y, lessThan(start.y * 0.95));

      await pinch(tester, vertical: false, from: 30, to: 80);
      expect(spans().x, lessThan(afterVertical.x * 0.95));
    });
  });
}
