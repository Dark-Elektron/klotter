import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// What a plot can be saved as.
///
/// SVG is deliberately absent. A Flutter [ui.Picture] does not expose the
/// drawing operations that produced it, so there is no way to recover vectors
/// from a CustomPainter — an .svg here could only be a raster in an `<image>`
/// wrapper, which fails the one expectation the format carries.
enum PlotExportFormat {
  png,
  jpg,

  /// A single page sized to the plot, holding it as an image. `dart:ui` can
  /// only rasterise, so the PDF is not resolution-independent either; it is
  /// rendered above screen resolution so it stays clean in a document.
  pdf,
}

extension PlotExportFormatInfo on PlotExportFormat {
  String get extension => switch (this) {
    PlotExportFormat.png => 'png',
    PlotExportFormat.jpg => 'jpg',
    PlotExportFormat.pdf => 'pdf',
  };

  String get label => switch (this) {
    PlotExportFormat.png => 'PNG image',
    PlotExportFormat.jpg => 'JPEG image',
    PlotExportFormat.pdf => 'PDF document',
  };

  String get mimeType => switch (this) {
    PlotExportFormat.png => 'image/png',
    PlotExportFormat.jpg => 'image/jpeg',
    PlotExportFormat.pdf => 'application/pdf',
  };
}

/// Turn a rendered plot into file bytes.
///
/// Kept free of Flutter widgets and the file system so it can be tested on its
/// own: give it an image, get bytes back.
class PlotExporter {
  /// Quality for [PlotExportFormat.jpg], where 100 is least compressed.
  ///
  /// A plot is flat colour and thin lines, which is what JPEG handles worst —
  /// ringing shows up around axis lines well before it would on a photograph.
  /// High enough that the artefacts stay invisible at normal zoom.
  static const int jpegQuality = 95;

  /// Encode [image] as [format].
  ///
  /// JPEG has no alpha, so a transparent background would come out black; it
  /// is composited onto [background] first. PNG keeps whatever transparency
  /// the plot had.
  static Future<Uint8List> encode(
    ui.Image image,
    PlotExportFormat format, {
    int background = 0xFFFFFFFF,
  }) async {
    if (format == PlotExportFormat.png) {
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (png == null) {
        throw StateError('The plot could not be encoded as PNG');
      }
      return png.buffer.asUint8List();
    }

    final img.Image raster = await _toRaster(image);

    if (format == PlotExportFormat.jpg) {
      return img.encodeJpg(_flatten(raster, background), quality: jpegQuality);
    }

    // PDF: one page the same shape as the plot, with the image filling it.
    final Uint8List pngBytes = img.encodePng(_flatten(raster, background));
    final pw.Document doc = pw.Document();
    final PdfPageFormat page = PdfPageFormat(
      image.width.toDouble(),
      image.height.toDouble(),
    );
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build:
            (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(pngBytes), fit: pw.BoxFit.contain),
            ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  /// dart:ui to the `image` package, which is what can encode JPEG — there is
  /// no JPEG option in [ui.ImageByteFormat].
  static Future<img.Image> _toRaster(ui.Image image) async {
    final ByteData? raw = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (raw == null) {
      throw StateError('The plot could not be read back as pixels');
    }
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: raw.buffer,
      numChannels: 4,
    );
  }

  /// Composite onto an opaque background.
  static img.Image _flatten(img.Image src, int argb) {
    final img.Image out = img.Image(width: src.width, height: src.height);
    img.fill(
      out,
      color: img.ColorRgb8(
        (argb >> 16) & 0xFF,
        (argb >> 8) & 0xFF,
        argb & 0xFF,
      ),
    );
    img.compositeImage(out, src);
    return out;
  }

  /// A filename that says which plot it came from and when.
  static String fileName(PlotExportFormat format, {DateTime? at}) {
    final DateTime t = at ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'klotter-plot-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}.${format.extension}';
  }
}
