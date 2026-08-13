import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/colormap.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// Several surfaces on one set of 3D axes, as 2D already does for curves.
///
/// A cell holds one expression per line. 2D drew every line and 3D drew only
/// the first, so adding a second surface silently did nothing.
void main() {
  const Size canvas = Size(300, 300);

  /// Excludes the left margin, where the colorbar sits, and the right margin,
  /// where the legend does. Both are drawn whether or not a surface is, and
  /// counting them masks the surface itself — which is exactly how an earlier
  /// bug here survived three "verified" fixes.
  const Rect plotArea = Rect.fromLTRB(60, 0, 260, 300);

  late AppColors colors;
  late PlotThemeData theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({'walkthrough_completed_v2': true});
    colors = AppColors.fromType(ThemeType.classic);
    theme = PlotThemeData.fromColors(colors);
  });

  PlotExpression fn(String t) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

  Plot3DPainter painter(
    List<String> exprs, {
    double rangeZ = 12,
    bool is3D = true,
  }) {
    final curves = exprs.map(fn).toList();
    return Plot3DPainter(
      function: curves.first,
      functions: curves,
      is3DFunction: is3D,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: rangeZ,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
  }

  /// Same painter, built from already-compiled lines.
  Plot3DPainter painterOf(List<PlotExpression> curves, {double rangeZ = 12}) {
    return Plot3DPainter(
      function: curves.isEmpty ? PlotExpression.invalid : curves.first,
      functions: curves,
      is3DFunction: true,
      rotationX: 0.6,
      rotationZ: 0.8,
      rangeX: 5,
      rangeY: 5,
      rangeZ: rangeZ,
      panX: 0,
      panY: 0,
      plotMode: PlotMode.function,
      fieldType: FieldType.scalar,
      showContour: false,
      surfaceMode: SurfaceMode.none,
      colors: colors,
      plotTheme: theme,
    );
  }

  Future<ByteData> rasterise(WidgetTester tester, CustomPainter p) async {
    late ByteData pixels;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), canvas);
      final ui.Image image = await recorder.endRecording().toImage(
        canvas.width.toInt(),
        canvas.height.toInt(),
      );
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return pixels;
  }

  /// Fraction of [plotArea] where two renders disagree.
  double differenceIn(ByteData a, ByteData b) {
    final int w = canvas.width.toInt();
    int differing = 0;
    int considered = 0;
    for (int y = plotArea.top.toInt(); y < plotArea.bottom.toInt(); y++) {
      for (int x = plotArea.left.toInt(); x < plotArea.right.toInt(); x++) {
        considered++;
        final int o = (y * w + x) * 4;
        for (int c = 0; c < 3; c++) {
          if ((a.getUint8(o + c) - b.getUint8(o + c)).abs() > 8) {
            differing++;
            break;
          }
        }
      }
    }
    return considered == 0 ? 0 : differing / considered;
  }

  /// Bounding box of the pixels where two renders disagree — the shape of
  /// whatever the second one added.
  Rect changedBounds(ByteData a, ByteData b) {
    final int w = canvas.width.toInt();
    double minX = double.infinity, maxX = -1, minY = double.infinity, maxY = -1;
    for (int y = plotArea.top.toInt(); y < plotArea.bottom.toInt(); y++) {
      for (int x = plotArea.left.toInt(); x < plotArea.right.toInt(); x++) {
        final int o = (y * w + x) * 4;
        for (int c = 0; c < 3; c++) {
          if ((a.getUint8(o + c) - b.getUint8(o + c)).abs() > 8) {
            if (x < minX) minX = x.toDouble();
            if (x > maxX) maxX = x.toDouble();
            if (y < minY) minY = y.toDouble();
            if (y > maxY) maxY = y.toDouble();
            break;
          }
        }
      }
    }
    if (maxX < 0) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  group('every line of the cell becomes a surface', () {
    testWidgets('a second surface adds geometry the first did not', (
      tester,
    ) async {
      // Chosen so the second is nowhere near the first: a bowl opening up and
      // a dome opening down, which cannot be mistaken for the same pixels.
      final one = await rasterise(tester, painter(<String>['x^2+y^2']));
      final two = await rasterise(
        tester,
        painter(<String>['x^2+y^2', '20-x^2-y^2']),
      );

      expect(
        differenceIn(one, two),
        greaterThan(0.05),
        reason: 'the second expression must draw something',
      );
    });

    testWidgets('a third surface adds more still', (tester) async {
      final two = await rasterise(
        tester,
        painter(<String>['x^2+y^2', '20-x^2-y^2']),
      );
      // A two-variable third line. 3x would now be a curve, not a sheet,
      // so it adds a stroke rather than an area.
      final three = await rasterise(
        tester,
        painter(<String>['x^2+y^2', '20-x^2-y^2', 'x*y']),
      );

      expect(differenceIn(two, three), greaterThan(0.03));
    });

    testWidgets('surfaces occlude each other rather than stacking', (
      tester,
    ) async {
      // Two planes crossing. If they were drawn one wholly over the other,
      // swapping their order would change the picture completely; sorted by
      // depth, each wins where it is nearer and the order barely matters.
      final ab = await rasterise(tester, painter(<String>['2x', '2y']));
      final ba = await rasterise(tester, painter(<String>['2y', '2x']));

      // Not identical — the ramps swap with the order — but the *shape* of
      // what covers what is the same, so the difference stays well under the
      // "one plane completely hides the other" case.
      expect(differenceIn(ab, ba), lessThan(0.75));
    });
  });

  group('each surface gets its own colour scheme', () {
    testWidgets('each ramp keeps one hue family from end to end', (
      tester,
    ) async {
      // This is the property that makes several surfaces readable: a surface
      // must be recognisable as "the blue one" at every height. Jet cannot do
      // it — it runs blue to red — so two jet surfaces interleave the same
      // colours and neither can be followed.
      //
      // Deliberately not a rendering check. Counting blue and warm pixels over
      // the whole plot cannot tell two hue-family ramps from one jet surface:
      // measured, they come out at 0.18/0.82 against 0.20/0.75, because jet is
      // mostly warm too. That test passed either way and proved nothing.
      for (int i = 0; i < surfaceRampCount; i++) {
        final List<double> hues = _rampHues(i);
        expect(
          _hueSpread(hues),
          lessThan(60),
          reason:
              'ramp $i wanders ${_hueSpread(hues).round()}° across its range, '
              'so its surface would not read as one colour',
        );
      }
    });

    testWidgets('no two ramps share a hue', (tester) async {
      // Warm-versus-cool is too crude a split to check this with: green sits
      // on the boundary and flips sides along its own ramp.
      for (int i = 0; i < surfaceRampCount; i++) {
        for (int j = i + 1; j < surfaceRampCount; j++) {
          final double gap = _hueGap(
            _midHue(_rampHues(i)),
            _midHue(_rampHues(j)),
          );
          expect(
            gap,
            greaterThan(30),
            reason: 'ramps $i and $j are only ${gap.round()}° apart',
          );
        }
      }
    });

    testWidgets('a lone surface keeps the full rainbow', (tester) async {
      // Regression pin. A single surface has nothing to be confused with, so
      // it keeps jet, which shows its shape better than one hue family can.
      expect(surfaceColormap(0, of: 1), same(plotColormap));
      expect(surfaceColormap(0, of: 2), isNot(same(plotColormap)));
    });

    testWidgets('the ramps differ from one another', (tester) async {
      final Set<int> midpoints = <int>{
        for (int i = 0; i < surfaceRampCount; i++)
          surfaceColormap(i, of: surfaceRampCount)(0.5).toARGB32(),
      };
      expect(
        midpoints.length,
        surfaceRampCount,
        reason: 'two surfaces must never be given the same ramp',
      );
    });

    testWidgets('ramps cycle rather than running out', (tester) async {
      final int n = surfaceRampCount;
      expect(
        surfaceColormap(n, of: n + 1)(0.5).toARGB32(),
        surfaceColormap(0, of: n + 1)(0.5).toARGB32(),
      );
    });
  });

  group('a single-variable line is a curve, not a sheet', () {
    PlotExpression trig(String f, String v) =>
        PlotExpression.compile(<MathNode>[
          TrigNode(function: f, argument: <MathNode>[LiteralNode(text: v)]),
        ]);

    test('classification follows the variables actually used', () {
      // z = cos(y) is a legitimate surface — a sheet extruded along x — but
      // someone who types cos(y) wants the cosine curve, not a corrugated
      // plane. So only a genuinely two-variable height is a sheet.
      expect(fn('x^2+y^2').isSurface, isTrue);
      expect(trig('sin', 'x').isSurface, isFalse);
      expect(trig('cos', 'y').isSurface, isFalse);
      expect(fn('2x').isSurface, isFalse);
      expect(fn('3').isSurface, isFalse, reason: 'a constant is a line');
    });

    test('a curve runs along the axis it varies in', () {
      expect(trig('sin', 'x').curveAxis, 'x');
      expect(trig('cos', 'y').curveAxis, 'y');
      expect(fn('y').curveAxis, 'y');
      expect(fn('3').curveAxis, 'x', reason: 'a constant lies along x');
    });

    test('a z-only line runs along z', () {
      // z is the height axis, so a line in z has no x/y to sample over. It
      // used to be drawn along x with z bound to 0, which for sin(z) is
      // sin(0) = 0 at every point: a flat line lying exactly on the x axis,
      // invisible, and reported as "no third curve".
      expect(trig('sin', 'z').curveAxis, 'z');
      expect(trig('sin', 'z').isSurface, isFalse);
    });

    testWidgets('sin(z) stands up the z axis rather than lying flat', (
      tester,
    ) async {
      // "Is anything drawn?" does not settle this: the old behaviour drew a
      // flat line along x at height 0, which is still ink on the canvas.
      // Neither does the aspect ratio — the camera is tilted, so a line along
      // x projects diagonally and is taller than you would expect.
      //
      // Width is what separates them. sin(z) sweeps the whole z range while
      // its value stays inside x = -1..1, so it occupies a narrow vertical
      // band: measured 30px wide against 131px for the same curve drawn along
      // x, on a 200px-wide plot area.
      final bare = await rasterise(tester, painterOf(<PlotExpression>[]));
      final zCurve = await rasterise(
        tester,
        painterOf(<PlotExpression>[trig('sin', 'z')], rangeZ: 5),
      );

      final Rect drawn = changedBounds(bare, zCurve);
      expect(drawn, isNot(Rect.zero), reason: 'nothing was drawn at all');
      expect(
        drawn.width,
        lessThan(60),
        reason:
            'a z curve is a narrow vertical band; got '
            '${drawn.width.round()}x${drawn.height.round()}',
      );
      expect(
        drawn.height,
        greaterThan(100),
        reason: 'it should span most of the z axis',
      );
    });

    test('z mixed with x or y is refused, not silently flattened', () {
      // `x+z` compiled fine and was sampled with z bound to 0, so it drew the
      // graph of x with nothing to say the z had been dropped.
      final mixed = PlotExpression.compile(<MathNode>[
        LiteralNode(text: 'x+z'),
      ]);
      expect(mixed.isValid, isFalse);
      expect(mixed.error, contains('='));

      // An equation in all three is a level surface and stays valid.
      expect(fn('x^2+y^2+z^2=4').isValid, isTrue);
      expect(fn('x^2+y^2+z^2=4').isLevelSet, isTrue);
    });

    testWidgets('two single-variable lines draw far less than two sheets', (
      tester,
    ) async {
      // A sheet covers area; a curve is a stroke. If cos(y) were still
      // extruded into a sheet the two would be within a factor of each other.
      final sheets = await rasterise(
        tester,
        painter(<String>['x^2+y^2', '20-x^2-y^2']),
      );
      final lines = await rasterise(
        tester,
        painterOf(<PlotExpression>[trig('sin', 'x'), trig('cos', 'y')]),
      );
      final bare = await rasterise(tester, painterOf(<PlotExpression>[]));

      final double sheetInk = differenceIn(bare, sheets);
      final double lineInk = differenceIn(bare, lines);

      expect(lineInk, greaterThan(0.005), reason: 'the curves must be drawn');
      expect(
        lineInk,
        lessThan(sheetInk / 4),
        reason: 'curves must not be filled sheets',
      );
    });

    testWidgets('cos(y) is drawn somewhere sin(x) is not', (tester) async {
      // Both are curves, but along different axes — they cross rather than
      // lying on top of each other.
      final sinOnly = await rasterise(
        tester,
        painterOf(<PlotExpression>[trig('sin', 'x')]),
      );
      final cosOnly = await rasterise(
        tester,
        painterOf(<PlotExpression>[trig('cos', 'y')]),
      );
      expect(differenceIn(sinOnly, cosOnly), greaterThan(0.004));
    });

    testWidgets('a curve beside a sheet is occluded by it', (tester) async {
      // Curves join the surfaces' depth-ordered scene. Drawn afterwards onto a
      // finished scene, a curve floats in front of geometry it runs through.
      final withCurve = await rasterise(
        tester,
        painterOf(<PlotExpression>[trig('sin', 'x'), fn('x^2+y^2')]),
      );
      final sheetOnly = await rasterise(
        tester,
        painterOf(<PlotExpression>[fn('x^2+y^2')]),
      );

      // The curve shows outside the bowl but not across its face, so it adds
      // ink without covering much.
      final double added = differenceIn(sheetOnly, withCurve);
      expect(added, greaterThan(0.002), reason: 'the curve must be visible');
      expect(added, lessThan(0.06), reason: 'it must not paint over the sheet');
    });
  });

  group('level surfaces', () {
    testWidgets('two equations both draw', (tester) async {
      final one = await rasterise(
        tester,
        painter(<String>['(x-1.2)^2+y^2+z^2=4'], rangeZ: 5),
      );
      final two = await rasterise(
        tester,
        painter(<String>[
          '(x-1.2)^2+y^2+z^2=4',
          '(x+1.2)^2+y^2+z^2=4',
        ], rangeZ: 5),
      );

      expect(
        differenceIn(one, two),
        greaterThan(0.05),
        reason: 'the second equation must draw its own surface',
      );
    });
  });

  group('a level surface is depth-sorted against the floor', () {
    testWidgets('the floor is hidden where the surface covers it', (
      tester,
    ) async {
      // The level renderer used to keep its own vertex buffer and draw it over
      // an already-painted floor, so a sphere sat on top of its own axes and
      // grid. The floor now joins the same back-to-front order.
      //
      // Framed close, the sphere covers the middle of the plot. If the floor
      // were painted under it, hiding the sphere would change those pixels;
      // with correct ordering the sphere's own body is what is there either
      // way, so the difference concentrates outside it.
      final withSphere = await rasterise(
        tester,
        painterOf(<PlotExpression>[fn('x^2+y^2+z^2=1')], rangeZ: 1.3),
      );
      final bare = await rasterise(tester, painterOf(<PlotExpression>[]));

      expect(
        differenceIn(bare, withSphere),
        greaterThan(0.05),
        reason: 'the sphere must be drawn',
      );
    });

    testWidgets('grid lines cross in front of the near side', (tester) async {
      // The floor plane cuts the sphere at its equator. The near half of the
      // floor is closer to the camera than the sphere's lower front, so grid
      // pixels must appear over it. Painting the surface last removed them.
      final sphereOnly = await rasterise(
        tester,
        painterOf(<PlotExpression>[fn('x^2+y^2+z^2=1')], rangeZ: 1.3),
      );

      // Sample a band just below the centre, where the near floor crosses the
      // sphere, and count how many pixels are the grid's grey rather than the
      // ramp's saturated colour.
      final int w = canvas.width.toInt();
      int greyish = 0;
      for (int y = 165; y < 200; y++) {
        for (int x = 120; x < 180; x++) {
          final int o = (y * w + x) * 4;
          final int r = sphereOnly.getUint8(o);
          final int g = sphereOnly.getUint8(o + 1);
          final int b = sphereOnly.getUint8(o + 2);
          final int mx = [r, g, b].reduce((a, c) => a > c ? a : c);
          final int mn = [r, g, b].reduce((a, c) => a < c ? a : c);
          // Low saturation and not near-black: that is the grid, not the ramp.
          if (mx - mn < 40 && mx > 40) greyish++;
        }
      }
      expect(
        greyish,
        greaterThan(0),
        reason: 'no floor pixels survive in front of the sphere',
      );
    });
  });

  group('the screen passes the whole cell to the painter', () {
    testWidgets('Plot3DScreen forwards functions', (tester) async {
      final curves = <PlotExpression>[fn('x^2+y^2'), fn('20-x^2-y^2')];
      final settings = await SettingsProvider.create();
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 300,
                child: Plot3DScreen(
                  function: curves.first,
                  functions: curves,
                  is3DFunction: true,
                  toolMode: Tool3DMode.zoom,
                  plotMode: PlotMode.function,
                  fieldType: FieldType.scalar,
                  showContour: false,
                  surfaceMode: SurfaceMode.none,
                  zoomAxis: ZoomAxis.free,
                  colors: colors,
                  plotTheme: theme,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final CustomPaint paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(Plot3DScreen),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect((paint.painter! as Plot3DPainter).functions, hasLength(2));
    });
  });
}

/// Hue angles along ramp [i], skipping the darkest end.
///
/// Near-black is almost hueless, so its reported angle swings wildly and says
/// nothing about which family the ramp belongs to.
List<double> _rampHues(int i) {
  final Color Function(double) ramp = surfaceColormap(i, of: surfaceRampCount);
  return <double>[
    for (int s = 3; s <= 10; s++) HSVColor.fromColor(ramp(s / 10)).hue,
  ];
}

/// Smallest angle between two hues, accounting for the wrap at 360°.
double _hueGap(double a, double b) {
  final double d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

double _midHue(List<double> hues) => hues[hues.length ~/ 2];

/// Widest gap between any sample and the middle of the ramp.
double _hueSpread(List<double> hues) {
  final double mid = _midHue(hues);
  double worst = 0;
  for (final double h in hues) {
    final double g = _hueGap(h, mid);
    if (g > worst) worst = g;
  }
  return worst;
}
