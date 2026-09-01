import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/default_sweep.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// Applying newly-marked defaults to recipes already saved (spec §5.3).
Food beef() =>
    aFood('Maverick Ranch 96/4 Ground Beef', id: 'food-beef').asDefault();

Recipe chilli({
  String id = 'recipe-chilli',
  String? beefFoodId,
  String beefLine = 'lean ground beef',
}) => aRecipe(
  title: 'Chilli',
  id: id,
  ingredients: <RecipeIngredient>[
    anIngredient(beefLine, id: '$id-beef', foodId: beefFoodId),
    anIngredient('salt', id: '$id-salt'),
  ],
);

void main() {
  group('what a sweep proposes', () {
    test('a line a default answers, with no food on it', () {
      final List<DefaultSweepChange> changes = DefaultSweep.proposals(
        recipes: <Recipe>[chilli()],
        library: <Food>[beef()],
      );

      expect(changes, hasLength(1));
      expect(changes.single.ingredient.name, 'lean ground beef');
      expect(changes.single.food.id, 'food-beef');
      expect(changes.single.recipe.id, 'recipe-chilli');
    });

    test('never a line that already has one', () {
      // Nothing anybody matched — or deliberately unmatched and left that
      // way — is second-guessed by a sweep.
      expect(
        DefaultSweep.proposals(
          recipes: <Recipe>[chilli(beefFoodId: 'food-other')],
          library: <Food>[beef()],
        ),
        isEmpty,
      );
    });

    test('never a line several defaults answer', () {
      // A sweep is the worst possible place to guess: it writes to recipes
      // nobody is looking at.
      final Recipe latte = aRecipe(
        title: 'Latte',
        id: 'recipe-latte',
        ingredients: <RecipeIngredient>[anIngredient('milk', id: 'i-milk')],
      );

      expect(
        DefaultSweep.proposals(
          recipes: <Recipe>[latte],
          library: <Food>[
            aFood('Whole milk', id: 'milk-whole').asDefault(),
            aFood('2% milk', id: 'milk-2').asDefault(),
          ],
        ),
        isEmpty,
      );
    });

    test('never a grade the line contradicts', () {
      expect(
        DefaultSweep.proposals(
          recipes: <Recipe>[chilli(beefLine: '88% ground beef')],
          library: <Food>[beef()],
        ),
        isEmpty,
      );
    });

    test('never a deleted recipe', () {
      expect(
        DefaultSweep.proposals(
          recipes: <Recipe>[
            aRecipe(
              title: 'Chilli',
              id: 'recipe-gone',
              isDeleted: true,
              ingredients: <RecipeIngredient>[
                anIngredient('lean ground beef', id: 'gone-beef'),
              ],
            ),
          ],
          library: <Food>[beef()],
        ),
        isEmpty,
      );
    });

    test('across the whole library, not just one recipe', () {
      final List<DefaultSweepChange> changes = DefaultSweep.proposals(
        recipes: <Recipe>[
          chilli(),
          chilli(id: 'recipe-tacos'),
        ],
        library: <Food>[beef()],
      );

      expect(changes, hasLength(2));
      expect(changes.map((DefaultSweepChange c) => c.recipe.id), <String>{
        'recipe-chilli',
        'recipe-tacos',
      });
    });
  });

  group('applying it', () {
    test('attaches the food and leaves everything else alone', () {
      final List<DefaultSweepChange> changes = DefaultSweep.proposals(
        recipes: <Recipe>[chilli()],
        library: <Food>[beef()],
      );

      final Recipe updated = DefaultSweep.apply(changes).single;
      final List<RecipeIngredient> lines = updated.allIngredients;

      expect(lines, hasLength(2));
      expect(lines.first.foodId, 'food-beef');
      expect(lines.first.id, 'recipe-chilli-beef', reason: 'ids are kept');
      expect(lines.last.name, 'salt');
      expect(lines.last.foodId, isNull);
      expect(updated.title, 'Chilli');
    });

    test('only the changes handed to it, so unticking really skips', () {
      final List<DefaultSweepChange> all = DefaultSweep.proposals(
        recipes: <Recipe>[
          chilli(),
          chilli(id: 'recipe-tacos'),
        ],
        library: <Food>[beef()],
      );

      final List<Recipe> saved = DefaultSweep.apply(<DefaultSweepChange>[
        all.firstWhere((DefaultSweepChange c) => c.recipe.id == 'recipe-tacos'),
      ]);

      expect(saved, hasLength(1));
      expect(saved.single.id, 'recipe-tacos');
    });

    test('a recipe none of the changes touch comes back untouched', () {
      final Recipe untouched = chilli(id: 'recipe-other');
      expect(
        identical(
          DefaultSweep.applyTo(untouched, const <DefaultSweepChange>[]),
          untouched,
        ),
        isTrue,
      );
    });
  });
}
