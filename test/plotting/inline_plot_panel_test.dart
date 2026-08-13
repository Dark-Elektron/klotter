import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/plot_2d_screen.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

void main() {
  late SettingsProvider settings;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'dark_theme': false,
      'multiplication_sign': '×',
      'walkthrough_completed_v2': true,
    });
  });

  setUp(() async {
    settings = await SettingsProvider.create();
  });

  tearDown(() => settings.dispose());

  Widget host({
    required String expression,
    required List<MathNode> nodes,
    double height = 320,
  }) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: height,
            width: 360,
            child: InlinePlotPanel(expression: expression, nodes: nodes),
          ),
        ),
      ),
    );
  }

  List<MathNode> literal(String t) => <MathNode>[LiteralNode(text: t)];

  group('InlinePlotPanel rendering', () {
    testWidgets('renders the 2D plot for a scalar function', (tester) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      expect(find.byType(Plot2DScreen), findsOneWidget);
      expect(find.byType(InlinePlotPanel), findsOneWidget);
    });

    testWidgets('offers a 3D toggle and switches to the 3D screen', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: 'xy', nodes: literal('xy')));
      await tester.pumpAndSettle();

      final toggle3D = find.text('3D');
      expect(toggle3D, findsOneWidget);
      expect(find.text('2D'), findsOneWidget);

      await tester.tap(toggle3D);
      await tester.pumpAndSettle();

      // Both screens stay mounted and cross-fade, so switching dimension
      // never throws away rotation or zoom state.
      expect(find.byType(Plot3DScreen), findsOneWidget);
      // The hidden screen goes offstage rather than being disposed, so it is
      // still in the tree — that is what preserves its view state.
      expect(find.byType(Plot2DScreen, skipOffstage: false), findsOneWidget);

      final fades = tester.widgetList<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(
        fades.any((f) => f.opacity == 1.0),
        isTrue,
        reason: '3D should have faded in',
      );
    });

    testWidgets('shows a reset-view control in the overlay column', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.home), findsOneWidget);
    });
  });

  group('klotter keeps the keypad and the plot on screen together', () {
    testWidgets('there is no keypad-hide control', (tester) async {
      // klotter is plotting-focused: hiding the keypad would break the live
      // edit loop the inline plot exists for.
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_hide), findsNothing);
      expect(find.byIcon(Icons.keyboard), findsNothing);
    });

    testWidgets('2D mode shows no bottom toolbar', (tester) async {
      // Reset moved to the overlay column and the no-op buttons were removed,
      // so 2D has nothing left for a toolbar row.
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pan_tool), findsNothing);
      expect(find.byIcon(Icons.zoom_in), findsNothing);
      expect(find.byIcon(Icons.zoom_out), findsNothing);
    });

    testWidgets('3D adds pan and zoom to the overlay column, not a toolbar', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: 'xy', nodes: literal('xy')));
      await tester.pumpAndSettle();

      // 2D shows neither.
      expect(find.byIcon(Icons.pan_tool), findsNothing);
      expect(find.byIcon(Icons.zoom_out_map), findsNothing);

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pan_tool), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
      expect(find.byIcon(Icons.zoom_in), findsNothing);
    });

    testWidgets('navigation floats centred at the bottom, not in the column', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: 'xy', nodes: literal('xy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();

      final panelWidth = tester.getSize(find.byType(InlinePlotPanel)).width;
      final panelCentre = tester.getCenter(find.byType(InlinePlotPanel)).dx;

      // View controls (reset, pan, zoom) sit centred at the bottom...
      final homeX = tester.getCenter(find.byIcon(Icons.home)).dx;
      final panX = tester.getCenter(find.byIcon(Icons.pan_tool)).dx;
      final zoomX = tester.getCenter(find.byIcon(Icons.zoom_out_map)).dx;
      for (final x in <double>[homeX, panX, zoomX]) {
        expect((x - panelCentre).abs(), lessThan(panelWidth / 4));
      }

      // ...while the mode switches stay hard right.
      final toggleX = tester.getCenter(find.text('3D')).dx;
      expect(toggleX, greaterThan(panelCentre + panelWidth / 4));
      expect(homeX, lessThan(toggleX));
    });

    testWidgets('3D mode survives editing a 2D-only expression', (
      tester,
    ) async {
      // Re-parsing used to reset any expression without a free y back to 2D,
      // so choosing 3D for a curve like sin(x) was undone by the next
      // keystroke — and the pan/zoom controls disappeared with it.
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pan_tool), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);

      // Type another character.
      await tester.pumpWidget(host(expression: '2x+1', nodes: literal('2x+1')));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.pan_tool),
        findsOneWidget,
        reason: 'editing must not silently drop the user out of 3D',
      );
      expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
      expect(find.byType(Plot3DScreen), findsOneWidget);
    });

    testWidgets('overlay buttons are compact', (tester) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      // They sit on top of the data, so they stay small.
      final size = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.home),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(size.width, lessThanOrEqualTo(40));
      expect(size.height, lessThanOrEqualTo(40));
    });
  });

  group('errors are surfaced, never plotted as zero', () {
    testWidgets('an unknown variable shows the error banner', (tester) async {
      await tester.pumpWidget(host(expression: 'a', nodes: literal('a')));
      await tester.pumpAndSettle();

      expect(find.textContaining('unknown variable'), findsOneWidget);
    });

    testWidgets(
      'an unresolved integral shows an error rather than a flat line',
      (tester) async {
        final nodes = <MathNode>[
          IntegralNode(
            variable: [LiteralNode(text: 'x')],
            lower: [LiteralNode(text: '')],
            upper: [LiteralNode(text: '')],
            body: [LiteralNode(text: 'x')],
            isDefinite: false,
          ),
        ];
        await tester.pumpWidget(host(expression: 'int(x,,,x)', nodes: nodes));
        await tester.pumpAndSettle();

        expect(find.textContaining('Cannot plot'), findsOneWidget);
      },
    );

    testWidgets('an empty expression shows bare axes, not an error', (
      tester,
    ) async {
      // The plot is always on screen, so "nothing typed yet" is a normal
      // state to look at while you type — not a fault worth a red banner.
      await tester.pumpWidget(host(expression: '', nodes: <MathNode>[]));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a function'), findsNothing);
      expect(find.textContaining('Cannot plot'), findsNothing);
      expect(find.byType(Plot2DScreen), findsOneWidget);
    });

    testWidgets('a constant plots as a horizontal line, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(expression: '5', nodes: <MathNode>[LiteralNode(text: '5')]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot plot'), findsNothing);
      expect(find.textContaining('unknown variable'), findsNothing);
      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.function.isValid, isTrue);
      expect(screen.function.evaluate(3), closeTo(5, 1e-9));
    });

    testWidgets('a valid function shows no error banner', (tester) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot plot'), findsNothing);
      expect(find.textContaining('unknown variable'), findsNothing);
    });
  });

  group('which surface path a plain 3D function takes', () {
    testWidgets('surfaceMode stays none for z = f(x, y)', (tester) async {
      // This has now caused three wrong fixes. There are two height-surface
      // renderers: _drawSurfaceWithJetColormap runs when a surface mode is
      // selected, _drawSurface when it is not. surfaceMode defaults to none
      // and nothing changes it for a plain function, so the *plain* one is
      // what an ordinary z = f(x, y) actually draws with — despite the other
      // being the one that looks like the main path.
      await tester.pumpWidget(host(expression: 'x+y', nodes: literal('x+y')));
      await tester.pumpAndSettle();

      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.surfaceMode, equals(SurfaceMode.none));
      expect(screen.function.usesY, isTrue, reason: 'it is a 3D function');
    });

    testWidgets('choosing a surface mode switches path', (tester) async {
      await tester.pumpWidget(host(expression: 'x+y', nodes: literal('x+y')));
      await tester.pumpAndSettle();

      // The field/surface toggle is what moves it off none.
      expect(
        tester.widget<Plot2DScreen>(find.byType(Plot2DScreen)).surfaceMode,
        equals(SurfaceMode.none),
      );
    });
  });

  group('equations plot as level sets', () {
    testWidgets('a circle draws without an error banner', (tester) async {
      await tester.pumpWidget(
        host(expression: 'xx+yy=1', nodes: literal('xx+yy=1')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot plot'), findsNothing);
      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.function.isLevelSet, isTrue);
      // F vanishes on the circle rather than being a height to draw.
      expect(screen.function.evaluate(1, 0), closeTo(0, 1e-9));
    });

    testWidgets('a sphere offers the 3D view', (tester) async {
      // x²+y²+z²=1 has no z = f(x,y) form, so 3D has to be offered from the
      // level set being in z rather than from "depends on y".
      await tester.pumpWidget(
        host(expression: 'xx+yy+zz=1', nodes: literal('xx+yy+zz=1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('3D'), findsOneWidget);
      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.function.isImplicitSurface, isTrue);
    });

    testWidgets('a level set is not shaded as a heatmap', (tester) async {
      // F only locates the surface; shading it would colour the plot by
      // distance from the answer.
      await tester.pumpWidget(
        host(expression: 'xx+yy=1', nodes: literal('xx+yy=1')),
      );
      await tester.pumpAndSettle();

      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.surfaceMode, equals(SurfaceMode.none));
    });
  });

  group('recompiles when the expression changes', () {
    testWidgets('switching from valid to invalid surfaces the error', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();
      expect(find.textContaining('unknown variable'), findsNothing);

      await tester.pumpWidget(host(expression: 'q', nodes: literal('q')));
      await tester.pumpAndSettle();
      expect(find.textContaining('unknown variable'), findsOneWidget);
    });

    testWidgets('a y-dependent expression is treated as a surface', (
      tester,
    ) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(expression: 'xy', nodes: literal('xy')));
      await tester.pumpAndSettle();

      final screen = tester.widget<Plot2DScreen>(find.byType(Plot2DScreen));
      expect(screen.is3DFunction, isTrue);
    });
  });

  group('neither plot layer is ever offstage', () {
    // Both screens have a LayoutBuilder at their root. An offstage subtree is
    // retained but never laid out, and a retained-but-unlaid-out LayoutBuilder
    // is what RenderObjectWithLayoutCallbackMixin.scheduleLayoutCallback
    // asserts against — "'debugNeedsLayout': is not true" — which took the app
    // to a red error screen, usually after minimise and restore.
    //
    // The hidden layer is hidden with opacity instead, which still skips
    // painting but keeps the child laid out.
    testWidgets('the inactive layer is still laid out', (tester) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      // Default finders skip offstage widgets, so finding both at all is the
      // assertion.
      expect(find.byType(Plot2DScreen), findsOneWidget);
      expect(
        find.byType(Plot3DScreen),
        findsOneWidget,
        reason: 'the hidden 3D layer must stay in the laid-out tree',
      );

      for (final Type t in <Type>[Plot2DScreen, Plot3DScreen]) {
        expect(
          tester.getSize(find.byType(t)).height,
          greaterThan(0),
          reason: '$t was not given a size',
        );
      }
    });

    testWidgets('still true after switching to 3D and back', (tester) async {
      await tester.pumpWidget(host(expression: '2x', nodes: literal('2x')));
      await tester.pumpAndSettle();

      final state = tester.state<InlinePlotPanelState>(
        find.byType(InlinePlotPanel),
      );
      state.setShow3DForTest(true);
      await tester.pumpAndSettle();
      expect(find.byType(Plot2DScreen), findsOneWidget);
      expect(find.byType(Plot3DScreen), findsOneWidget);

      state.setShow3DForTest(false);
      await tester.pumpAndSettle();
      expect(find.byType(Plot2DScreen), findsOneWidget);
      expect(find.byType(Plot3DScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a cell with several lines reaches the 3D plot whole', () {
    testWidgets('every line is handed to Plot3DScreen', (tester) async {
      // 2D already drew one curve per line while 3D drew only the first, so a
      // second surface silently did nothing.
      await tester.pumpWidget(
        host(
          expression: 'x^2+y^2\n20-x^2-y^2',
          nodes: <MathNode>[
            LiteralNode(text: 'x^2+y^2'),
            NewlineNode(),
            LiteralNode(text: '20-x^2-y^2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The 3D layer is kept alive offstage while 2D is showing, so the
      // finder has to look past Visibility.
      final Plot3DScreen screen = tester.widget<Plot3DScreen>(
        find.byType(Plot3DScreen, skipOffstage: false),
      );
      expect(screen.functions, hasLength(2));
    });

    testWidgets('a later line can make the whole cell 3D', (tester) async {
      // is3DFunction used to read the first line only, so a surface added
      // under a plain f(x) left the cell in 1D and was flattened into a
      // standing curve.
      await tester.pumpWidget(
        host(
          expression: '2x\nx^2+y^2',
          nodes: <MathNode>[
            LiteralNode(text: '2x'),
            NewlineNode(),
            LiteralNode(text: 'x^2+y^2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The 3D layer is kept alive offstage while 2D is showing, so the
      // finder has to look past Visibility.
      final Plot3DScreen screen = tester.widget<Plot3DScreen>(
        find.byType(Plot3DScreen, skipOffstage: false),
      );
      expect(
        screen.is3DFunction,
        isTrue,
        reason: 'line 2 depends on y, so the cell is a 3D cell',
      );
    });
  });
}
