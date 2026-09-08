import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import 'pdf_pages.dart';

/// [PdfPages] via `file_picker` and `pdfx`.
///
/// The one file that touches either package, so the import screen stays
/// testable and swapping the renderer is a change here (rule 7).
class PdfxPages implements PdfPages {
  const PdfxPages();

  /// How wide a rendered page is, in pixels.
  ///
  /// A nutrition table is small type in a wide grid, and the failure this
  /// whole feature exists to avoid is a number read from the wrong column.
  /// 2,000px is roughly what made Chopt's guide legible when its pages were
  /// rendered by hand; less blurred the digits, and more cost image budget for
  /// nothing.
  static const double _width = 2000;

  @override
  bool get isSupported =>
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  Future<PickedPdf?> pick() async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Choose a nutrition guide',
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    if (file == null) return null;

    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    // Opened only to be counted, then closed again. Nothing is rendered here:
    // the length is what the caller needs to decide what to pay for.
    final pdfx.PdfDocument document = await pdfx.PdfDocument.openData(bytes);
    try {
      return PickedPdf(
        name: file.name,
        pageCount: document.pagesCount,
        bytes: bytes,
      );
    } finally {
      await document.close();
    }
  }

  @override
  Future<RenderedPdf> render(PickedPdf pdf, {required List<int> pages}) async {
    if (pages.isEmpty) return const RenderedPdf(pages: <RenderedPage>[]);

    final pdfx.PdfDocument document = await pdfx.PdfDocument.openData(
      pdf.bytes,
    );
    try {
      final List<RenderedPage> rendered = <RenderedPage>[];
      final List<int> failed = <int>[];

      for (final int number in (pages.toList()..sort())) {
        // Out of range is a caller's mistake rather than a page that would not
        // render, but it is recorded the same way: the alternative is throwing
        // away a batch of six because one number was wrong.
        if (number < 1 || number > pdf.pageCount) {
          failed.add(number);
          continue;
        }
        final Uint8List? bytes = await _renderOne(document, number);
        if (bytes == null) {
          // Named, not dropped. A page that would not render used to vanish
          // from the batch without a word, so a guide came back missing a
          // section and looked complete.
          failed.add(number);
          continue;
        }
        rendered.add(RenderedPage(number: number, bytes: bytes));
      }

      return RenderedPdf(pages: rendered, failed: failed);
    } finally {
      await document.close();
    }
  }

  /// One page, or null if it would not render.
  ///
  /// A throw is caught rather than allowed out: one damaged page in an
  /// eighteen-page guide should cost that page, not the other seventeen and
  /// the money already spent reading them.
  Future<Uint8List?> _renderOne(pdfx.PdfDocument document, int number) async {
    try {
      final pdfx.PdfPage page = await document.getPage(number);
      try {
        final pdfx.PdfPageImage? image = await page.render(
          width: _width,
          // Kept to the page's own proportions; a squashed table is harder
          // to read than a small one.
          height: _width * page.height / page.width,
          format: pdfx.PdfPageImageFormat.png,
          // White rather than transparent: a PNG with no background renders
          // black-on-black wherever the page was blank.
          backgroundColor: '#FFFFFF',
        );
        return image?.bytes;
      } finally {
        await page.close();
      }
    } on Object {
      return null;
    }
  }
}
