import 'package:meta/meta.dart';

import '../planning/day_format.dart';

/// Where a restaurant's menu came from, and when (review N08).
///
/// A menu is somebody else's numbers, read once and then trusted for months.
/// What that is worth depends entirely on facts the menu itself does not
/// carry: where it came from, what date was printed on it, how much of it was
/// read, and when. §5.6's "flag, don't guess" is the same instinct one level
/// up — a number you cannot date is a number you cannot weigh.
@immutable
class MenuProvenance {
  const MenuProvenance({
    required this.restaurant,
    required this.itemCount,
    required this.importedAt,
    this.source,
    this.documentDate,
  });

  final String restaurant;

  /// A URL, a file name, or whatever was said about where the numbers came
  /// from. Null when nobody said, which is honest and common.
  final String? source;

  /// The date printed on the document, which is **not** when it was read. A
  /// sheet published in March and pasted in September is nine months old
  /// however fresh the import is, and only this field can say so.
  final DateTime? documentDate;

  final int itemCount;
  final DateTime importedAt;

  /// How old the numbers are, measured from the document where there is one
  /// and from the reading where there is not.
  ///
  /// The document wins deliberately: it is the date the restaurant stands
  /// behind, and reading an old sheet today does not make it new.
  Duration ageAt(DateTime now) => now.difference(documentDate ?? importedAt);

  /// One line, for under a restaurant's name.
  ///
  /// Only what is known. A menu with no source and no document date still has
  /// a count and a date it was read, and saying those two plainly beats
  /// padding the line with "unknown".
  ///
  /// Takes no clock, deliberately. It used to, and never read it — a
  /// parameter that makes every caller reach for `DateTime.now()` while the
  /// answer does not move is a lie about what the line depends on. [ageAt] is
  /// the one that needs a clock, and has one.
  String get describe => <String>[
    '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
    if (source case final String source when source.isNotEmpty) source,
    if (documentDate case final DateTime printed)
      'dated ${printed.day} ${monthName(printed)}'
    else
      'read ${importedAt.day} ${monthName(importedAt)}',
  ].join(' · ');
}
