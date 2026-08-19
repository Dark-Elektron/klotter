import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Long-pressing the plot, driven through the widget rather than the picker.
///
/// The picker was tested in isolation and worked, and the plots still could not
/// be read from on screen — so what needed testing was the path between the two:
/// whether the gesture arrives, whether the screen is told which components are
/// showing, and whether the marker survives to be drawn.
void main() {
  // Without this SettingsProvider.create() waits on a platform channel that
  // never answers, and every test in the file hangs rather than failing.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const Size canvas = Size(400, 400);
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);

  Future<Plot3DScreenState> pump(
    WidgetTester tester, {
    required PlotExpression function,
    VectorFieldParser? vectorParser,
    ComplexView complexView = ComplexView.initial,
    SurfaceMode surfaceMode = SurfaceMode.none,
    ParameterRange uRange = defaultParameterRange,
    ParameterRange vRange = defaultParameterRange,
  }) async {
    final key = GlobalKey<Plot3DScreenState>();
    final settings = await SettingsProvider.create();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: canvas.width,
              height: canvas.height,
              child: Plot3DScreen(
                key: key,
                function: function,
                functions: <PlotExpression>[function],
                vectorParser: vectorParser,
                is3DFunction: true,
                toolMode: Tool3DMode.zoom,
                plotMode: PlotMode.function,
                fieldType:
                    vectorParser == null ? FieldType.scalar : FieldType.vector,
                showContour: false,
                surfaceMode: surfaceMode,
                complexView: complexView,
                uRange: uRange,
                vRange: vRange,
                zoomAxis: ZoomAxis.free,
                colors: colors,
                plotTheme: theme,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return key.currentState!;
  }

  /// The camera the screen is currently drawing through.
  PlotCamera cameraOf(Plot3DScreenState s) => PlotCamera(
    size: canvas,
    rotationX: s.rotationX,
    rotationZ: s.rotationZ,
    panX: s.panX,
    panY: s.panY,
    rangeX: s.xRange,
    rangeY: s.yRange,
    rangeZ: s.zRange,
  );

  /// Long-press at [point] in data coordinates, and report what was picked.
  ///
  /// Aimed rather than swept: hunting over a grid of presses meant sixteen
  /// full repaints of a complex surface per test, which does not finish. The
  /// projection is known, so the touch can be computed instead of searched
  /// for — and a press at a point known to be on the plot distinguishes
  /// "unpickable" from "nothing was there", which a blind press cannot.
  Future<SurfaceHit?> pressAt(
    WidgetTester tester,
    Plot3DScreenState state,
    double x,
    double y,
    double z,
  ) async {
    final Offset origin = tester.getTopLeft(find.byType(Plot3DScreen));
    await tester.longPressAt(origin + cameraOf(state).project(x, y, z));
    await tester.pump(const Duration(milliseconds: 300));
    return state.tracePointForTest;
  }

  testWidgets('a complex surface can be read from', (tester) async {
    final PlotExpression f = PlotExpression.compile(<MathNode>[
      LiteralNode(text: '(x+yi)^2'),
    ]);
    expect(f.isValid, isTrue, reason: f.error);
    expect(f.isComplex, isTrue);

    final Plot3DScreenState state = await pump(tester, function: f);
    // On the modulus surface, which is what a new complex plot shows.
    const double x = 0.8, y = 0.5;
    final double h = f.evaluateComplex(x, y).magnitude;
    final SurfaceHit? hit = await pressAt(tester, state, x, y, h);
    expect(
      hit,
      isNotNull,
      reason: 'a long press on a complex plot placed no marker',
    );
    expect(
      f.evaluateComplex(hit!.x, hit.y).magnitude,
      closeTo(hit.z, 0.4),
      reason: 'the marker is not on the modulus surface',
    );
  });

  testWidgets('a parametric sweep can be read from', (tester) async {
    final List<MathNode> nodes = <MathNode>[
      TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
      UnitVectorNode('x'),
      LiteralNode(text: '+'),
      TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
      UnitVectorNode('y'),
      LiteralNode(text: '+u'),
      UnitVectorNode('z'),
    ];
    final VectorFieldParser? field = VectorFieldParser.fromNodes(nodes);
    expect(field?.isParametric, isTrue);

    final Plot3DScreenState state = await pump(
      tester,
      function: PlotExpression.compile(nodes),
      vectorParser: field,
      uRange: (min: 0.0, max: 4.0),
    );
    // A point a known way along the helix.
    final SurfaceHit? hit = await pressAt(
      tester,
      state,
      -0.8011436155469337,
      0.5984721441039564,
      2.5,
    );
    expect(hit, isNotNull, reason: 'a long press on a sweep placed no marker');
    expect(hit!.u, isNotNull, reason: 'a sweep hit must name its parameter');
  });

  testWidgets('a vector magnitude surface can be read from', (tester) async {
    final List<MathNode> nodes = <MathNode>[
      LiteralNode(text: 'y'),
      UnitVectorNode('x'),
      LiteralNode(text: '-x'),
      UnitVectorNode('y'),
    ];
    final VectorFieldParser? field = VectorFieldParser.fromNodes(nodes);
    expect(field?.isParametric, isFalse);

    final Plot3DScreenState state = await pump(
      tester,
      function: PlotExpression.compile(nodes),
      vectorParser: field,
      surfaceMode: SurfaceMode.magnitude,
    );
    final SurfaceHit? hit = await pressAt(
      tester,
      state,
      2,
      1,
      field!.magnitude(2, 1),
    );
    expect(
      hit,
      isNotNull,
      reason: 'a long press on a magnitude surface placed no marker',
    );
    expect(hit!.curveIndex, vectorCurveIndex);
  });

  testWidgets('the marker lands where it was touched', (tester) async {
    // "It does not stay on the surface" is a claim about agreement between the
    // picker and the painter: they must invert the same projection, or the dot
    // sits away from the finger.
    final PlotExpression f = PlotExpression.compile(<MathNode>[
      LiteralNode(text: 'x^2+y^2'),
    ]);
    final Plot3DScreenState state = await pump(tester, function: f);
    final Offset origin = tester.getTopLeft(find.byType(Plot3DScreen));
    final Offset touch = origin + const Offset(200, 260);

    await tester.longPressAt(touch);
    await tester.pump(const Duration(milliseconds: 300));
    final SurfaceHit? hit = state.tracePointForTest;
    expect(hit, isNotNull);

    final Offset back = cameraOf(state).project(hit!.x, hit.y, hit.z) + origin;
    expect(
      (back - touch).distance,
      lessThan(8),
      reason: 'the marker projects back to ${back - origin}, not the touch',
    );
  });
}
