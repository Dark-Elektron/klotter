import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/painters/plot_2d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// The cut surface: the plane a 3D plot is sliced on, coloured by what runs
/// through it.
///
/// A field filling space has no one surface to colour while it is drawn in
/// space, so the colouring menu used to turn a 3D field away outright. Cut to a
/// plane it has one — the plane itself — and without that, slicing a field
/// showed arrows and nothing else.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const int side = 200;

  late SettingsProvider settings;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dark_theme': false,
      'walkthrough_completed_v2': true,
    });
  });

  setUp(() async => settings = await SettingsProvider.create());
  tearDown(() => settings.dispose());

  group('a field filling space can be coloured once it is cut', () {
    final GlobalKey<InlinePlotPanelState> panelKey =
        GlobalKey<InlinePlotPanelState>();

    /// `x x̂ + y ŷ + x·y ẑ` — a field through space, not a sweep.
    List<MathNode> field() => <MathNode>[
      LiteralNode(text: 'x'),
      UnitVectorNode('x'),
      LiteralNode(text: '+y'),
      UnitVectorNode('y'),
      LiteralNode(text: '+x*y'),
      UnitVectorNode('z'),
    ];

    Future<InlinePlotPanelState> pump(
      WidgetTester tester, {
      bool show3D = false,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                width: 360,
                child: InlinePlotPanel(
                  key: panelKey,
                  expression: 'field',
                  nodes: field(),
                  initialView: PlotViewState(show3D: show3D),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return panelKey.currentState!;
    }

    testWidgets('the flat view offers it', (tester) async {
      final InlinePlotPanelState panel = await pump(tester);
      expect(
        panel.canShowSurfaceForTest,
        isTrue,
        reason:
            'a field cut to a plane has a surface to colour, and the menu '
            'that turns it on was refusing to appear',
      );
    });

    testWidgets('in space there is still no one surface to colour', (
      tester,
    ) async {
      final InlinePlotPanelState panel = await pump(tester, show3D: true);
      expect(panel.canShowSurfaceForTest, isFalse);
    });

    testWidgets('and it opens on a plane it can name', (tester) async {
      final InlinePlotPanelState panel = await pump(tester);
      expect(panel.sliceForTest.axis, SliceAxis.z);
      panel.cycleSliceAxisForTest();
      await tester.pump();
      expect(panel.sliceForTest.axis, SliceAxis.x);
    });
  });

  group('the coloured plane moves with the cut', () {
    Future<ByteData> render(VectorFieldParser f, PlaneSlice slice) async {
      final painter = Plot2DPainter(
        function: fn('x'),
        functions: const <PlotExpression>[],
        vectorParser: f,
        xMin: -3,
        xMax: 3,
        yMin: -3,
        yMax: 3,
        plotMode: PlotMode.function,
        fieldType: FieldType.vector,
        showContour: false,
        surfaceMode: SurfaceMode.magnitude,
        colors: colors,
        plotTheme: theme,
        slice: slice,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 200));
      final ui.Image image = await recorder.endRecording().toImage(side, side);
      return (await image.toByteData())!;
    }

    int differing(ByteData a, ByteData b) {
      int n = 0;
      for (int i = 0; i < side * side; i++) {
        final int p = i * 4;
        if (a.getUint8(p) != b.getUint8(p) ||
            a.getUint8(p + 1) != b.getUint8(p + 1) ||
            a.getUint8(p + 2) != b.getUint8(p + 2)) {
          n++;
        }
      }
      return n;
    }

    testWidgets('sliding the plane repaints it', (tester) async {
      await tester.runAsync(() async {
        // Depends on z, so the plane genuinely passes through different field
        // as it climbs.
        final VectorFieldParser rising = VectorFieldParser(
          xComponent: fn('x'),
          yComponent: fn('y'),
          zComponent: fn('z'),
        );
        final ByteData low = await render(rising, const PlaneSlice());
        final ByteData high = await render(rising, const PlaneSlice(offset: 2));
        expect(
          differing(low, high),
          greaterThan(side * side ~/ 10),
          reason:
              'the coloured plane did not follow the slice: '
              '${differing(low, high)} pixels of ${side * side} changed',
        );
      });
    });

    testWidgets('a field that ignores z looks the same all the way up it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // `x x̂ + y ŷ + x·y ẑ` has no z in it, so sliding the z plane through
        // it cannot change anything — worth pinning so that a picture which
        // does not move is not mistaken later for the slider being broken.
        final VectorFieldParser flat = VectorFieldParser(
          xComponent: fn('x'),
          yComponent: fn('y'),
          zComponent: fn('xy'),
        );
        expect(
          differing(
            await render(flat, const PlaneSlice()),
            await render(flat, const PlaneSlice(offset: 2)),
          ),
          0,
        );
        // Cut the other way and it varies, because now the held variable is
        // one the field actually uses.
        expect(
          differing(
            await render(flat, const PlaneSlice(axis: SliceAxis.x)),
            await render(flat, const PlaneSlice(axis: SliceAxis.x, offset: 2)),
          ),
          greaterThan(side * side ~/ 10),
        );
      });
    });
  });
}
