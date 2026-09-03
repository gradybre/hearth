import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/ingredient_matcher.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  defaultFoodTests();

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

/// Defaults: the household's standing choices (spec §5.3).
void defaultFoodTests() {
  Food beef({String name = 'Maverick Ranch 96/4 Ground Beef'}) =>
      aFood(name, id: 'food-beef').asDefault();

  group('a default answers a line that names the same thing', () {
    test('applied without asking, because it was chosen deliberately', () {
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'lean ground beef',
        library: <Food>[beef()],
      );

      expect(suggestion!.foodId, 'food-beef');
      expect(suggestion.origin, MatchOrigin.defaultFood);
      expect(suggestion.isTrusted, isTrue);
    });

    test('a food that is not marked default does not get the tier', () {
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'lean ground beef',
        library: <Food>[aFood('Maverick Ranch 96/4 Ground Beef', id: 'f1')],
      );

      expect(suggestion?.origin, isNot(MatchOrigin.defaultFood));
    });

    test('a deleted default is not offered', () {
      expect(
        IngredientMatcher.defaultsFor('ground beef', <Food>[
          beef().withDeleted(),
        ]),
        isEmpty,
      );
    });

    test('a grade the line contradicts is not a default for it', () {
      expect(
        IngredientMatcher.defaultsFor('88% ground beef', <Food>[beef()]),
        isEmpty,
      );
    });
  });

  group('a default outranks a remembered match', () {
    test('on a line neither has claimed yet', () {
      // Marking a default is a deliberate act. A remembered match is recorded
      // automatically every time anybody picks anything, so when the two
      // disagree the deliberate one is the newer, broader statement.
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'ground beef',
        library: <Food>[
          beef(),
          aFood('Old beef', id: 'food-old'),
        ],
        remembered: <String, String>{'ground beef': 'food-old'},
      );

      expect(suggestion!.foodId, 'food-beef');
      expect(suggestion.origin, MatchOrigin.defaultFood);
    });

    test('but a remembered match still wins where no default answers', () {
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'oyster sauce',
        library: <Food>[
          beef(),
          aFood('Oyster sauce', id: 'food-oyster'),
        ],
        remembered: <String, String>{'oyster sauce': 'food-oyster'},
      );

      expect(suggestion!.origin, MatchOrigin.remembered);
    });
  });

  group('several defaults answering one line is a menu, not a tie', () {
    List<Food> milks() => <Food>[
      aFood('Whole milk', id: 'milk-whole').asDefault(),
      aFood('2% milk', id: 'milk-2').asDefault(),
      aFood('Non-fat milk', id: 'milk-0').asDefault(),
    ];

    test('nothing is applied, because the line has not said which', () {
      // Brendan's own case: a recipe asking for "milk" against a fridge
      // holding three has genuinely not said which one.
      expect(
        IngredientMatcher.suggest(
          ingredientName: 'milk',
          library: milks(),
        )?.origin,
        isNot(MatchOrigin.defaultFood),
      );
    });

    test('all of them are offered, so the caller can show the choice', () {
      expect(
        IngredientMatcher.defaultsFor('milk', milks()).map((Food f) => f.id),
        <String>{'milk-whole', 'milk-2', 'milk-0'},
      );
    });

    test('a line that does say which resolves to one of them', () {
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: '1 cup whole milk',
        library: milks(),
      );

      expect(suggestion!.foodId, 'milk-whole');
      expect(suggestion.origin, MatchOrigin.defaultFood);
    });

    test('and skim resolves to the non-fat one, however it is spelled', () {
      expect(
        IngredientMatcher.suggest(
          ingredientName: 'skim milk',
          library: milks(),
        )!.foodId,
        'milk-0',
      );
    });
  });

  test('a hyphen in the recipe does not hide the default', () {
    // Brendan's report end to end: the food is saved as "Kikkoman's Low
    // Sodium Soy Sauce" and the recipe line reads "low-sodium soy sauce".
    final MatchSuggestion? suggestion = IngredientMatcher.suggest(
      ingredientName: 'low-sodium soy sauce',
      library: <Food>[
        aFood("Kikkoman's Low Sodium Soy Sauce", id: 'food-soy').asDefault(),
      ],
    );

    expect(suggestion!.foodId, 'food-soy');
    expect(suggestion.origin, MatchOrigin.defaultFood);
  });

  test('the closest fit leads the menu', () {
    // Both answer "ground beef"; the one carrying fewer words nobody asked
    // for is the better opening offer.
    final List<Food> found = IngredientMatcher.defaultsFor(
      'ground beef',
      <Food>[beef(), aFood('96/4 ground beef', id: 'food-plain').asDefault()],
    );

    expect(found.first.id, 'food-plain');
    expect(found, hasLength(2));
  });

  group("somebody else's kitchen (spec §5.2)", () {
    Food restaurantChicken() => aFood(
      'Chicken',
      id: 'f-chipotle-chicken',
      brand: 'Chipotle',
      source: FoodSource.restaurant,
    );

    test('a restaurant food is never suggested for a cooking line', () {
      // Chipotle's menu puts a Chicken, a Cheese, a Sour Cream and a Romaine
      // Lettuce in the library. None of them is something you cook with.
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'chicken',
        library: <Food>[restaurantChicken()],
      );

      expect(suggestion, isNull);
    });

    test('and does not make an unambiguous line ambiguous', () {
      // The regression that matters more than the wrong suggestion. The
      // library is only consulted when the answer is unambiguous, so a second
      // Chicken would make a line that used to resolve cleanly stop resolving
      // at all — a silent loss of matching quality across the whole existing
      // library, caused by data that has nothing to do with cooking.
      final Food ownChicken = aFood('Chicken breast', id: 'f-own-chicken');

      final MatchSuggestion? before = IngredientMatcher.suggest(
        ingredientName: 'chicken breast',
        library: <Food>[ownChicken],
      );
      final MatchSuggestion? after = IngredientMatcher.suggest(
        ingredientName: 'chicken breast',
        library: <Food>[ownChicken, restaurantChicken()],
      );

      expect(before?.foodId, 'f-own-chicken');
      expect(after?.foodId, 'f-own-chicken');
    });

    test('nor offered as a default, however it got marked as one', () {
      final Food marked = aFood(
        'Chicken',
        id: 'f-chipotle-chicken',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
        isDefault: true,
      );

      expect(IngredientMatcher.defaultsFor('chicken', <Food>[marked]), isEmpty);
    });

    test('a remembered match wins in the kitchen it came from', () {
      // Somebody who deliberately attached Chipotle's guacamole to a line has
      // said what they meant — but only about a meal from Chipotle. This test
      // used to assert the first half without the second, which was the hole:
      // remembered matches are trusted and keyed on the bare ingredient
      // string, so "guacamole → Chipotle's" would have been applied to a
      // recipe somebody was cooking.
      final Food guac = aFood(
        'Guacamole',
        id: 'f-chipotle-guac',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
      );
      const Map<String, String> remembered = <String, String>{
        'guacamole': 'f-chipotle-guac',
      };

      final MatchSuggestion? eatenOut = IngredientMatcher.suggest(
        ingredientName: 'guacamole',
        library: <Food>[guac],
        remembered: remembered,
        kind: RecipeKind.eatenOut,
      );
      expect(eatenOut?.foodId, 'f-chipotle-guac');
      expect(eatenOut?.origin, MatchOrigin.remembered);

      final MatchSuggestion? cooking = IngredientMatcher.suggest(
        ingredientName: 'guacamole',
        library: <Food>[guac],
        remembered: remembered,
      );
      expect(cooking, isNull);
    });
  });

  group('a meal you ordered matches against the menu (spec §5.2)', () {
    Food chipotleChicken() => aFood(
      'Chicken',
      id: 'f-chipotle-chicken',
      brand: 'Chipotle',
      source: FoodSource.restaurant,
    );
    Food ownChicken() => aFood('Chicken breast', id: 'f-own-chicken');

    test('a component resolves without being asked', () {
      // The whole point of A: typing the six lines of a burrito bowl should
      // be the whole of building one. A tap per line to say "yes, that
      // Chipotle chicken" is a tax paid on a decision already made by saying
      // the meal was eaten out.
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'chicken',
        library: <Food>[chipotleChicken(), ownChicken()],
        kind: RecipeKind.eatenOut,
      );

      expect(suggestion?.foodId, 'f-chipotle-chicken');
      // Trusted, so the editor applies it rather than offering it. A plain
      // best guess would still need the tap this exists to remove.
      expect(suggestion?.isTrusted, isTrue);
      expect(suggestion?.origin, MatchOrigin.restaurantMenu);
    });

    test('and the household\'s own foods stay out of it', () {
      // Symmetrical to the cooking rule. Your raw chicken breast is not what
      // was in the bowl, and offering it would be the same error in reverse.
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'chicken breast',
        library: <Food>[ownChicken()],
        kind: RecipeKind.eatenOut,
      );

      expect(suggestion, isNull);
    });

    test('a partial name still finds the one thing it can mean', () {
      // Chipotle calls it "Cilantro-Lime White Rice"; nobody types that.
      final Food rice = aFood(
        'Cilantro-Lime White Rice',
        id: 'f-white-rice',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
      );
      final Food brown = aFood(
        'Cilantro-Lime Brown Rice',
        id: 'f-brown-rice',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
      );

      expect(
        IngredientMatcher.suggest(
          ingredientName: 'white rice',
          library: <Food>[rice, brown],
          kind: RecipeKind.eatenOut,
        )?.foodId,
        'f-white-rice',
      );
      // But a line that has genuinely not said which is still offered rather
      // than guessed at — the rule that will protect this the day a second
      // chain is seeded and there are two Chickens.
      expect(
        IngredientMatcher.suggest(
          ingredientName: 'rice',
          library: <Food>[rice, brown],
          kind: RecipeKind.eatenOut,
        ),
        isNull,
      );
    });

    test('two chains answering one line is offered, never applied', () {
      final Food cava = aFood(
        'Chicken',
        id: 'f-cava-chicken',
        brand: 'Cava',
        source: FoodSource.restaurant,
      );

      expect(
        IngredientMatcher.suggest(
          ingredientName: 'chicken',
          library: <Food>[chipotleChicken(), cava],
          kind: RecipeKind.eatenOut,
        ),
        isNull,
      );
    });

    test('a remembered restaurant match never leaks into a cooking recipe', () {
      // The hole this closes: picking Chipotle's chicken by hand in a bowl
      // writes an `ingredient_match` row keyed on "chicken", and remembered
      // matches are trusted — so the next chilli would silently count a
      // burrito's chicken. Excluding restaurant foods from the candidate pool
      // meant nothing while this path went around it.
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'chicken',
        library: <Food>[chipotleChicken(), ownChicken()],
        remembered: <String, String>{'chicken': 'f-chipotle-chicken'},
      );

      expect(suggestion?.foodId, isNot('f-chipotle-chicken'));
    });

    test('and a remembered household match does not leak the other way', () {
      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: 'beans',
        library: <Food>[
          ownChicken(),
          aFood('Black beans', id: 'f-own-beans'),
        ],
        remembered: <String, String>{'beans': 'f-own-beans'},
        kind: RecipeKind.eatenOut,
      );

      expect(suggestion, isNull);
    });
  });
}
