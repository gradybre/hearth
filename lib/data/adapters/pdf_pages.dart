import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A PDF's pages, rendered (spec §5.2).
@immutable
class RenderedPdf {
  const RenderedPdf({required this.pages, required this.name});

  /// PNG bytes, one per page, in reading order.
  final List<Uint8List> pages;

  /// The file's own name, which is often the only place a restaurant's name
  /// appears — worth offering as a starting point rather than throwing away.
  final String name;
}

/// Choosing a PDF and turning its pages into pictures (rule 7).
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

  /// Null when the user backed out.
  ///
  /// [maxPages] is a cost ceiling as much as a size one: every page is an
  /// image sent to the model, and a forty-page guide would be a large bill
  /// for a menu nobody reads past page six of.
  Future<RenderedPdf?> pick({int maxPages = 6});
}
