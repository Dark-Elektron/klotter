import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/plotting/widgets/plot_3d_screen.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The action key builds a plot out of rows.
///
/// It used to insert a `NewlineNode` into the plot's one editor. A line inside a
/// shared node list can carry nothing of its own — no colour, no visibility, no
/// identity — which is what stopped it having a swatch and an eye toggle. A row
/// owns its editor instead.
///
/// The swipe strip is untouched: it still moves between plots. This is the level
/// below the page.
void main() {
  /// Let the row panel and the plot controls finish moving.
  ///
  /// Both animate now — the panel grows into its height, the controls slide to
  /// clear it — so a single pump catches them mid-slide and every position read
  /// is wrong by however far they have left to travel.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<HomePageState> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode(<String, dynamic>{
        'cells': <Map<String, dynamic>>[
          {
            'expression': jsonEncode(<Map<String, dynamic>>[
              {'type': 'literal', 'text': '2x'},
            ]),
          },
        ],
        'activeIndex': 0,
      }),
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GlobalKey<HomePageState> key = GlobalKey<HomePageState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(home: HomePage(key: key)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return key.currentState!;
  }

  testWidgets('a plot starts with one row', (tester) async {
    final HomePageState state = await pump(tester);
    expect(state.rowsOf(0), hasLength(1));
    expect(state.activeRow, 0);
  });

  testWidgets('the action key adds a row and moves the caret to it', (
    tester,
  ) async {
    final HomePageState state = await pump(tester);
    final int before = state.rowsOf(0).length;

    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      state.rowsOf(0),
      hasLength(before + 1),
      reason: 'the action key did not add a row',
    );
    expect(
      state.activeRow,
      before,
      reason:
          'the caret stayed on the old row instead of moving to the new one',
    );
    // And it is a real second editor, not a redrawn one.
    expect(find.byType(MathEditorInline), findsNWidgets(before + 1));
  });

  testWidgets('rows keep their identity when one is added above', (
    tester,
  ) async {
    // The reason a row has an id at all: position shifts, so anything
    // remembered by position — which row is hidden, which colour it wears —
    // would silently move to a different expression.
    final HomePageState state = await pump(tester);
    final String first = state.rowsOf(0).first.id;

    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 300));
    state.activeRow = 0;
    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.rowsOf(0), hasLength(3));
    expect(
      state.rowsOf(0).first.id,
      first,
      reason: 'the original row lost its identity when rows were inserted',
    );
    expect(
      state.rowsOf(0).map((r) => r.id).toSet(),
      hasLength(3),
      reason: 'two rows share an id',
    );
  });

  testWidgets('every row reaches the plot', (tester) async {
    // Each row is drawn as its own curve, so the plot has to be handed all of
    // them — not just the one being typed into.
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      state.plotNodesForTest(0).whereType<NewlineNode>(),
      hasLength(1),
      reason: 'the second row never reached the plot',
    );
  });

  testWidgets('the last row is not removed by backspace', (tester) async {
    // A plot with no expression has nothing to draw and nowhere to type. The
    // whole plot goes instead, which is what backspace on an empty cell did
    // before rows existed.
    final HomePageState state = await pump(tester);
    expect(state.rowsOf(0), hasLength(1));
    expect(
      state.removeActiveRowForTest(),
      isFalse,
      reason: 'the only row of a plot was removed, leaving nothing to type in',
    );
    expect(state.rowsOf(0), hasLength(1));
  });

  testWidgets('an added row can be removed again', (tester) async {
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('\u2318'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.rowsOf(0), hasLength(2));

    expect(state.removeActiveRowForTest(), isTrue);
    await tester.pump();
    expect(state.rowsOf(0), hasLength(1));
    expect(state.activeRow, 0, reason: 'the caret was left past the last row');
  });

  testWidgets('each row carries a swatch and an eye', (tester) async {
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(state.rowsOf(0), hasLength(2));

    expect(
      find.byIcon(Icons.visibility),
      findsNWidgets(2),
      reason: 'every row needs its own toggle',
    );
  });

  testWidgets('the eye hides that row and nothing else', (tester) async {
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    final List<bool> visible = state.rowsOf(0).map((r) => r.visible).toList();
    expect(visible, <bool>[
      false,
      true,
    ], reason: 'the toggle hid the wrong row, or hid more than one');
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('a hidden row still reaches the plot, marked hidden', (
    tester,
  ) async {
    // It must not simply be left out: it keeps its place in the colour order,
    // so dropping it would recolour every row below it.
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    expect(
      state.plotNodesForTest(0).whereType<NewlineNode>(),
      hasLength(1),
      reason: 'the hidden row was dropped from the plot input',
    );
  });

  testWidgets('the plot runs behind the rows', (tester) async {
    // The rows used to sit in an opaque band below the plot, so every row cost
    // the plot that much height. They overlay it now — which is only true if
    // the plot is actually laid out under them.
    final HomePageState state = await pump(tester);
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(state.rowsOf(0), hasLength(2));

    final Rect plot = tester.getRect(find.byType(InlinePlotPanel).first);
    final Rect rows = tester.getRect(find.byType(MathEditorInline).first);
    expect(
      plot.bottom,
      greaterThan(rows.top),
      reason: 'the plot stops above the rows instead of running behind them',
    );
  });

  testWidgets('adding a row does not shrink the plot', (tester) async {
    // The reason for the overlay: with rows plural, an opaque band would eat
    // the plot a row at a time.
    final HomePageState state = await pump(tester);
    final double before =
        tester.getRect(find.byType(InlinePlotPanel).first).height;

    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(state.rowsOf(0), hasLength(2));

    final double after =
        tester.getRect(find.byType(InlinePlotPanel).first).height;
    expect(
      after,
      closeTo(before, 1),
      reason: 'the plot lost ${before - after}px to the new row',
    );
  });

  testWidgets('the plot controls clear the expression rows', (tester) async {
    // The rows float over the plot, so without an inset the reset/fit/pan row
    // and the 2D/3D column sit underneath them and cannot be tapped.
    await pump(tester);
    await settle(tester);

    final Finder panel = find.byType(InlinePlotPanel).first;
    final Rect rows = tester.getRect(find.byType(MathEditorInline).first);
    final InlinePlotPanel widget = tester.widget<InlinePlotPanel>(panel);

    expect(
      widget.bottomInset,
      greaterThan(0),
      reason: 'the plot was never told how much of it the rows cover',
    );

    // And it is actually applied. Checking only the value passed in leaves the
    // controls free to ignore it — which they did, and the mutation passed.
    final Finder home = find.byIcon(Icons.home);
    expect(home, findsOneWidget, reason: 'the reset control is not on screen');
    expect(
      tester.getRect(home).bottom,
      lessThanOrEqualTo(rows.top),
      reason:
          'the reset control sits over the expression rows, so it cannot be '
          'tapped',
    );
    // Measured, not guessed: rows are not a fixed height.
    final Rect plot = tester.getRect(panel);
    expect(
      widget.bottomInset,
      closeTo(plot.bottom - rows.top, 24),
      reason:
          'the inset (${widget.bottomInset}) does not match the height the '
          'rows actually occupy',
    );
  });

  testWidgets('the inset grows when a row is added', (tester) async {
    final HomePageState state = await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final double before =
        tester
            .widget<InlinePlotPanel>(find.byType(InlinePlotPanel).first)
            .bottomInset;

    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.rowsOf(0), hasLength(2));
    await settle(tester);

    final double after =
        tester
            .widget<InlinePlotPanel>(find.byType(InlinePlotPanel).first)
            .bottomInset;
    expect(
      after,
      greaterThan(before),
      reason:
          'a second row was added but the controls were not lifted further '
          'clear ($before then $after)',
    );
  });

  testWidgets('the plot controls still receive taps', (tester) async {
    // The rows overlay the plot, so a control lifted clear of them visually is
    // not necessarily reachable: anything spanning the plot and absorbing
    // pointers would swallow the tap while leaving the button where it looks
    // tappable.
    await pump(tester);
    await settle(tester);

    final Finder home = find.byIcon(Icons.home);
    expect(home, findsOneWidget);

    final Offset at = tester.getCenter(home);
    final Finder hit = find.byWidgetPredicate(
      (Widget w) => w is InlinePlotPanel,
    );
    expect(hit, findsWidgets);

    // Not just "does not throw" — that passes while the tap goes nowhere. A
    // control has to *do* its job, so this taps 3D and checks the view
    // actually switched.
    final Finder toggle = find.text('3D');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(Plot3DScreen),
      findsWidgets,
      reason: 'tapping 3D did nothing — the control is not receiving the tap',
    );
    expect(tester.takeException(), isNull);
    expect(at, isNotNull);
  });

  testWidgets('the row chrome mirrors for a left-handed layout', (
    tester,
  ) async {
    // The same setting that mirrors the keypad. Chrome pinned to one side puts
    // it under the wrong thumb and breaks the promise the setting makes.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      'handedness': Handedness.leftHanded.name,
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    await settings.setHandedness(Handedness.leftHanded);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    final double eye = tester.getCenter(find.byIcon(Icons.visibility)).dx;
    final double editor =
        tester.getCenter(find.byType(MathEditorInline).first).dx;
    expect(
      eye,
      lessThan(editor),
      reason:
          'the eye is still on the right; a left-handed layout puts it under '
          'the reaching thumb',
    );
  });

  testWidgets('the expression is centred in its own slot', (tester) async {
    // The editor shares its row with the swatch and the eye, so it is narrower
    // than the panel. Given the panel's width instead of its own it overflows
    // its box, and the glyphs and caret drift off centre.
    await pump(tester);
    await settle(tester);

    final Rect editor = tester.getRect(find.byType(MathEditorInline).first);
    // A sibling in the stack, not an ancestor: the rows float over the plot.
    final Rect panel = tester.getRect(find.byType(InlinePlotPanel).first);
    expect(
      editor.width,
      lessThan(panel.width),
      reason:
          'the editor is as wide as the whole panel, so it does not fit beside '
          'the swatch and the eye',
    );

    // And it sits between them rather than running under either.
    final Rect dot = tester.getRect(find.byIcon(Icons.visibility).first);
    expect(
      editor.right,
      lessThanOrEqualTo(dot.left + 1),
      reason: 'the expression runs under the eye toggle',
    );
  });

  testWidgets('an empty row cannot spawn another', (tester) async {
    // Otherwise the action key leaves a trail of blank rows, each taking
    // height from the plot and offering a swatch and a toggle for a curve that
    // does not exist.
    final HomePageState state = await pump(tester);
    await settle(tester);

    // The first press is fine: the loaded row has an expression in it.
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(state.rowsOf(0), hasLength(2));

    // The second lands on the row it just made, which is empty.
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(
      state.rowsOf(0),
      hasLength(2),
      reason: 'a blank row was added below a blank row',
    );
  });

  testWidgets('a saved multi-line plot reloads as separate rows', (
    tester,
  ) async {
    // Every save made before rows existed is one expression with newlines in
    // it. Each line has to become a row, or it comes back as a single row that
    // draws the right curves but offers one swatch and one toggle for all of
    // them.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode(<String, dynamic>{
        'cells': <Map<String, dynamic>>[
          {
            'expression': jsonEncode(<Map<String, dynamic>>[
              {'type': 'literal', 'text': '2x'},
              {'type': 'newline'},
              {'type': 'literal', 'text': 'x^2'},
            ]),
          },
        ],
        'activeIndex': 0,
      }),
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GlobalKey<HomePageState> key = GlobalKey<HomePageState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(home: HomePage(key: key)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(
      key.currentState!.rowsOf(0),
      hasLength(2),
      reason: 'the saved lines came back as one row, not two',
    );
    expect(find.byIcon(Icons.visibility), findsNWidgets(2));
  });

  testWidgets('the plot control column mirrors too', (tester) async {
    // The row chrome was mirrored first; the plot has its own leading and
    // trailing sides — the 2D/3D column and the parameter chips — and the
    // setting has to reach those as well or half the interface swaps hands.
    Future<double> columnCentre(Handedness hand) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
      });
      final SettingsProvider settings = await SettingsProvider.create();
      addTearDown(settings.dispose);
      await settings.setHandedness(hand);

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      return tester.getCenter(find.text('3D')).dx;
    }

    final double right = await columnCentre(Handedness.rightHanded);
    final double left = await columnCentre(Handedness.leftHanded);
    expect(
      left,
      lessThan(right),
      reason:
          'the 2D/3D column stayed on the right for a left-handed layout '
          '($right then $left)',
    );
  });

  testWidgets('inserting a plot carries every plot rows with it', (
    tester,
  ) async {
    // The three editor maps are derived from the row store, and assigning into
    // a derived map writes into the temporary it just built — legal Dart, and
    // silently nothing. The shift did exactly that, so a plot inserted before
    // another would have left its rows behind.
    final HomePageState state = await pump(tester);
    await settle(tester);

    // Give plot 0 a second row so there is something to lose.
    state.rowsOf(0).first.controller.insertCharacter('2');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('⌘'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(state.rowsOf(0), hasLength(2));

    state.addDisplayForTest(insertAt: 0);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    // The original plot moved to index 1 and must still have both rows.
    expect(
      state.rowsOf(1),
      hasLength(2),
      reason: 'the shifted plot lost its rows',
    );
    expect(state.rowsOf(0), hasLength(1), reason: 'the new plot is not fresh');
  });
}
