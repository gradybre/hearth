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

/// A food offered by some source, with how much that source trusts it.
///
/// Domain-side stand-in for a nutrition-source result, so the matching logic
/// stays pure Dart and testable without a network or an adapter in sight.
@immutable
class MatchCandidate {
  const MatchCandidate({required this.food, required this.confidence});

  final Food food;

  /// 0..1, as the source reported it.
  final double confidence;
}

/// A best guess at which candidate an ingredient line meant.
@immutable
class CandidateGuess {
  const CandidateGuess({
    required this.food,
    required this.score,
    required this.isAmbiguous,
  });

  final Food food;

  /// 0..1. How well the name actually matched, before confidence is folded in.
  final double score;

  /// True when the runner-up was nearly as good.
  ///
  /// Spec §5.3 asks for genuinely ambiguous matches to be flagged rather than
  /// quietly resolved. "Cheddar cheese" against four supermarket cheddars has
  /// no right answer the app can know — but it does know that it doesn't know,
  /// and saying so is what keeps a wrong macro from being silently adopted.
  final bool isAmbiguous;

  /// Good enough to apply without asking.
  ///
  /// Being the only candidate is not the same as being right. "1 red bell
  /// pepper" once matched "RED BELL PEPPER VEGGIE CHIPS" and was applied by
  /// default, because with nothing else close there was nothing to be
  /// ambiguous against — and a mediocre match nobody was asked about is
  /// exactly the silent wrong macro the review screen exists to prevent.
  ///
  /// Everything else is still offered; it just arrives unticked.
  bool get isConfident => !isAmbiguous && score >= CandidateMatcher.confident;
}

/// Picking a food for an ingredient from what the outside world offered.
///
/// Separate from [IngredientMatcher.suggest] on purpose. That resolves against
/// the household's own library, where a hit is something the user has already
/// vouched for. This ranks strangers' data, so nothing it produces is ever
/// applied without being seen (spec §5.3).
abstract final class CandidateMatcher {
  /// How close the runner-up may be before the winner is called ambiguous.
  static const double _ambiguityMargin = 0.08;

  /// The score above which a match is applied without asking.
  ///
  /// Sits above what a name buried in extra words can reach, and below an
  /// exact name from a source that trusts itself.
  static const double confident = 0.85;

  /// Words shorter than this are not required to appear.
  ///
  /// They are articles and prepositions — "of", "la", "in" — that carry no
  /// meaning a food name is obliged to repeat. Note that this is *not* a
  /// stemmer: "bay leaf" will not find "Bay leaves", and that gap is left to
  /// the user's one tap rather than papered over with guesswork that would
  /// also match "leafy greens".
  static const int _minimumTokenLength = 3;

  /// The best candidate for [ingredientName], or null when none is close
  /// enough to be worth offering.
  ///
  /// [candidates] arrive in source-priority order and that order breaks exact
  /// ties, so the household's own sources keep precedence over a stranger's.
  static CandidateGuess? best({
    required String ingredientName,
    required List<MatchCandidate> candidates,
  }) {
    final List<String> wanted = _tokens(ingredientName);
    if (wanted.isEmpty || candidates.isEmpty) return null;

    double bestScore = 0;
    double runnerUpScore = 0;
    Food? winner;
    Food? runnerUp;

    for (final MatchCandidate candidate in candidates) {
      final double score = _score(wanted, candidate);
      if (score > bestScore) {
        runnerUpScore = bestScore;
        runnerUp = winner;
        bestScore = score;
        winner = candidate.food;
      } else if (score > runnerUpScore) {
        runnerUpScore = score;
        runnerUp = candidate.food;
      }
    }

    // Below half the words matched it is a coin flip wearing a suggestion's
    // clothes, and a wrong macro is worse than a missing one.
    if (winner == null || bestScore < 0.5) return null;

    final bool tooClose = bestScore - runnerUpScore < _ambiguityMargin;

    return CandidateGuess(
      food: winner,
      score: bestScore,
      // A tie only matters if it changes the answer. Every supermarket's
      // cheddar is 393 kcal per 100 g, so which one is picked costs the user
      // nothing — and flagging every near-tie made the flag mean nothing,
      // which is the same as not having one.
      isAmbiguous: tooClose && !_macrosAgree(winner, runnerUp),
    );
  }

  /// How far two foods' energy may differ before the choice between them
  /// matters.
  static const double _macroTolerance = 0.1;

  /// Whether two candidates would give materially the same numbers.
  ///
  /// Compared per canonical unit so a food described per 100 g and one
  /// described per ounce are still comparable. Anything that cannot be
  /// compared — no servings, no energy — counts as disagreement: nothing to
  /// compare is nothing to be reassured by.
  static bool _macrosAgree(Food a, Food? b) {
    if (b == null) return false;

    final double? left = _kcalPerCanonicalUnit(a);
    final double? right = _kcalPerCanonicalUnit(b);
    if (left == null || right == null) return false;

    final double larger = left > right ? left : right;
    if (larger == 0) return false;

    return (left - right).abs() / larger <= _macroTolerance;
  }

  static double? _kcalPerCanonicalUnit(Food food) {
    final ServingOption? serving = food.defaultServing;
    if (serving == null) return null;

    final double amount = serving.amount.canonicalAmount;
    if (amount == 0) return null;

    final double kcal = serving.macros.kcal;
    return kcal == 0 ? null : kcal / amount;
  }

  static double _score(List<String> wanted, MatchCandidate candidate) {
    final String name = normaliseKey(candidate.food.name);
    if (name.isEmpty) return 0;

    final String haystack = normaliseKey(
      '${candidate.food.name} ${candidate.food.brand ?? ''}',
    );

    final int hits = wanted.where(haystack.contains).length;
    if (hits == 0) return 0;

    // Every word has to land somewhere. A partial hit is how "cheese" ends up
    // matched to "cheese and onion crisps".
    final double coverage = hits / wanted.length;
    if (coverage < 1) return coverage * 0.5;

    // All words present. Now prefer the plainest candidate: an ingredient line
    // says "cheddar cheese", and the food closest to just those words is a
    // better answer than one that buries them in a product name.
    final int extra = (name.split(' ').length - wanted.length).clamp(0, 20);
    final double plainness = 1 / (1 + extra * 0.25);

    // An exact name is the one case worth calling certain.
    final double exactness = name == wanted.join(' ') ? 1 : plainness;

    return 0.6 + 0.4 * exactness * candidate.confidence.clamp(0, 1);
  }

  static List<String> _tokens(String value) => <String>[
    for (final String word in normaliseKey(value).split(' '))
      if (word.length >= _minimumTokenLength) word,
  ];
}
