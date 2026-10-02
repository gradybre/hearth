import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/foods/usual_order_projection.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:hearth/features/recipes/usual_order_variation.dart';

import '../../support/fixtures.dart';
import 'restaurant_usual_fixtures.dart';

UsualOrderProjection _base(Recipe recipe) => UsualOrderProjection.resolve(
  recipe: recipe,
  restaurant: 'Corner Kitchen',
  foods: <String, Food>{
    for (final Food food in usualMenuFoods()) food.id: food,
  },
);

void main() {
  test(
    'different foods with the same name cannot silently share one match',
    () {
      final Recipe original = aRecipe(
        kind: RecipeKind.eatenOut,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Side',
            amount: 1,
            unit: Units.item,
            foodId: 'usual-burger',
          ),
          anIngredient(
            'side',
            amount: 100,
            unit: Units.gram,
            foodId: 'usual-rice',
          ),
        ],
      );
      final UsualOrderProjection base = _base(original);
      expect(
        () => usualOrderVariation(base: base, picks: base.picks),
        throwsStateError,
        reason: 'The editor stores one food match per normalized name.',
      );
      expect(
        original.allIngredients.map((RecipeIngredient i) => i.foodId),
        <String>['usual-burger', 'usual-rice'],
      );
    },
  );

  test(
    'variation keeps yield, exact amounts and unknown lines with new ids',
    () {
      final Recipe original = savedUsual(missing: true);
      final UsualOrderProjection base = _base(original);
      final RecipeDraft draft = usualOrderVariation(
        base: base,
        picks: base.picks,
      );
      final Recipe variation = draft.toRecipe();
      expect(draft.existingId, isNull);
      expect(draft.title, 'Our usual dinner (variation)');
      expect(variation.id, isNot(original.id));
      expect(variation.sections.single.id, isNot(original.sections.single.id));
      expect(variation.servings, 2);
      expect(
        variation.allIngredients.map((RecipeIngredient i) => i.name),
        <String>['Burger', 'Rice', 'House sauce'],
      );
      expect(variation.allIngredients[1].quantity!.canonicalAmount, 150);
      expect(variation.allIngredients.last.quantity!.canonicalAmount, 30);
      expect(variation.allIngredients.last.foodId, 'unavailable-sauce');
      expect(original.allIngredients, hasLength(3));
      expect(original.title, 'Our usual dinner');
    },
  );

  test(
    'changes add and remove ingredients without editing the saved recipe',
    () {
      final Recipe original = savedUsual();
      final UsualOrderProjection base = _base(original);
      final Recipe variation = usualOrderVariation(
        base: base,
        picks: <MenuPick>[
          base.picks.first,
          MenuPick(food: usualMenuFoods()[2], count: -1),
          MenuPick(food: usualMenuFoods()[3]),
        ],
      ).toRecipe();
      expect(
        variation.allIngredients.map((RecipeIngredient i) => i.name),
        <String>['Burger', 'Lettuce', 'Lettuce wrap'],
      );
      expect(
        variation.allIngredients[1].quantity!.canonicalAmount,
        lessThan(0),
      );
      expect(variation.allIngredients[2].quantity!.canonicalAmount, 1);
      expect(
        original.allIngredients.map((RecipeIngredient i) => i.name),
        <String>['Burger', 'Rice'],
      );
      expect(variation.servings, 2);
    },
  );

  test(
    'untouched parsed precision survives projection and editor serialization',
    () {
      final Recipe original = aRecipe(
        kind: RecipeKind.eatenOut,
        servings: 3,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Rice',
            amount: 125.123456789123,
            unit: Units.gram,
            foodId: 'usual-rice',
          ),
        ],
      );
      final UsualOrderProjection base = _base(original);
      final Recipe variation = usualOrderVariation(
        base: base,
        picks: base.picks,
      ).toRecipe();
      expect(
        variation.allIngredients.single.quantity!.canonicalAmount,
        original.allIngredients.single.quantity!.canonicalAmount,
      );
      expect(variation.servings, 3);
    },
  );

  test(
    'unsupported units, optional lines and duplicate foods remain for review',
    () {
      final Recipe original = aRecipe(
        kind: RecipeKind.eatenOut,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Rice',
            amount: 1,
            unit: Units.cup,
            foodId: 'usual-rice',
          ),
          anIngredient(
            'Rice',
            amount: 50,
            unit: Units.gram,
            foodId: 'usual-rice',
          ),
          anIngredient('Garnish', amount: 1, unit: Units.item, optional: true),
          anIngredient('Salt', needsNoMatch: true),
        ],
      );
      final UsualOrderProjection base = _base(original);
      final Recipe variation = usualOrderVariation(
        base: base,
        picks: base.picks,
      ).toRecipe();
      expect(variation.allIngredients, hasLength(4));
      expect(variation.allIngredients[0].quantity!.preferredUnit, Units.cup);
      expect(variation.allIngredients[1].quantity!.canonicalAmount, 50);
      expect(variation.allIngredients[2].isOptional, isTrue);
      expect(variation.allIngredients[3].needsNoMatch, isTrue);
    },
  );
}
