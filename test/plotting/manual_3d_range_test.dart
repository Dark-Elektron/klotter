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

/// Setting the 3D box by hand.
///
/// Auto-fitting cannot serve a surface that diverges: sin(r)/r² climbs without
/// limit at the origin, so no automatic height is right and the box has to be
/// settable — which is what the 2D plot has always had.
void main() {
  Future<Plot3DScreenState> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    final colors = AppColors.fromType(ThemeType.classic);
    final key = GlobalKey<Plot3DScreenState>();
    final curve = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x^2+y^2'),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: Plot3DScreen(
                key: key,
                function: curve,
                functions: <PlotExpression>[curve],
                is3DFunction: true,
                toolMode: Tool3DMode.zoom,
                plotMode: PlotMode.function,
                fieldType: FieldType.scalar,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                zoomAxis: ZoomAxis.free,
                colors: colors,
                plotTheme: PlotThemeData.fromColors(colors),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return key.currentState!;
  }

  testWidgets('the box takes the extents it is given', (tester) async {
    final state = await pump(tester);
    state.setBox(xMin: -3, xMax: 3, yMin: -7, yMax: 7, zMin: -2, zMax: 2);
    await tester.pump();

    expect(state.xRange, closeTo(3, 1e-9));
    expect(state.yRange, closeTo(7, 1e-9));
    expect(state.zRange, closeTo(2, 1e-9));
  });

  testWidgets('an off-centre pair keeps whatever it has to reach', (
    tester,
  ) async {
    // The box is centred on the origin, so it has to span the further of the
    // two bounds rather than silently cropping one of them.
    final state = await pump(tester);
    state.setBox(xMin: -1, xMax: 9, yMin: -4, yMax: 4);
    await tester.pump();
    expect(state.xRange, closeTo(9, 1e-9));
  });

  testWidgets('a height set by hand is not overwritten by auto-fitting', (
    tester,
  ) async {
    // Auto-fitting runs whenever the expression or window changes; it must not
    // undo a height the user chose.
    final state = await pump(tester);
    state.setBox(xMin: -5, xMax: 5, yMin: -5, yMax: 5, zMin: -0.5, zMax: 0.5);
    await tester.pump();
    expect(state.zRange, closeTo(0.5, 1e-9));

    state.autoScaleForTest();
    await tester.pump();
    expect(
      state.zRange,
      closeTo(0.5, 1e-9),
      reason: 'auto-fit reclaimed a height the user had set',
    );
  });

  testWidgets('setting only x and y leaves the height alone', (tester) async {
    final state = await pump(tester);
    final double before = state.zRange;
    state.setBox(xMin: -2, xMax: 2, yMin: -2, yMax: 2);
    await tester.pump();
    expect(state.zRange, closeTo(before, 1e-9));
  });
}
