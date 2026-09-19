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

/// Home is a fixed frame, and editing does not move the window.
///
/// It used to measure the curves and size itself around them, so the same key
/// gave a different window depending on what was plotted, and typing a line
/// moved everything already on screen.
void main() {
  late SettingsProvider settings;
  final AppColors colors = AppColors.fromType(ThemeType.classic);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
    });
    settings = await SettingsProvider.create();
  });
  tearDown(() => settings.dispose());

  Future<Plot2DScreenState> pump(
    WidgetTester tester,
    GlobalKey<Plot2DScreenState> key,
    List<String> lines,
  ) async {
    final List<PlotExpression> curves = <PlotExpression>[
      for (int i = 0; i < lines.length; i++)
        PlotExpression.compile(<MathNode>[LiteralNode(text: lines[i])])
          ..seriesIndex = i,
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 360,
              child: Plot2DScreen(
                key: key,
                plotTheme: PlotThemeData.fromColors(colors),
                function: curves.first,
                functions: curves,
                is3DFunction: false,
                plotMode: PlotMode.function,
                fieldType: FieldType.scalar,
                showContour: false,
                surfaceMode: SurfaceMode.none,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return key.currentState!;
  }

  testWidgets('home is the same frame whatever is plotted', (tester) async {
    for (final String line in <String>['x^2+20', 'x', '0.01x', 'x^2+y^2=1']) {
      final key = GlobalKey<Plot2DScreenState>();
      final Plot2DScreenState state = await pump(tester, key, <String>[line]);
      state.resetView();
      await tester.pump(const Duration(milliseconds: 200));

      final (xMin, xMax, yMin, yMax) = state.ranges;
      expect(xMin, -5, reason: 'x for $line');
      expect(xMax, 5, reason: 'x for $line');
      expect(yMin, -10, reason: 'y for $line');
      expect(yMax, 10, reason: 'y for $line');
    }
  });

  testWidgets('editing a line leaves the window where it was', (tester) async {
    final key = GlobalKey<Plot2DScreenState>();
    final Plot2DScreenState state = await pump(tester, key, <String>['x']);

    // Somewhere of the user's choosing, not the home frame.
    state.setRanges(newXMin: -1, newXMax: 3, newYMin: -2, newYMax: 40);
    await tester.pump(const Duration(milliseconds: 200));
    final before = state.ranges;

    // A second line arrives, as it does while typing.
    await pump(tester, key, <String>['x', 'x^2+500']);

    expect(
      state.ranges,
      before,
      reason: 'the window moved when a line was added: ${state.ranges}',
    );
  });
}
