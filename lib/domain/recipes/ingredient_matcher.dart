import 'package:meta/meta.dart';

import '../foods/food_concept.dart';
import '../models/food.dart';
import '../text/text_normaliser.dart';

/// Where a suggested food came from, so the UI can say why (spec §5.3).
enum MatchOrigin {
  /// A food the household marked as one of the things it actually buys, whose
  /// name says the same thing the line does. Trusted outright, and ranked
  /// above a remembered match: marking a default is a deliberate act, while a
  /// remembered match is recorded automatically every time anybody picks
  /// anything. When the two disagree the deliberate one is the newer, broader
  /// statement of what this household eats.
  defaultFood,

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

  /// Defaults and remembered corrections are applied without asking; anything
  /// weaker is a suggestion the user confirms.
  bool get isTrusted =>
      origin == MatchOrigin.defaultFood || origin == MatchOrigin.remembered;

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

    // Everything the *household* could be cooking with. A restaurant's own
    // menu is in the same library and is not one of them — see [matchable].
    final List<Food> candidates = matchable(library);

    // `known` is still the whole live library on purpose: it only checks that
    // a remembered or previously-used id still exists, and a person who
    // deliberately attached Chipotle's guacamole to a line has said what they
    // meant. The exclusion is of automatic matching, not of choice.
    final Set<String> known = library
        .where((Food f) => !f.isDeleted)
        .map((Food f) => f.id)
        .toSet();

    // Only when the household has said exactly one thing. Several defaults
    // answering the same line is not a tie to break — a recipe asking for
    // "milk" against a fridge holding whole, 2% and non-fat has genuinely not
    // said which, and picking one would be a coin flip wearing a suggestion's
    // clothes. The caller offers the menu instead (see [defaultsFor]).
    final List<Food> defaults = defaultsFor(ingredientName, candidates);
    if (defaults.length == 1) {
      return MatchSuggestion(
        foodId: defaults.single.id,
        origin: MatchOrigin.defaultFood,
      );
    }

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

    return _bestGuess(key, candidates);
  }

  /// Every default food whose name says what [ingredientName] asks for,
  /// closest fit first (spec §5.3).
  ///
  /// Empty is the ordinary answer — most lines have no default. One is a
  /// match. More than one is the ambiguity worth showing: those are the
  /// options to offer, and they are already the household's own foods, so the
  /// menu is short and every item on it is one they chose.
  static List<Food> defaultsFor(String ingredientName, List<Food> library) {
    final FoodConcept line = FoodConcept.of(ingredientName);
    if (line.isEmpty) return const <Food>[];

    final List<(Food, int)> matched = <(Food, int)>[
      for (final Food food in matchable(library))
        if (food.isDefault && !food.isDeleted)
          if (FoodConcept.of('${food.name} ${food.brand ?? ''}')
              case final FoodConcept c when c.covers(line))
            (food, c.distanceFrom(line)),
    ]..sort(((Food, int) a, (Food, int) b) => a.$2.compareTo(b.$2));

    return <Food>[for (final (Food, int) entry in matched) entry.$1];
  }

  /// An exact normalised name match, or a single unambiguous partial one.
  /// The foods an ingredient line may be matched to **automatically**.
  ///
  /// Everything live, less anything read off a restaurant's menu (spec §5.2).
  /// Chipotle's sheet contributes a Chicken, a Cheese, a Sour Cream and a
  /// Romaine Lettuce to the household library, and none of them is a thing
  /// you cook with. Renaming them "Chipotle Chicken" would not help:
  /// [FoodConcept.canAnswer] is asymmetric on purpose, so a line reading
  /// "chicken" is still answered by a food whose name merely adds a brand.
  ///
  /// The damage is worse than a wrong suggestion. A best guess is only
  /// offered when it is unambiguous, so a second Chicken makes lines that
  /// used to resolve cleanly stop resolving at all — a silent loss of
  /// matching quality across every recipe already in the library.
  ///
  /// Choosing one by hand is untouched, and so is a remembered match. This
  /// excludes them from being picked *for* you, not from being picked.
  static List<Food> matchable(List<Food> library) => <Food>[
    for (final Food food in library)
      if (!food.isDeleted && food.source != FoodSource.restaurant) food,
  ];

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

  /// The food most often matched to each ingredient name, across every
  /// recipe in the library — spec §5.3's "previously-used" tier applied
  /// household-wide rather than within one recipe.
  ///
  /// [previouslyUsedFrom] is first-seen-wins, which is right for its own job
  /// of keeping repeated lines in *one* recipe consistent with each other —
  /// there is no meaningful frequency signal within a single recipe. Here
  /// there is: a food matched to "ground beef" in nine recipes out of ten is
  /// a real household habit, and picking whichever recipe happened to load
  /// first would throw that signal away.
  static Map<String, String> mostUsedByName(
    Iterable<(String name, String? foodId)> ingredients,
  ) {
    final Map<String, Map<String, int>> countsByName =
        <String, Map<String, int>>{};

    for (final (String name, String? foodId) in ingredients) {
      if (foodId == null) continue;
      final String key = normaliseKey(name);
      if (key.isEmpty) continue;

      final Map<String, int> counts = countsByName.putIfAbsent(
        key,
        () => <String, int>{},
      );
      counts[foodId] = (counts[foodId] ?? 0) + 1;
    }

    final Map<String, String> mostUsed = <String, String>{};
    countsByName.forEach((String key, Map<String, int> counts) {
      String bestId = counts.keys.first;
      int bestCount = counts[bestId]!;
      counts.forEach((String foodId, int count) {
        if (count > bestCount) {
          bestId = foodId;
          bestCount = count;
        }
      });
      mostUsed[key] = bestId;
    });
    return mostUsed;
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
