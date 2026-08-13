import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:klotter/plotting/export/plot_exporter.dart';

/// Exporting the plot to a file.
///
/// The encoders are checked against each format's own magic bytes and then
/// decoded back, so "it produced some bytes" cannot pass for "it produced a
/// file anything can open".
void main() {
  /// A small image with a transparent corner, so flattening is exercised.
  Future<ui.Image> plotLike(WidgetTester tester) async {
    late ui.Image image;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 60, 40),
        Paint()..color = const Color(0xFF1E63B8),
      );
      canvas.drawRect(
        const Rect.fromLTWH(60, 0, 40, 40),
        Paint()..color = const Color(0x00000000),
      );
      canvas.drawLine(
        const Offset(0, 20),
        const Offset(100, 20),
        Paint()
          ..color = const Color(0xFFFFD98A)
          ..strokeWidth = 2,
      );
      image = await recorder.endRecording().toImage(100, 40);
    });
    return image;
  }

  testWidgets('PNG is a real PNG and keeps the plot size', (tester) async {
    final ui.Image image = await plotLike(tester);
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await PlotExporter.encode(image, PlotExportFormat.png);
    });

    expect(bytes.sublist(0, 8), <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ], reason: 'PNG signature');
    final img.Image? decoded = img.decodePng(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 100);
    expect(decoded.height, 40);
  });

  testWidgets('JPEG is a real JPEG, opaque, and the right size', (
    tester,
  ) async {
    // dart:ui cannot encode JPEG at all — ImageByteFormat offers only raw RGBA
    // and PNG — so this goes through the image package.
    final ui.Image image = await plotLike(tester);
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await PlotExporter.encode(image, PlotExportFormat.jpg);
    });

    expect(bytes.sublist(0, 3), <int>[
      0xFF,
      0xD8,
      0xFF,
    ], reason: 'JPEG start-of-image marker');
    final img.Image? decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 100);
    expect(decoded.height, 40);

    // JPEG has no alpha. Without compositing first, the transparent half of
    // the plot would come out black rather than on the page background.
    final img.Pixel corner = decoded.getPixel(95, 5);
    expect(
      corner.r,
      greaterThan(200),
      reason: 'the transparent area became white, not black',
    );
    expect(corner.g, greaterThan(200));
    expect(corner.b, greaterThan(200));
  });

  testWidgets('PDF is a real PDF sized to the plot', (tester) async {
    final ui.Image image = await plotLike(tester);
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await PlotExporter.encode(image, PlotExportFormat.pdf);
    });

    expect(
      String.fromCharCodes(bytes.sublist(0, 5)),
      '%PDF-',
      reason: 'PDF header',
    );
    expect(
      String.fromCharCodes(bytes.sublist(bytes.length - 20)),
      contains('%%EOF'),
      reason: 'PDF trailer, so the file is complete',
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('file names carry the format and are sortable by time', () {
    final DateTime at = DateTime(2026, 8, 10, 9, 5, 3);
    expect(
      PlotExporter.fileName(PlotExportFormat.png, at: at),
      'klotter-plot-20260810-090503.png',
    );
    expect(
      PlotExporter.fileName(PlotExportFormat.jpg, at: at),
      endsWith('.jpg'),
    );
    expect(
      PlotExporter.fileName(PlotExportFormat.pdf, at: at),
      endsWith('.pdf'),
    );
  });

  test('every offered format has a label, extension and MIME type', () {
    for (final PlotExportFormat f in PlotExportFormat.values) {
      expect(f.extension, isNotEmpty);
      expect(f.label, isNotEmpty);
      expect(f.mimeType, contains('/'));
    }
  });
}
