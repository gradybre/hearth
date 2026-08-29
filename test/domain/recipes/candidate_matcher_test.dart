import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/recipes/ingredient_matcher.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// Ranking a stranger's foods against an ingredient line (spec §5.3).
///
/// Nothing here is applied without being seen, so the bar is not "always be
/// right" — it is "be right often enough to save typing, and admit it when
/// there is no answer to be had".
MatchCandidate candidate(
  String name, {
  String? brand,
  double confidence = 0.9,
  double? kcalPer100g,
}) => MatchCandidate(
  confidence: confidence,
  food: Food(
    id: '$name/${brand ?? ''}',
    name: name,
    brand: brand,
    source: FoodSource.usda,
    servingOptions: kcalPer100g == null
        ? const <ServingOption>[]
        : <ServingOption>[
            ServingOption(
              id: '$name/${brand ?? ''}:100g',
              label: '100 g',
              amount: Quantity.of(100, Units.gram),
              macros: Macros(kcal: kcalPer100g),
            ),
          ],
  ),
);

CandidateGuess? bestFor(String ingredient, List<MatchCandidate> candidates) =>
    CandidateMatcher.best(ingredientName: ingredient, candidates: candidates);

void main() {
  test('an exact name wins outright', () {
    final CandidateGuess? guess = bestFor('cheddar cheese', <MatchCandidate>[
      candidate('Cheddar cheese and bacon crisps'),
      candidate('Cheddar cheese'),
    ]);

    expect(guess!.food.name, 'Cheddar cheese');
  });

  test('the plainest candidate beats the most elaborate', () {
    // The line says "olive oil". A food that is just olive oil answers it; one
    // that merely contains the words does not.
    final CandidateGuess? guess = bestFor('olive oil', <MatchCandidate>[
      candidate('Sun dried tomato and olive oil tapenade'),
      candidate('Extra virgin olive oil'),
    ]);

    expect(guess!.food.name, 'Extra virgin olive oil');
  });

  test('a candidate missing one of the words loses to one with all', () {
    final CandidateGuess? guess = bestFor('greek yogurt', <MatchCandidate>[
      candidate('Yogurt', confidence: 1),
      candidate('Greek yogurt, plain'),
    ]);

    expect(guess!.food.name, 'Greek yogurt, plain');
  });

  test('nothing close enough is no answer at all', () {
    // A wrong macro is worse than a missing one, and this is the case where
    // guessing costs more than it saves.
    expect(
      bestFor('smoked paprika', <MatchCandidate>[
        candidate('Tomato ketchup'),
        candidate('Digestive biscuits'),
      ]),
      isNull,
    );
  });

  test('a tie that changes the macros is flagged', () {
    // Spec §5.3: genuinely ambiguous matches are flagged for review. The app
    // cannot know whether the line meant the cream or the milk — and the
    // answer is 200 kcal either way it guesses.
    final CandidateGuess? guess = bestFor('coconut milk', <MatchCandidate>[
      candidate('Coconut milk', brand: 'A', kcalPer100g: 230),
      candidate('Coconut milk', brand: 'B', kcalPer100g: 20),
    ]);

    expect(guess, isNotNull);
    expect(guess!.isAmbiguous, isTrue);
  });

  test('a tie that changes nothing is not worth stopping for', () {
    // Every supermarket's cheddar is 393 kcal per 100 g. Which one the app
    // picks does not change a single number the user sees, and flagging it
    // spends their attention on a decision that has no wrong answer.
    //
    // Ambiguity is about consequences. Flagging every near-tie made the flag
    // mean nothing, which is the same as not having one.
    final CandidateGuess? guess = bestFor('cheddar cheese', <MatchCandidate>[
      candidate('CHEDDAR CHEESE', brand: 'Weis Markets', kcalPer100g: 393),
      candidate('CHEDDAR CHEESE', brand: 'Grafton Village', kcalPer100g: 393),
      candidate('CHEDDAR CHEESE', brand: 'Waldbaum', kcalPer100g: 400),
    ]);

    expect(guess, isNotNull);
    expect(guess!.isAmbiguous, isFalse);
  });

  test('a tie between candidates with no macros to compare is flagged', () {
    // Nothing to compare means nothing to be reassured by.
    final CandidateGuess? guess = bestFor('cheddar cheese', <MatchCandidate>[
      candidate('CHEDDAR CHEESE', brand: 'Weis Markets'),
      candidate('CHEDDAR CHEESE', brand: 'Grafton Village'),
    ]);

    expect(guess!.isAmbiguous, isTrue);
  });

  test('a clear winner is not flagged as ambiguous', () {
    final CandidateGuess? guess = bestFor('olive oil', <MatchCandidate>[
      candidate('Olive oil'),
      candidate('Olive oil and rosemary focaccia crackers'),
    ]);

    expect(guess!.isAmbiguous, isFalse);
  });

  test('articles and prepositions are not required to appear', () {
    // "la" carries no meaning a food name is obliged to repeat; requiring it
    // would halve the coverage and throw a good answer away.
    expect(
      bestFor('la tortilla', <MatchCandidate>[candidate('Tortilla wraps')]),
      isNotNull,
    );
  });

  test('it is not a stemmer, and does not pretend to be', () {
    // "bay leaf" does not find "Bay leaves". Left deliberately to the user's
    // one tap: the loosening that would catch it also matches "leafy greens",
    // and a wrong macro is worse than a missing one.
    expect(
      bestFor('bay leaf', <MatchCandidate>[candidate('Bay leaves')]),
      isNull,
    );
  });

  test('a brand match counts toward coverage', () {
    final CandidateGuess? guess = bestFor(
      'cathedral city cheddar',
      <MatchCandidate>[candidate('Mature cheddar', brand: 'Cathedral City')],
    );

    expect(guess, isNotNull);
  });

  test('the source order breaks an exact tie', () {
    // Candidates arrive library-first, so a household's own food keeps
    // precedence over a stranger's identical one.
    final CandidateGuess? guess = bestFor('olive oil', <MatchCandidate>[
      candidate('Olive oil', brand: 'ours'),
      candidate('Olive oil', brand: 'theirs'),
    ]);

    expect(guess!.food.brand, 'ours');
  });

  test('an empty ingredient asks nothing', () {
    expect(bestFor('', <MatchCandidate>[candidate('Olive oil')]), isNull);
    expect(bestFor('olive oil', <MatchCandidate>[]), isNull);
  });
}
