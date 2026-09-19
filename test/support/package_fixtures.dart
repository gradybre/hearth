import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

// Synthetic product and nutrition data, never a household record.
Food packageCorn({bool approximate = false}) => Food(
  id: 'test-package-corn',
  name: 'Frozen corn',
  source: FoodSource.manual,
  packSize: Quantity.of(10, Units.ounce),
  servingOptions: <ServingOption>[
    ServingOption(
      id: 'test-corn-cup',
      label: '1 cup',
      amount: Quantity.of(1, Units.cup),
      macros: const Macros(
        kcal: 100,
        proteinG: 3,
        carbG: 20,
        fatG: 1,
        fiberG: 2,
        sodiumMg: 10,
        cholesterolMg: 0,
      ),
    ),
  ],
  packageNutrition: PackageNutrition.manual(
    servingsPerPackage: 2,
    servingOptionId: 'test-corn-cup',
    servingAmount: Quantity.of(1, Units.cup),
    packageAmount: Quantity.of(10, Units.ounce),
    isApproximate: approximate,
  ),
);
Recipe packageRecipe() => Recipe(
  id: 'test-package-recipe',
  title: 'Three-pack corn soup',
  servings: 3,
  sections: <RecipeSection>[
    RecipeSection(
      id: 'test-section',
      sortOrder: 0,
      name: 'Soup',
      ingredients: <RecipeIngredient>[
        RecipeIngredient(
          id: 'test-corn-ingredient',
          sectionId: 'test-section',
          name: 'Frozen corn',
          sortOrder: 0,
          foodId: 'test-package-corn',
          rawText: '3 (10 oz) bags frozen corn',
          quantity: Quantity.of(30, Units.ounce),
        ),
      ],
      steps: const <RecipeStep>[
        RecipeStep(
          id: 'test-step',
          sectionId: 'test-section',
          stepNumber: 1,
          text: 'Add the frozen corn to the soup and simmer.',
        ),
      ],
    ),
  ],
);

class PackageFixtureReader implements LabelReader {
  PackageFixtureReader({this.partial = false, this.failFirst = false});
  final bool failFirst;
  int calls = 0;
  final bool partial;
  @override
  Future<LabelReading> read(List<AiImage> images) async {
    if (failFirst && calls++ == 0) {
      throw const RecipeAiException('The reader is busy. Try again.');
    }
    return LabelReading(
      name: 'Frozen corn',
      packageSize: Quantity.of(10, Units.ounce),
      servingsPerContainer: partial ? null : 2,
      packageBasis: partial ? 'unknown' : 'as_packaged',
      servings: partial
          ? const <LabelServing>[]
          : const <LabelServing>[
              LabelServing(
                amount: 1,
                unitId: 'cup',
                kcal: 100,
                proteinG: 3,
                carbG: 20,
                fatG: 1,
                fiberG: 2,
                sodiumMg: 10,
                cholesterolMg: 0,
              ),
            ],
    );
  }

  @override
  Future<PackReading> readPack(List<AiImage> images) async =>
      PackReading(size: Quantity.of(10, Units.ounce));
}
