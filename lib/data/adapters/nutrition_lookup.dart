import '../../domain/models/food.dart';
import 'nutrition_source.dart';

/// The lookup chain: library → Open Food Facts → USDA → manual (spec §5.5).
///
/// Order is the whole design. The household's own library is asked first
/// because it works offline and because a food this household has already
/// corrected must outrank a stranger's version of it. External sources follow
/// in the order the spec sets, and a miss everywhere is not an error — it is
/// the manual-entry path, which is a first-class outcome rather than a
/// failure.
class NutritionLookup {
  NutritionLookup(this.sources);

  /// In priority order. The first source with an answer wins for a barcode;
  /// search gathers from all of them.
  final List<NutritionSource> sources;

  /// The first match for a barcode, or null when nobody has heard of it.
  ///
  /// Stops at the first hit rather than polling everything: the library
  /// answering means the answer is already the household's own, and asking
  /// the internet afterwards could only produce a worse one.
  Future<NutritionMatch?> byBarcode(String barcode) async {
    for (final NutritionSource source in sources) {
      final NutritionMatch? match = await source.byBarcode(barcode);
      if (match != null) return match;
    }
    return null;
  }

  /// Search results from every source, the household's own first.
  ///
  /// Duplicates are collapsed by barcode: the same product from two sources is
  /// one thing to the person looking at it, and the earlier source — the more
  /// trusted one — is the one kept.
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    final List<NutritionMatch> found = <NutritionMatch>[];
    final Set<String> seenBarcodes = <String>{};

    for (final NutritionSource source in sources) {
      if (found.length >= limit) break;
      for (final NutritionMatch match in await source.search(
        query,
        limit: limit,
      )) {
        final String? barcode = match.food.barcode;
        if (barcode != null && !seenBarcodes.add(barcode)) continue;
        found.add(match);
        if (found.length >= limit) break;
      }
    }

    return found;
  }
}

/// What a barcode scan turned up, and where from.
///
/// A miss is modelled as a value rather than a null so the screen can say
/// "nobody has heard of this — add it yourself" with the barcode in hand,
/// which is the path §5.5 asks for.
class BarcodeResult {
  const BarcodeResult.found(this.barcode, NutritionMatch this.match);
  const BarcodeResult.miss(this.barcode) : match = null;

  final String barcode;
  final NutritionMatch? match;

  bool get isMiss => match == null;

  /// True when something was found but is not to be trusted without a look.
  bool get needsReview => match?.isLowConfidence ?? false;

  FoodSource? get source => match?.source;
}
