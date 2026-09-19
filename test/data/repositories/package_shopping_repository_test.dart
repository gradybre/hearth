import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/shopping/cart_quantity.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// The list reading its own library (spec R5).
///
/// The repository is the only thing here that knows which foods exist, so it
/// is where a line's total gets brought into step with the food it is
/// matched to — once per write, not once per line.
void main() {
  late HearthDatabase db;
  late ShoppingRepository repository;
  final DateTime clock = DateTime.utc(2026, 9, 2, 9);

  Food sparkle() {
    final Quantity pack = Quantity.of(10, Units.ounce);
    final Quantity serving = Quantity.of(1, Units.cup);
    return Food(
      id: 'f-sparkle',
      householdId: 'household-1',
      name: 'Sparkle powder',
      source: FoodSource.manual,
      packSize: pack,
      servingOptions: <ServingOption>[
        ServingOption(
          id: 'f-sparkle-cup',
          label: '1 cup',
          amount: serving,
          macros: const Macros(kcal: 100, proteinG: 7, carbG: 1, fatG: 8),
        ),
      ],
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'f-sparkle-cup',
        servingAmount: serving,
        packageAmount: pack,
      ),
    );
  }

  Recipe bake() => aRecipe(
    id: 'r-bake',
    title: 'Sparkle bake',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'sparkle powder',
            amount: 2,
            unit: Units.cup,
            sectionId: 's1',
            foodId: 'f-sparkle',
          ),
        ],
      ),
    ],
  );

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    repository = ShoppingRepository(
      database: db,
      store: ShoppingStore(db),
      queue: PendingWriteStore(db),
      householdId: 'household-1',
      now: () => clock,
      idFactory: () => 'list-1',
    );
    await FoodStore(db).upsert(sparkle(), updatedAt: clock);
  });

  tearDown(() => db.close());

  test('a recipe measured in cups lands on the list in packages', () async {
    final List<ShoppingLine> lines = await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );

    final Quantity total = lines.single.planned.single;
    expect(total.kind, UnitKind.mass);
    expect(total.amountIn(Units.ounce), closeTo(10, 1e-6));
    expect(
      CartQuantity.forLine(line: lines.single, pack: sparkle().packSize),
      1,
    );
  });

  test('and it survives being written and read back', () async {
    await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );

    final ShoppingListSnapshot? reread = await repository.current();
    final ShoppingLine line = reread!.lines.single;
    // The ask is still the cups somebody asked for — the total is derived
    // from it every time, never stored in its place.
    expect(line.contributions.single.quantities.single.kind, UnitKind.volume);
    expect(line.planned.single.amountIn(Units.ounce), closeTo(10, 1e-6));
  });

  test('adding it twice is two packages', () async {
    await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );
    final List<ShoppingLine> lines = await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );

    expect(
      lines.single.planned.single.amountIn(Units.ounce),
      closeTo(20, 1e-6),
    );
    expect(
      CartQuantity.forLine(line: lines.single, pack: sparkle().packSize),
      2,
    );
  });

  test('a food added on its own is counted the same way', () async {
    final List<ShoppingLine> lines = await repository.addFood(
      food: sparkle(),
      servings: 3,
    );

    // Three 1 cup servings of a food whose cup weighs 5 oz.
    expect(
      lines.single.planned.single.amountIn(Units.ounce),
      closeTo(15, 1e-6),
    );
  });

  test('and taking the recipe back off clears the line', () async {
    await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );
    expect(await repository.removeSource('recipe:r-bake'), isEmpty);
  });

  /// The same food and the same package, holding a different number of
  /// servings — which is the whole of what a household can get wrong and
  /// then correct.
  Food sparkleWith(double servingsPerPackage) {
    final Food base = sparkle();
    return Food(
      id: base.id,
      householdId: base.householdId,
      name: base.name,
      source: base.source,
      packSize: base.packSize,
      servingOptions: base.servingOptions,
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: servingsPerPackage,
        servingOptionId: 'f-sparkle-cup',
        servingAmount: base.servingOptions.single.amount,
        packageAmount: base.packSize!,
      ),
    );
  }

  /// The same food with no relationship at all.
  Food unlinkedSparkle() {
    final Food base = sparkle();
    return Food(
      id: base.id,
      householdId: base.householdId,
      name: base.name,
      source: base.source,
      packSize: base.packSize,
      servingOptions: base.servingOptions,
    );
  }

  test('correcting the servings per package recounts the same ask', () async {
    await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );

    final Food denser = sparkleWith(4);
    await FoodStore(db).upsert(denser, updatedAt: clock);

    // Written back untouched: the ask is what is stored, so re-settling is
    // all it takes for the correction to reach the line.
    final ShoppingListSnapshot? before = await repository.current();
    final List<ShoppingLine> after = await repository.replace(before!.lines);

    expect(
      after.single.contributions.single.quantities.single.kind,
      UnitKind.volume,
    );
    expect(after.single.planned.single.amountIn(Units.ounce), closeTo(5, 1e-6));
    expect(CartQuantity.forLine(line: after.single, pack: denser.packSize), 1);
  });

  test('and taking the relation away puts the cups back', () async {
    await repository.addRecipe(
      recipe: bake(),
      servings: 4,
      foods: <String, Food>{'f-sparkle': sparkle()},
    );

    await FoodStore(db).upsert(unlinkedSparkle(), updatedAt: clock);

    final ShoppingListSnapshot? before = await repository.current();
    final List<ShoppingLine> after = await repository.replace(before!.lines);

    // Nothing left to convert with, so no package count is guessed at.
    expect(after.single.planned.single.kind, UnitKind.volume);
    expect(after.single.planned.single.amountIn(Units.cup), closeTo(2, 1e-6));
  });
}
