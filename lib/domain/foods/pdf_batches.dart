/// Which pages of a nutrition guide the next read asks for, and how to say so
/// (spec §5.2).
///
/// A guide is read in batches because every page is an image sent to the
/// model: a forty-page document read whole is a large bill for a menu nobody
/// reads past page six of. That is a good reason to *default* to six pages and
/// no reason at all to pretend the other thirty-four are not there, which is
/// what reading the first six silently and calling it the document amounted
/// to. Six pages of eighteen is a fine offer. Six pages of eighteen described
/// as "the menu" is a wrong answer with no way to notice.
///
/// Pure, so the arithmetic that decides what gets paid for is tested without
/// a file dialog, a renderer or a model (§9.1).
class PdfBatches {
  const PdfBatches._();

  /// How many pages one read asks for.
  ///
  /// Six because that is what the picker has always taken, and because a
  /// nutrition guide's tables are usually in its first few pages. It is a
  /// default, not a ceiling: [next] keeps offering until the document runs
  /// out.
  static const int size = 6;

  /// The next pages to read, given what has been read already.
  ///
  /// Ascending, and always the lowest unread pages first — a guide is read
  /// front to back, and an offer to read pages 13–18 while 7–12 are still
  /// unread would be a strange thing to put in front of somebody.
  ///
  /// Empty when there is nothing left, which is the signal to stop offering.
  /// [batchSize] rather than `size`: a parameter named for the constant it
  /// defaults to reads as though it defaults to itself, and the next person
  /// to look has to work out which of the two `size` means before they can
  /// trust the arithmetic underneath it.
  static List<int> next({
    required int pageCount,
    Set<int> alreadyRead = const <int>{},
    int batchSize = size,
  }) {
    if (pageCount <= 0 || batchSize <= 0) return const <int>[];
    return <int>[
      for (int page = 1; page <= pageCount; page++)
        if (!alreadyRead.contains(page)) page,
    ].take(batchSize).toList();
  }

  /// How many pages of the document have not been read.
  static int remaining({
    required int pageCount,
    Set<int> alreadyRead = const <int>{},
  }) {
    if (pageCount <= 0) return 0;
    int unread = 0;
    for (int page = 1; page <= pageCount; page++) {
      if (!alreadyRead.contains(page)) unread++;
    }
    return unread;
  }

  /// "Pages 7–12 of 18", and the shapes either side of it.
  ///
  /// Said before the read as what will be charged for and after it as what was
  /// actually looked at. Both matter: a page that failed to render must not
  /// end up inside the sentence claiming it was read.
  static String describe(Iterable<int> pages, {required int pageCount}) {
    final List<int> sorted = pages.toList()..sort();
    if (sorted.isEmpty) return 'No pages of $pageCount';

    final String subject = sorted.length == 1
        ? 'Page ${sorted.single}'
        : 'Pages ${_list(sorted)}';
    return '$subject of $pageCount';
  }

  /// The page numbers themselves, as a run where they are one and a list
  /// where they are not.
  ///
  /// A failed page in the middle of a batch is exactly how a list arises, and
  /// printing "7–12" over a batch that skipped page 9 would be the silence
  /// this is here to end.
  static String _list(List<int> pages) {
    final bool contiguous = pages.last - pages.first == pages.length - 1;
    if (contiguous) return '${pages.first}–${pages.last}';

    final List<String> numbers = <String>[
      for (final int page in pages) '$page',
    ];
    final String last = numbers.removeLast();
    return '${numbers.join(', ')} and $last';
  }
}
