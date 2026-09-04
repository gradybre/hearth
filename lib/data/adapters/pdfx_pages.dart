import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';

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
  Future<RenderedPdf?> pick({int maxPages = 6}) async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Choose a nutrition guide',
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    if (file == null) return null;

    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final PdfDocument document = await PdfDocument.openData(bytes);
    try {
      final List<Uint8List> pages = <Uint8List>[];
      final int count = document.pagesCount < maxPages
          ? document.pagesCount
          : maxPages;

      for (int number = 1; number <= count; number++) {
        final PdfPage page = await document.getPage(number);
        try {
          final PdfPageImage? rendered = await page.render(
            width: _width,
            // Kept to the page's own proportions; a squashed table is harder
            // to read than a small one.
            height: _width * page.height / page.width,
            format: PdfPageImageFormat.png,
            // White rather than transparent: a PNG with no background renders
            // black-on-black wherever the page was blank.
            backgroundColor: '#FFFFFF',
          );
          if (rendered != null) pages.add(rendered.bytes);
        } finally {
          await page.close();
        }
      }
      return RenderedPdf(pages: pages, name: file.name);
    } finally {
      await document.close();
    }
  }
}
