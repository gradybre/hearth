import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Something handed to Hearth from another app's share sheet (spec §5.3).
///
/// Deliberately the same three things the import screen already takes —
/// pictures, a link, some text — because that is what makes this a new *way
/// in* rather than a new feature. What arrives lands in the import screen and
/// goes through the same mandatory review as anything else (CLAUDE.md rule 4).
@immutable
class SharedContent {
  const SharedContent({
    this.images = const <Uint8List>[],
    this.url = '',
    this.text = '',
  });

  /// Screenshots, photos of a page — up to the same ten the photo import
  /// already accepts, because a recipe spans as many screens as it spans.
  final List<Uint8List> images;

  /// A link, if one was shared. Not yet judged — see `SharedLink`.
  final String url;

  /// Plain text, which for a recipe DM is often the whole recipe.
  final String text;

  bool get isEmpty =>
      images.isEmpty && url.trim().isEmpty && text.trim().isEmpty;
}

/// Where shared content comes from, behind an interface (CLAUDE.md rule 7).
///
/// One implementation reads what an iOS share extension left behind; every
/// other platform has none, and the app is written so that "nobody ever
/// shares anything here" is an ordinary state rather than a missing feature.
/// It is also what lets the whole flow above this seam be tested without a
/// share sheet, which is just as well, because a share sheet cannot be.
abstract interface class SharedContentSource {
  /// Everything shared since the app last looked, oldest first.
  ///
  /// A stream rather than a callback because the two cases are genuinely
  /// different — a cold start with something waiting, and a share arriving
  /// while Hearth is already open — and neither should be the special one.
  Stream<SharedContent> get incoming;

  /// Anything that arrived before the app was listening.
  ///
  /// A share extension can run while Hearth is not, so the payload is waiting
  /// on disk before there is anybody to hand it to.
  Future<SharedContent?> pending();
}
