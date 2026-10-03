import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/foods/usual_order_projection.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

Food _food({
  String id = 'rice',
  num amount = 100,
  Unit unit = Units.gram,
  bool modifier = false,
  bool deleted = false,
  Macros macros = const Macros(kcal: 200, proteinG: 4, carbG: 40, fatG: 2),
}) => Food(
  name: id,
  id: id,
  brand: 'Corner Kitchen',
  source: FoodSource.restaurant,
  isModifier: modifier,
  isDeleted: deleted,
  servingOptions: <ServingOption>[
    aServing(amount: amount, unit: unit, macros: macros),
  ],
);

UsualOrderProjection _project(
  List<RecipeIngredient> ingredients,
  List<Food> foods, {
  double yield = 1,
}) => UsualOrderProjection.resolve(
  recipe: aRecipe(
    id: 'saved-order',
    ingredients: ingredients,
    servings: yield,
    kind: RecipeKind.eatenOut,
  ),
  restaurant: 'Corner Kitchen',
  foods: <String, Food>{for (final Food food in foods) food.id: food},
);

void main() {
  test('shared modifier guard accepts once and rejects repeated or unrepresentable amounts', () {
    final Food modifier = _food(
      id: 'wrap',
      amount: 1,
      unit: Units.item,
      modifier: true,
    );
    final Map<String, Food> foods = <String, Food>{modifier.id: modifier};
    Recipe recipe(List<RecipeIngredient> ingredients) =>
        aRecipe(kind: RecipeKind.eatenOut, ingredients: ingredients);
    RecipeIngredient line({
      double amount = 1,
      Unit unit = Units.item,
      bool optional = false,
    }) => anIngredient(
      'Wrap',
      amount: amount,
      unit: unit,
      foodId: 'wrap',
      optional: optional,
    );
    expect(
      usualOrderModifierProblem(recipe(<RecipeIngredient>[line()]), foods),
      isNull,
    );
    expect(
      usualOrderModifierProblem(
        recipe(<RecipeIngredient>[line(), line(optional: true)]),
        foods,
      ),
      isNull,
    );
    for (final List<RecipeIngredient> ingredients in <List<RecipeIngredient>>[
      <RecipeIngredient>[line(amount: 2)],
      <RecipeIngredient>[line(), line()],
      <RecipeIngredient>[line(unit: Units.gram)],
      <RecipeIngredient>[anIngredient('Wrap', foodId: 'wrap')],
    ]) {
      expect(
        usualOrderModifierProblem(recipe(ingredients), foods),
        contains('only once'),
      );
    }
  });

  test('restores exact whole-order quantity without multiplying by yield', () {
    final UsualOrderProjection result = _project(
      <RecipeIngredient>[
        anIngredient(
          'Rice',
          amount: 0.125,
          unit: Units.kilogram,
          foodId: 'rice',
        ),
      ],
      <Food>[_food()],
      yield: 2,
    );
    expect(result.picks.single.count, 1.25);
    expect(result.picks.single.quantity!.canonicalAmount, 125);
    expect(result.recipe.servings, 2);
    expect(result.nutrition.total.kcal, 250);
    expect(result.nutrition.perServing.kcal, 125);
    expect(result.unresolved, isEmpty);
  });

  test(
    'changed current menu portion is a new projection, not a guessed count',
    () {
      final List<RecipeIngredient> ingredients = <RecipeIngredient>[
        anIngredient('Rice', amount: 125, unit: Units.gram, foodId: 'rice'),
      ];
      final UsualOrderProjection before = _project(ingredients, <Food>[
        _food(),
      ]);
      final UsualOrderProjection after = _project(ingredients, <Food>[
        _food(amount: 250),
      ]);
      expect(after.picks.single.count, 0.5);
      expect(before.hasSamePortionBasis(after), isFalse);
    },
  );

  test(
    'nutrient-only updates use current facts without changing quantities',
    () {
      final List<RecipeIngredient> ingredients = <RecipeIngredient>[
        anIngredient('Rice', amount: 100, unit: Units.gram, foodId: 'rice'),
      ];
      final UsualOrderProjection before = _project(ingredients, <Food>[
        _food(),
      ]);
      final UsualOrderProjection after = _project(ingredients, <Food>[
        _food(macros: const Macros(kcal: 240)),
      ]);
      expect(before.hasSamePortionBasis(after), isTrue);
      expect(after.nutrition.total.kcal, 240);
    },
  );

  for (final bool deleted in <bool>[false, true]) {
    test('missing or deleted components remain visible ($deleted)', () {
      final UsualOrderProjection result = _project(<RecipeIngredient>[
        anIngredient('Rice', amount: 100, unit: Units.gram, foodId: 'rice'),
      ], deleted ? <Food>[_food(deleted: true)] : <Food>[]);
      expect(result.picks, isEmpty);
      expect(result.unresolved.single.ingredient.name, 'Rice');
      expect(result.unresolved.single.reason, contains('unavailable'));
      expect(result.nutrition.isIncomplete, isTrue);
    });
  }

  test('different units and absent amounts are exposed, never guessed', () {
    final UsualOrderProjection result = _project(
      <RecipeIngredient>[
        anIngredient('Rice', amount: 1, unit: Units.cup, foodId: 'rice'),
        anIngredient('Sauce', foodId: 'sauce'),
      ],
      <Food>[_food(), _food(id: 'sauce')],
    );
    expect(result.picks, isEmpty);
    expect(result.unresolved, hasLength(2));
    expect(result.unresolved[0].reason, contains('unit differs'));
    expect(result.unresolved[1].reason, contains('no usable amount'));
  });

  test('repeated and deliberately excluded lines are kept for review', () {
    final UsualOrderProjection result = _project(
      <RecipeIngredient>[
        anIngredient('Rice', amount: 100, unit: Units.gram, foodId: 'rice'),
        anIngredient('Rice', amount: -10, unit: Units.gram, foodId: 'rice'),
        anIngredient('Garnish', amount: 5, unit: Units.gram, optional: true),
      ],
      <Food>[_food()],
    );
    expect(result.picks, isEmpty);
    expect(result.unresolved, hasLength(3));
    expect(result.unresolved.last.reason, contains('Excluded'));
  });

  test(
    'modifier signs are per nutrient and applying one twice is unresolved',
    () {
      final Food modifier = _food(
        id: 'wrap',
        amount: 1,
        unit: Units.item,
        modifier: true,
        macros: const Macros(kcal: -180, carbG: -30, fiberG: 1),
      );
      final UsualOrderProjection result = _project(
        <RecipeIngredient>[
          anIngredient('Wrap', amount: 2, unit: Units.item, foodId: 'wrap'),
        ],
        <Food>[modifier],
      );
      expect(result.unresolved.single.reason, contains('only once'));
      final UsualOrderChange adding = UsualOrderChange.between(
        <MenuPick>[],
        <MenuPick>[MenuPick(food: modifier)],
      ).single;
      expect(adding.added, isTrue);
      expect(adding.nutrients!.kcal, -180);
      expect(adding.nutrients!.fiberG, 1);
      final UsualOrderChange removing = UsualOrderChange.between(<MenuPick>[
        MenuPick(food: modifier),
      ], <MenuPick>[]).single;
      expect(removing.nutrients!.kcal, 180);
      expect(removing.nutrients!.fiberG, -1);
    },
  );

  test('ordinary removals retain their sign and unknown nutrients', () {
    final Food rice = _food();
    final UsualOrderChange change = UsualOrderChange.between(
      <MenuPick>[MenuPick(food: rice)],
      <MenuPick>[MenuPick(food: rice, count: 0.5)],
    ).single;
    expect(change.added, isFalse);
    expect(change.pick.count, -0.5);
    expect(change.nutrients!.kcal, -100);
    expect(change.nutrients!.sodiumMg, isNull);
  });
}
