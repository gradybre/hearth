import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One page of a PDF, rendered, carrying the number it came from (spec §5.2).
///
/// The number travels with the picture because it is the only thing that can
/// answer "which pages did you actually read?" later. A bare list of images
/// could not: a batch of six that rendered five looked exactly like a batch of
/// five, and the page that failed had no name.
@immutable
class RenderedPage {
  const RenderedPage({required this.number, required this.bytes});

  /// One-based, as the document numbers it and as a person would say it.
  final int number;

  /// PNG bytes.
  final Uint8List bytes;
}

/// A PDF the user chose, before anything has been read from it.
///
/// Choosing is free; reading costs — every page is an image sent to the model.
/// Splitting the two is what lets the screen say "18 pages; shall I read the
/// first six?" instead of reading six and calling them the document.
@immutable
class PickedPdf {
  const PickedPdf({
    required this.name,
    required this.pageCount,
    required this.bytes,
  });

  /// The file's own name, which is often the only place a restaurant's name
  /// appears — worth offering as a starting point rather than throwing away.
  final String name;

  /// How many pages the document has. All of them, not the batch size.
  final int pageCount;

  /// The file, held so a second batch needs no second file dialog. A nutrition
  /// guide is a few megabytes and the alternative is asking somebody to find
  /// the same file again to read page seven.
  final Uint8List bytes;
}

/// What one read got, page by page (spec §5.2).
@immutable
class RenderedPdf {
  const RenderedPdf({required this.pages, this.failed = const <int>[]});

  /// The pages that rendered, in document order.
  final List<RenderedPage> pages;

  /// The pages that would not render, by number.
  ///
  /// Named rather than dropped. A page silently missing from a nutrition guide
  /// is a whole section of a menu that quietly does not exist, and nobody goes
  /// looking for an item they were never told was missing.
  final List<int> failed;

  /// The numbers of the pages that rendered — what may honestly be claimed as
  /// read.
  List<int> get numbers => <int>[
    for (final RenderedPage page in pages) page.number,
  ];
}

/// Choosing a PDF and turning chosen pages of it into pictures (rule 7).
///
/// **Pictures, not the PDF's text**, and that is the point rather than a
/// limitation. Chopt's guide serialises column-major — every name in one
/// block, then every serving size, then blocks of numbers — so reading its
/// text stream means aligning six lists by eye and silently attaching one
/// item's numbers to another. Rendering the page and reading it as a table is
/// what a person does, and it is what the model can do too.
///
/// An interface so the import screen can be exercised without a file dialog,
/// which no widget test can open.
abstract interface class PdfPages {
  /// Whether this platform can open a PDF at all.
  bool get isSupported;

  /// Opens the file dialog. Null when the user backed out.
  ///
  /// Renders nothing and costs nothing: it answers what the document is and
  /// how long it is, so the choice of what to read can be made — and priced —
  /// with the length in view.
  Future<PickedPdf?> pick();

  /// Renders [pages] of [pdf], by one-based page number.
  ///
  /// Asks for exactly what it is given. The batch size is the caller's
  /// decision (see `PdfBatches`), because the caller is the one that knows
  /// what has been read already and what the reader is being asked to pay for.
  Future<RenderedPdf> render(PickedPdf pdf, {required List<int> pages});
}
