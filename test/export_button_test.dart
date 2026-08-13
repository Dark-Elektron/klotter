import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/plotting/export/plot_exporter.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

/// The export key and the capture behind it.
///
/// The extras keypad had one empty slot; this is what now fills it.
void main() {
  Future<SettingsProvider> seed() async {
    SharedPreferences.setMockInitialValues({
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode({
        'cells': [
          {
            'expression': jsonEncode([
              {'type': 'literal', 'text': 'x^2'},
            ]),
          },
        ],
        'activeIndex': 0,
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

  testWidgets('the extras keypad has no empty slot left', (tester) async {
    final settings = await seed();
    addTearDown(settings.dispose);
    await pump(tester, settings);

    // Swipe to the extras page, which is where the blank sat.
    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1000);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.text('⇪'),
      findsOneWidget,
      reason: 'the export key should occupy the slot that was blank',
    );
  });

  testWidgets('tapping export offers exactly the formats we can produce', (
    tester,
  ) async {
    final settings = await seed();
    addTearDown(settings.dispose);
    await pump(tester, settings);

    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1000);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(find.text('⇪'));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('PNG image'), findsOneWidget);
    expect(find.text('JPEG image'), findsOneWidget);
    expect(find.text('PDF document'), findsOneWidget);
    expect(
      find.textContaining('SVG'),
      findsNothing,
      reason: 'SVG cannot be produced as vectors, so it is not offered',
    );
  });

  testWidgets('the plot captures to an image that encodes', (tester) async {
    final settings = await seed();
    addTearDown(settings.dispose);
    await pump(tester, settings);

    final InlinePlotPanelState panel = tester.state<InlinePlotPanelState>(
      find.byType(InlinePlotPanel).first,
    );

    late ui.Image? image;
    late Uint8List bytes;
    await tester.runAsync(() async {
      image = await panel.capturePlot(pixelRatio: 2.0);
      expect(image, isNotNull, reason: 'the plot is on screen');
      bytes = await PlotExporter.encode(image!, PlotExportFormat.png);
    });

    expect(image!.width, greaterThan(0));
    expect(bytes.sublist(1, 4), <int>[0x50, 0x4E, 0x47]);
  });
}
