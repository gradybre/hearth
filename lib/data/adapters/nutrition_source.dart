import 'package:meta/meta.dart';

import '../../domain/models/food.dart';

/// A candidate match for a food lookup, with enough context for the review
/// screen to show a source badge and a confidence flag (spec §5.3).
@immutable
class NutritionMatch {
  const NutritionMatch({
    required this.food,
    required this.source,
    required this.confidence,
    this.fromLibrary = false,
    this.isGeneric = false,
  });

  final Food food;

  /// Where the numbers originally came from — provenance, not who answered.
  ///
  /// A food saved from Open Food Facts keeps that source for the rest of its
  /// life, so this cannot be read as "the household does not have it yet".
  /// [fromLibrary] is the field that answers that question.
  final FoodSource source;

  /// True when this came out of the household's own library.
  ///
  /// The difference is what separates "here is a food, save it" from "you
  /// already have this" — offering to save the second produces a duplicate of
  /// a food the user may already have corrected.
  final bool fromLibrary;

  /// True when this is a plain ingredient rather than a packaged product.
  ///
  /// USDA keeps its curated whole foods — Foundation, SR Legacy, and the
  /// survey set — apart from the million-odd branded labels, and the
  /// difference is exactly the one a recipe cares about: an ingredient list
  /// asks for cheddar cheese, not for a particular shop's packet of it. Only
  /// a tiebreak, so a search that names a brand still gets that brand.
  final bool isGeneric;

  /// 0..1. Anything the adapter is unsure of is flagged for review rather than
  /// silently accepted — a wrong match corrupts macros invisibly.
  final double confidence;

  bool get isLowConfidence => confidence < 0.7;
}

/// A source of nutrition data, behind an interface (CLAUDE.md rule 7).
///
/// The lookup chain is personal/household library → Open Food Facts → USDA →
/// manual entry (spec §5.5). Each link is one of these, so a source can be
/// added, reordered, or swapped — Nutritionix is named as a possible phase-2
/// addition — without any UI change.
///
/// No implementations exist yet: barcode and external lookup are Phase 2. The
/// interface lands now so nothing above it is written against a concrete
/// client.
abstract interface class NutritionSource {
  /// A short name for the source badge shown beside a match.
  String get displayName;

  /// Looks a food up by barcode. Null when this source has never heard of it,
  /// which is a normal outcome that hands off to the next link in the chain.
  Future<NutritionMatch?> byBarcode(String barcode);

  /// Free-text search, best matches first.
  Future<List<NutritionMatch>> search(String query, {int limit = 20});
}
