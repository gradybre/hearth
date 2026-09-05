import 'package:hearth/domain/foods/eatable_foods.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/ingredient_matcher.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// A modifier is what you log *against*, never what you log (spec §5.2).
///
/// Freddy's "Make any Sandwich a Lettuce Wrap" is −180 kcal. On its own it is
/// not a meal, it is an accounting error waiting to be committed: a day with
/// one logged reads 180 calories lighter than the day that actually happened,
/// and once it is frozen into a log snapshot nothing can correct it (rule 3).
/// So every place that offers a food to eat has to leave it out, and each of
/// those places is one line that could quietly stop working.
void main() {
  final Food wrap = aFood(
    'Make any Sandwich a Lettuce Wrap',
    id: 'wrap',
    source: FoodSource.restaurant,
    brand: "Freddy's",
  ).asModifier();
  final Food burger = aFood(
    'Single Steakburger',
    id: 'burger',
    source: FoodSource.restaurant,
    brand: "Freddy's",
  );
  final Food beef = aFood('Ground Beef', id: 'beef');

  group('what may be chosen to eat', () {
    test('leaves a modifier out and keeps everything else', () {
      expect(
        eatableFoods(<Food>[burger, wrap, beef]).map((Food f) => f.id),
        <String>['burger', 'beef'],
      );
    });

    test('and a deleted food, which was never choosable either', () {
      final Food gone = aFood('Old', id: 'gone').withDeleted();

      expect(eatableFoods(<Food>[gone, beef]).map((Food f) => f.id), <String>[
        'beef',
      ]);
    });
  });

  group('what may be matched into a recipe', () {
    test('a modifier is not offered to an eaten-out recipe', () {
      // Which is the one kind that *does* match restaurant foods, so this is
      // the case a `source == restaurant` gate alone would let through.
      expect(
        IngredientMatcher.matchable(<Food>[
          burger,
          wrap,
        ], kind: RecipeKind.eatenOut).map((Food f) => f.id),
        <String>['burger'],
      );
    });

    test('nor to a cooked one', () {
      final Food homeWrap = aFood('Skip the bun', id: 'home').asModifier();

      expect(
        IngredientMatcher.matchable(<Food>[beef, homeWrap])
            .map((Food f) => f.id),
        <String>['beef'],
      );
    });
  });
}
