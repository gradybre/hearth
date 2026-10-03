import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

List<Food> usualMenuFoods() => <Food>[
  aFood(
    'Burger',
    id: 'usual-burger',
    brand: 'Corner Kitchen',
    source: FoodSource.restaurant,
    menuOrder: 1,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        macros: const Macros(
          kcal: 600,
          proteinG: 30,
          carbG: 50,
          fatG: 25,
          fiberG: 4,
          sodiumMg: 900,
          cholesterolMg: 70,
        ),
      ),
    ],
  ),
  aFood(
    'Rice',
    id: 'usual-rice',
    brand: 'Corner Kitchen',
    source: FoodSource.restaurant,
    menuOrder: 2,
    servingOptions: <ServingOption>[
      aServing(
        amount: 100,
        unit: Units.gram,
        macros: const Macros(
          kcal: 200,
          proteinG: 4,
          carbG: 40,
          fatG: 2,
          fiberG: 1,
          sodiumMg: 5,
          cholesterolMg: 0,
        ),
      ),
    ],
  ),
  aFood(
    'Lettuce',
    id: 'usual-lettuce',
    brand: 'Corner Kitchen',
    source: FoodSource.restaurant,
    menuOrder: 3,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.ounce,
        macros: const Macros(kcal: 5, carbG: 1, fiberG: 0.5, sodiumMg: 2),
      ),
    ],
  ),
  aFood(
    'Lettuce wrap',
    id: 'usual-wrap',
    brand: 'Corner Kitchen',
    source: FoodSource.restaurant,
    menuOrder: 4,
    isModifier: true,
    servingOptions: <ServingOption>[
      aServing(
        amount: 1,
        unit: Units.item,
        macros: const Macros(kcal: -180, carbG: -30, fatG: -5, fiberG: 1),
      ),
    ],
  ),
];

Recipe savedUsual({bool missing = false}) => aRecipe(
  id: 'saved-usual',
  title: 'Our usual dinner',
  servings: 2,
  kind: RecipeKind.eatenOut,
  notes: 'Corner Kitchen',
  ingredients: <RecipeIngredient>[
    anIngredient(
      'Burger',
      amount: 2,
      unit: Units.item,
      foodId: 'usual-burger',
      sortOrder: 0,
    ),
    anIngredient(
      'Rice',
      amount: 150,
      unit: Units.gram,
      foodId: 'usual-rice',
      sortOrder: 1,
    ),
    if (missing)
      anIngredient(
        'House sauce',
        amount: 30,
        unit: Units.gram,
        foodId: 'unavailable-sauce',
        sortOrder: 2,
      ),
  ],
);
