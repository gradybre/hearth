import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/recipes/ingredient_matcher.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  final Food oliveOil = aFoodPer100g('Olive oil', kcal: 884, id: 'food-oil');
  final Food chicken = aFoodPer100g(
    'Chicken breast',
    kcal: 165,
    id: 'food-chicken',
  );
  final List<Food> library = <Food>[oliveOil, chicken];

  group('resolution order (spec §5.3)', () {
    test('a remembered match wins over everything else', () {
      // "evoo" would never guess its way to olive oil; being remembered is
      // the whole point.
      final MatchSuggestion? match = IngredientMatcher.suggest(
        ingredientName: 'evoo',
        library: library,
        remembered: <String, String>{'evoo': 'food-oil'},
        previouslyUsed: <String, String>{'evoo': 'food-chicken'},
      );

      expect(match!.foodId, 'food-oil');
      expect(match.origin, MatchOrigin.remembered);
      expect(match.isTrusted, isTrue);
    });

    test('previously-used wins over a best guess', () {
      final MatchSuggestion? match = IngredientMatcher.suggest(
        ingredientName: 'olive oil',
        library: library,
        previouslyUsed: <String, String>{'olive oil': 'food-chicken'},
      );

      expect(match!.foodId, 'food-chicken');
      expect(match.origin, MatchOrigin.previouslyUsed);
      expect(match.isTrusted, isFalse);
    });

    test('a best guess is the last resort and is not trusted', () {
      final MatchSuggestion? match = IngredientMatcher.suggest(
        ingredientName: 'Olive Oil',
        library: library,
      );

      expect(match!.foodId, 'food-oil');
      expect(match.origin, MatchOrigin.bestGuess);
      expect(match.isTrusted, isFalse);
    });
  });

  group('stale references', () {
    test('a remembered match to a missing food falls through', () {
      final MatchSuggestion? match = IngredientMatcher.suggest(
        ingredientName: 'olive oil',
        library: library,
        remembered: <String, String>{'olive oil': 'food-that-vanished'},
      );

      // It must not return a dangling id; it drops to the next signal.
      expect(match!.foodId, 'food-oil');
      expect(match.origin, MatchOrigin.bestGuess);
    });

    test('a soft-deleted food is never suggested', () {
      final Food deleted = Food(
        id: 'food-oil',
        name: 'Olive oil',
        servingOptions: oliveOil.servingOptions,
        source: FoodSource.manual,
        isDeleted: true,
      );

      expect(
        IngredientMatcher.suggest(
          ingredientName: 'olive oil',
          library: <Food>[deleted],
          remembered: <String, String>{'olive oil': 'food-oil'},
        ),
        isNull,
      );
    });
  });

  group('guessing stays conservative', () {
    test('two foods with the same name produce no guess', () {
      // This is exactly what the duplicate warning exists for; picking one
      // here would be arbitrary, and a wrong macro is worse than a missing one.
      final List<Food> ambiguous = <Food>[
        aFoodPer100g('Olive oil', kcal: 884, id: 'a'),
        aFoodPer100g('olive oil', kcal: 880, id: 'b'),
      ];

      expect(
        IngredientMatcher.suggest(
          ingredientName: 'olive oil',
          library: ambiguous,
        ),
        isNull,
      );
    });

    test('several plausible partial matches produce no guess', () {
      final List<Food> oils = <Food>[
        aFoodPer100g('Olive oil, extra virgin', kcal: 884, id: 'a'),
        aFoodPer100g('Olive oil, light', kcal: 884, id: 'b'),
      ];

      expect(
        IngredientMatcher.suggest(ingredientName: 'olive oil', library: oils),
        isNull,
      );
    });

    test('a single partial match is offered', () {
      final MatchSuggestion? match = IngredientMatcher.suggest(
        ingredientName: 'chicken',
        library: library,
      );
      expect(match!.foodId, 'food-chicken');
    });

    test('nothing matching produces nothing', () {
      expect(
        IngredientMatcher.suggest(
          ingredientName: 'fennel fronds',
          library: library,
        ),
        isNull,
      );
      expect(
        IngredientMatcher.suggest(ingredientName: '  ', library: library),
        isNull,
      );
    });
  });

  group('previouslyUsedFrom', () {
    test('collects the foods already attached to named lines', () {
      final Map<String, String> used = IngredientMatcher.previouslyUsedFrom(
        <(String, String?)>[
          ('Olive oil', 'food-oil'),
          ('chicken breast', 'food-chicken'),
          ('salt', null),
        ],
      );

      expect(used['olive oil'], 'food-oil');
      expect(used['chicken breast'], 'food-chicken');
      expect(used.containsKey('salt'), isFalse);
    });

    test('the first attachment wins for a repeated name', () {
      final Map<String, String> used = IngredientMatcher.previouslyUsedFrom(
        <(String, String?)>[('olive oil', 'food-a'), ('olive oil', 'food-b')],
      );
      expect(used['olive oil'], 'food-a');
    });
  });

  group('mostUsedByName', () {
    test('the food matched most often wins, not the first one seen', () {
      // Unlike previouslyUsedFrom, order here should not decide the winner —
      // frequency should, since this is meant to reflect an actual household
      // habit across the whole recipe library.
      final Map<String, String> mostUsed = IngredientMatcher.mostUsedByName(
        <(String, String?)>[
          ('ground beef', 'food-a'),
          ('ground beef', 'food-b'),
          ('ground beef', 'food-b'),
          ('ground beef', 'food-b'),
        ],
      );

      expect(mostUsed['ground beef'], 'food-b');
    });

    test('a tie breaks toward whichever was seen first', () {
      final Map<String, String> mostUsed = IngredientMatcher.mostUsedByName(
        <(String, String?)>[
          ('ground beef', 'food-a'),
          ('ground beef', 'food-b'),
        ],
      );

      expect(mostUsed['ground beef'], 'food-a');
    });

    test('ingredients with no food attached are ignored', () {
      final Map<String, String> mostUsed = IngredientMatcher.mostUsedByName(
        <(String, String?)>[('salt', null), ('  ', 'food-a')],
      );

      expect(mostUsed, isEmpty);
    });

    test('different ingredient names are tallied separately', () {
      final Map<String, String> mostUsed = IngredientMatcher.mostUsedByName(
        <(String, String?)>[
          ('olive oil', 'food-oil'),
          ('chicken breast', 'food-chicken'),
        ],
      );

      expect(mostUsed['olive oil'], 'food-oil');
      expect(mostUsed['chicken breast'], 'food-chicken');
    });
  });
}
