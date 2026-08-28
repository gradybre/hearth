import 'package:meta/meta.dart';

import '../models/food.dart';
import '../text/text_normaliser.dart';

/// Where a suggested food came from, so the UI can say why (spec §5.3).
enum MatchOrigin {
  /// A correction this household made before. Trusted outright — the whole
  /// point of remembering is that the same fix is never made twice.
  remembered,

  /// A food already attached to another line with the same name, in this
  /// recipe or a recent one.
  previouslyUsed,

  /// A plain name match against the library. The weakest signal, and the one
  /// worth showing as a guess rather than applying silently.
  bestGuess,
}

/// A suggested food for an ingredient line.
@immutable
class MatchSuggestion {
  const MatchSuggestion({required this.foodId, required this.origin});

  final String foodId;
  final MatchOrigin origin;

  /// Remembered corrections are applied without asking; anything weaker is a
  /// suggestion the user confirms.
  bool get isTrusted => origin == MatchOrigin.remembered;

  @override
  bool operator ==(Object other) =>
      other is MatchSuggestion &&
      other.foodId == foodId &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(foodId, origin);

  @override
  String toString() => 'MatchSuggestion($foodId, ${origin.name})';
}

/// Resolves an ingredient string to a food, in the order spec §5.3 lays out:
/// remembered matches, then previously-used foods, then a best guess.
///
/// The order matters because the signals differ in strength. A remembered
/// match is a decision the household already made and is applied silently; a
/// best guess is the parser's opinion and is offered, not assumed. Getting
/// this backwards would quietly attach the wrong food to an ingredient, and a
/// wrong macro is worse than a missing one.
///
/// The automatic match across Open Food Facts and USDA is Phase 3; this
/// resolves against the household's own library.
abstract final class IngredientMatcher {
  /// Suggests a food for [ingredientName], or null when nothing is close
  /// enough to be worth offering.
  ///
  /// [remembered] and [previouslyUsed] are keyed by normalised ingredient
  /// string. [library] is searched only as a last resort, and only when the
  /// answer is unambiguous — offering one of five plausible foods would just
  /// be a coin flip wearing a suggestion's clothes.
  static MatchSuggestion? suggest({
    required String ingredientName,
    required List<Food> library,
    Map<String, String> remembered = const <String, String>{},
    Map<String, String> previouslyUsed = const <String, String>{},
  }) {
    final String key = normaliseKey(ingredientName);
    if (key.isEmpty) return null;

    final Set<String> known = library
        .where((Food f) => !f.isDeleted)
        .map((Food f) => f.id)
        .toSet();

    final String? rememberedId = remembered[key];
    if (rememberedId != null && known.contains(rememberedId)) {
      return MatchSuggestion(
        foodId: rememberedId,
        origin: MatchOrigin.remembered,
      );
    }

    final String? usedId = previouslyUsed[key];
    if (usedId != null && known.contains(usedId)) {
      return MatchSuggestion(
        foodId: usedId,
        origin: MatchOrigin.previouslyUsed,
      );
    }

    return _bestGuess(key, library);
  }

  /// An exact normalised name match, or a single unambiguous partial one.
  static MatchSuggestion? _bestGuess(String key, List<Food> library) {
    final List<Food> live = library
        .where((Food f) => !f.isDeleted)
        .toList(growable: false);

    final List<Food> exact = live
        .where((Food f) => normaliseKey(f.name) == key)
        .toList(growable: false);
    if (exact.length == 1) {
      return MatchSuggestion(
        foodId: exact.single.id,
        origin: MatchOrigin.bestGuess,
      );
    }
    // Two foods with the same name is exactly the case the duplicate warning
    // exists for; picking one here would be arbitrary.
    if (exact.length > 1) return null;

    final List<Food> partial = live
        .where(
          (Food f) =>
              normaliseKey(f.name).contains(key) ||
              key.contains(normaliseKey(f.name)),
        )
        .toList(growable: false);
    if (partial.length == 1) {
      return MatchSuggestion(
        foodId: partial.single.id,
        origin: MatchOrigin.bestGuess,
      );
    }

    return null;
  }

  /// Builds a previously-used lookup from ingredients that already carry a
  /// food, so a name matched once in a recipe resolves on its other lines.
  static Map<String, String> previouslyUsedFrom(
    Iterable<(String name, String? foodId)> ingredients,
  ) {
    final Map<String, String> used = <String, String>{};
    for (final (String name, String? foodId) in ingredients) {
      if (foodId == null) continue;
      final String key = normaliseKey(name);
      if (key.isEmpty) continue;
      used.putIfAbsent(key, () => foodId);
    }
    return used;
  }
}
