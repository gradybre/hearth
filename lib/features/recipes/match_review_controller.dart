import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/models/food.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/recipes/ingredient_matcher.dart';
import '../../domain/text/text_normaliser.dart';

/// One ingredient line and what the search made of it (spec §5.3).
@immutable
class IngredientMatchRow {
  const IngredientMatchRow({
    required this.ingredient,
    required this.guess,
    this.estimate,
    this.accepted = true,
  });

  final ParsedIngredient ingredient;

  /// Null when nothing came close enough to be worth offering.
  final CandidateGuess? guess;

  /// The model's own number for this line, offered only when the real chain
  /// found nothing (spec §5.4). Never used while [guess] is set: real data
  /// outranks a guess, always.
  final AiEstimate? estimate;

  /// True when the only thing on offer here is the model's own arithmetic.
  bool get isEstimateOnly => guess == null && estimate != null;

  /// Whether this suggestion will be applied. Ambiguous ones start unticked,
  /// so the user opts *in* to a guess the app has already said it is unsure
  /// of rather than having to notice and opt out.
  final bool accepted;

  bool get hasGuess => guess != null;
  bool get isAmbiguous => guess?.isAmbiguous ?? false;

  Food? get food => guess?.food;

  IngredientMatchRow copyWith({bool? accepted, CandidateGuess? guess}) =>
      IngredientMatchRow(
        ingredient: ingredient,
        guess: guess ?? this.guess,
        estimate: estimate,
        accepted: accepted ?? this.accepted,
      );
}

@immutable
sealed class MatchReviewState {
  const MatchReviewState();
}

class MatchReviewIdle extends MatchReviewState {
  const MatchReviewIdle();
}

class MatchReviewSearching extends MatchReviewState {
  const MatchReviewSearching(this.done, this.total);
  final int done;
  final int total;
}

class MatchReviewReady extends MatchReviewState {
  const MatchReviewReady(this.rows);
  final List<IngredientMatchRow> rows;

  Iterable<IngredientMatchRow> get accepted => rows.where(
    (IngredientMatchRow r) => r.accepted && (r.hasGuess || r.estimate != null),
  );

  int get foundCount => rows
      .where((IngredientMatchRow r) => r.hasGuess || r.estimate != null)
      .length;
}

/// Finds nutrition for a recipe's unmatched ingredients (spec §5.3).
///
/// The search runs against the whole chain, so the household's own library is
/// still asked first and still wins. What comes back is *offered*, never
/// applied: these are strangers' numbers, and §5.3 is explicit that the match
/// review screen is where the user sees the source, the serving and the
/// confidence before any of it counts toward a recipe.
class MatchReviewController extends Notifier<MatchReviewState> {
  @override
  MatchReviewState build() => const MatchReviewIdle();

  /// Guards against a second run landing on top of the first.
  int _run = 0;

  Future<void> findMatches(
    List<ParsedIngredient> ingredients, {
    List<AiEstimate> estimates = const <AiEstimate>[],
  }) async {
    final int run = ++_run;
    final List<ParsedIngredient> wanted = <ParsedIngredient>[
      // An optional line is a deliberate exclusion, not a gap (§5.2), so
      // there is nothing to look up and nothing to review.
      for (final ParsedIngredient ingredient in ingredients)
        if (!ingredient.isOptional && ingredient.name.trim().isNotEmpty)
          ingredient,
    ];

    if (wanted.isEmpty) {
      state = const MatchReviewReady(<IngredientMatchRow>[]);
      return;
    }

    state = MatchReviewSearching(0, wanted.length);
    final List<IngredientMatchRow> rows = <IngredientMatchRow>[];

    // One at a time rather than all at once: a dozen ingredients firing
    // together is a dozen simultaneous calls to services that are free to
    // rate-limit us, and the progress count is honest this way.
    for (int i = 0; i < wanted.length; i++) {
      final ParsedIngredient ingredient = wanted[i];
      final List<NutritionMatch> found = await ref
          .read(nutritionLookupProvider)
          .search(ingredient.name, limit: 8);

      if (_run != run) return;

      final CandidateGuess? guess = CandidateMatcher.best(
        ingredientName: ingredient.name,
        candidates: <MatchCandidate>[
          for (final NutritionMatch match in found)
            MatchCandidate(food: match.food, confidence: match.confidence),
        ],
      );

      // The model's number only where the real chain found nothing: §5.4 is
      // explicit that generated recipes are not trusted on estimated macros.
      final AiEstimate? estimate = guess != null
          ? null
          : _estimateFor(ingredient, estimates);

      rows.add(
        IngredientMatchRow(
          ingredient: ingredient,
          guess: guess,
          estimate: estimate,
          // Only what is clearly right is applied without asking. An
          // ambiguous match, a mediocre lone candidate, and an estimate are
          // all offered unticked — opted into rather than out of.
          accepted: guess?.isConfident ?? false,
        ),
      );
      state = MatchReviewSearching(i + 1, wanted.length);
    }

    if (_run != run) return;
    state = MatchReviewReady(rows);
  }

  void setAccepted(int index, {required bool accepted}) {
    final MatchReviewState current = state;
    if (current is! MatchReviewReady) return;

    state = MatchReviewReady(<IngredientMatchRow>[
      for (int i = 0; i < current.rows.length; i++)
        if (i == index)
          current.rows[i].copyWith(accepted: accepted)
        else
          current.rows[i],
    ]);
  }

  /// The estimate whose line this ingredient came from.
  ///
  /// Matched on the ingredient's own words rather than by position: the
  /// parser drops blank lines and optional items, so the indexes on the two
  /// sides do not line up.
  static AiEstimate? _estimateFor(
    ParsedIngredient ingredient,
    List<AiEstimate> estimates,
  ) {
    final String raw = normaliseKey(ingredient.raw);
    final String name = normaliseKey(ingredient.name);
    if (raw.isEmpty && name.isEmpty) return null;

    for (final AiEstimate estimate in estimates) {
      final String line = normaliseKey(estimate.ingredient);
      if (line.isEmpty) continue;
      if (line == raw || (name.isNotEmpty && line.contains(name))) {
        return estimate;
      }
    }
    return null;
  }

  void reset() {
    _run++;
    state = const MatchReviewIdle();
  }
}

final NotifierProvider<MatchReviewController, MatchReviewState>
matchReviewProvider = NotifierProvider<MatchReviewController, MatchReviewState>(
  MatchReviewController.new,
);
