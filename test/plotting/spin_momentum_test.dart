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

/// A flick turns the surface continuously until it is touched again.
///
/// Deliberately not inertia. Momentum that decays to a stop after a second or
/// two reads as the drag having overshot, not as the plot rotating — the point
/// is to watch a surface turn while reading it, without holding a finger down.
void main() {
  // One key per test. Sharing a GlobalKey across tests let state from a
  // torn-down tree be read by the next, which failed only when the file ran as
  // a whole and passed in isolation.
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

  testWidgets('a flick keeps the plot turning', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final before = key.currentState!.rotationZ;
    await tester.fling(find.byType(Plot3DScreen), const Offset(180, 0), 900);
    await tester.pump();

    expect(key.currentState!.isSpinning, isTrue);

    // It keeps moving with no finger down.
    await tester.pump(const Duration(milliseconds: 100));
    final mid = key.currentState!.rotationZ;
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.rotationZ, isNot(equals(mid)));
    expect(key.currentState!.rotationZ, isNot(equals(before)));

    // Stop it explicitly: pumpAndSettle cannot settle a rotation that is
    // designed never to stop on its own.
    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();
  });

  testWidgets('touching it stops the spin', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    await tester.fling(find.byType(Plot3DScreen), const Offset(180, 0), 900);
    await tester.pump();
    expect(key.currentState!.isSpinning, isTrue);

    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();

    expect(key.currentState!.isSpinning, isFalse);
    final stopped = key.currentState!.rotationZ;
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      key.currentState!.rotationZ,
      equals(stopped),
      reason: 'a tap should leave it exactly where it was',
    );
  });

  testWidgets('a hand-rolled drag starts the spin without a fling gesture', (
    tester,
  ) async {
    // The device failure this covers: the recogniser reported no end velocity,
    // so nothing spun even though the finger was clearly moving. Driving the
    // pointer manually — move, then lift immediately — reproduces that, since
    // no synthetic fling velocity is supplied.
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    final TestGesture gesture = await tester.startGesture(centre);
    // Advancing timestamps: TestGesture defaults every event to zero, which
    // makes a velocity tracker correctly see no motion over time.
    Duration t = Duration.zero;
    for (int i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(24, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(
      key.currentState!.isSpinning,
      isTrue,
      reason: 'velocity measured from the drag should carry the spin',
    );

    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();
  });

  testWidgets('a pinch does not start a spin', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final Offset c = tester.getCenter(find.byType(Plot3DScreen));
    final g1 = await tester.startGesture(c - const Offset(20, 0));
    final g2 = await tester.startGesture(c + const Offset(20, 0));
    Duration t = Duration.zero;
    for (int i = 0; i < 5; i++) {
      t += const Duration(milliseconds: 16);
      await g1.moveBy(const Offset(-8, 0), timeStamp: t);
      await g2.moveBy(const Offset(8, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    expect(
      key.currentState!.isSpinning,
      isFalse,
      reason: 'a pinch ends at a chosen zoom and should not drift',
    );
  });

  testWidgets('a slow drag does not start a spin', (tester) async {
    // Ending a careful drag while still moving is not a request to keep going.
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    final TestGesture gesture = await tester.startGesture(centre);
    Duration t = Duration.zero;
    for (int i = 0; i < 8; i++) {
      t += const Duration(milliseconds: 40);
      await gesture.moveBy(const Offset(3, 0), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 40));
    }
    // Pause before lifting, as anyone placing a view precisely would.
    t += const Duration(milliseconds: 200);
    await gesture.moveBy(Offset.zero, timeStamp: t);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(key.currentState!.isSpinning, isFalse);
  });

  testWidgets('it keeps turning rather than settling', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    await tester.fling(find.byType(Plot3DScreen), const Offset(180, 0), 900);
    await tester.pump();

    double previous = key.currentState!.rotationZ;
    // Ten seconds of frames: inertia would have died long before this.
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (i % 100 == 99) {
        expect(
          key.currentState!.rotationZ,
          isNot(equals(previous)),
          reason: 'still turning after ${(i + 1) * 16}ms',
        );
        previous = key.currentState!.rotationZ;
      }
    }
    expect(key.currentState!.isSpinning, isTrue);

    // And a touch still ends it.
    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();
    expect(key.currentState!.isSpinning, isFalse);
  });

  testWidgets('the viewing angle is held while it spins', (tester) async {
    // The bug this covers: any vertical component in the flick became a
    // constant tilt rate that never decayed, so a spin crept to the pole and
    // ended looking straight down whatever angle it started from.
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final double tilt = key.currentState!.rotationX;

    // A diagonal flick: mostly sideways, but with real vertical movement.
    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    final TestGesture gesture = await tester.startGesture(centre);
    Duration t = Duration.zero;
    for (int i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(24, 10), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(key.currentState!.isSpinning, isTrue);
    final double tiltAfterDrag = key.currentState!.rotationX;

    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      key.currentState!.rotationX,
      closeTo(tiltAfterDrag, 1e-9),
      reason: 'the spin must not change the angle it is viewed from',
    );
    expect(
      key.currentState!.rotationZ,
      isNot(closeTo(0.8, 0.01)),
      reason: 'but it did turn',
    );
    expect(tilt, isNot(equals(double.nan)));

    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();
  });

  testWidgets('a purely vertical flick does not spin', (tester) async {
    // There is nothing to spin about: continuous tilting only ends at a pole.
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    final Offset centre = tester.getCenter(find.byType(Plot3DScreen));
    final TestGesture gesture = await tester.startGesture(centre);
    Duration t = Duration.zero;
    for (int i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(0, 20), timeStamp: t);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(key.currentState!.isSpinning, isFalse);
  });

  testWidgets('a hard flick is capped to a readable speed', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    await tester.fling(find.byType(Plot3DScreen), const Offset(300, 0), 8000);
    await tester.pump();

    final start = key.currentState!.rotationZ;
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final turnedPerSecond = (key.currentState!.rotationZ - start).abs();
    expect(
      turnedPerSecond,
      lessThan(2.2),
      reason: 'a whipping surface cannot be read',
    );

    await tester.tap(find.byType(Plot3DScreen));
    await tester.pump();
  });

  testWidgets('resetting the view stops the spin', (tester) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();

    await tester.fling(find.byType(Plot3DScreen), const Offset(180, 0), 900);
    await tester.pump();
    expect(key.currentState!.isSpinning, isTrue);

    key.currentState!.resetView();
    await tester.pump();
    expect(key.currentState!.isSpinning, isFalse);
    expect(key.currentState!.rotationZ, closeTo(0.8, 1e-9));
  });
}
