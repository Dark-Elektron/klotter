import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// Reopening the app used to show the first cell's expression while the page
/// dots said you were on the third: the PageView was built at page 0 while
/// activeIndex had been restored. One swipe in either direction resynced them.
void main() {
  Future<SettingsProvider> seed(
    int activeIndex, {
    List<Map<String, dynamic>?>? views,
  }) async {
    final texts = <String>['1+1', '2x', 'xx'];
    final cells = <Map<String, dynamic>>[
      for (int i = 0; i < texts.length; i++)
        {
          'expression': jsonEncode(<Map<String, dynamic>>[
            {'type': 'literal', 'text': texts[i]},
          ]),
          if (views != null && views[i] != null) 'plotView': views[i],
        },
    ];
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': cells,
        'activeIndex': activeIndex,
      }),
    });
    return SettingsProvider.create();
  }

  Future<void> pump(WidgetTester tester, SettingsProvider settings) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('the third cell is shown when it was the active one', (
    tester,
  ) async {
    final settings = await seed(2);
    addTearDown(settings.dispose);
    await pump(tester, settings);

    final page = tester.widget<PageView>(find.byType(PageView).first);
    expect(
      page.controller?.page?.round(),
      equals(2),
      reason: 'the view must open on the cell that was left open',
    );
  });

  testWidgets('the first cell needs no jump', (tester) async {
    final settings = await seed(0);
    addTearDown(settings.dispose);
    await pump(tester, settings);

    final page = tester.widget<PageView>(find.byType(PageView).first);
    expect(page.controller?.page?.round(), equals(0));
  });

  testWidgets('a saved 3D view reopens in 3D', (tester) async {
    // Swiping away from a 3D plot used to drop it back to 2D, because the
    // panel can be disposed before its state is read.
    final settings = await seed(
      1,
      views: <Map<String, dynamic>?>[
        null,
        const PlotViewState(show3D: true, rotationX: 1.2).toJson(),
        null,
      ],
    );
    addTearDown(settings.dispose);
    await pump(tester, settings);

    // A PageView builds more than the current page, so search rather than
    // taking the first.
    final views = find
        .byType(InlinePlotPanel)
        .evaluate()
        .map((e) => (e.widget as InlinePlotPanel).initialView)
        .toList();
    expect(
      views.any((v) => v.show3D && (v.rotationX - 1.2).abs() < 1e-9),
      isTrue,
      reason: 'the cell must reopen in 3D, with its camera',
    );
  });

  testWidgets('a saved 2D window reopens framed as it was left', (
    tester,
  ) async {
    final settings = await seed(
      0,
      views: <Map<String, dynamic>?>[
        const PlotViewState(xMin: 0, xMax: 6.28).toJson(),
        null,
        null,
      ],
    );
    addTearDown(settings.dispose);
    await pump(tester, settings);

    final views = find
        .byType(InlinePlotPanel)
        .evaluate()
        .map((e) => (e.widget as InlinePlotPanel).initialView)
        .toList();
    expect(
      views.any((v) => v.xMin == 0 && (v.xMax - 6.28).abs() < 1e-9),
      isTrue,
      reason: 'the cell must reopen framed as it was left',
    );
  });

  testWidgets('an out-of-range saved index is clamped, not crashed on', (
    tester,
  ) async {
    final settings = await seed(9);
    addTearDown(settings.dispose);
    await pump(tester, settings);

    final page = tester.widget<PageView>(find.byType(PageView).first);
    expect(page.controller?.page?.round(), equals(2));
  });
}
