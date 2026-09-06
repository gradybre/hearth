import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Never being locked in (spec §7.4).
void main() {
  late HearthDatabase db;
  late DataExport export;
  late RecipeStore recipes;
  late FoodStore foods;
  late PlanRepository plans;
  final DateTime clock = DateTime.utc(2026, 9, 3, 12);

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeStore(db);
    foods = FoodStore(db);
    plans = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'user-1',
      clock: () => clock,
    );
    export = DataExport(
      database: db,
      recipes: recipes,
      foods: foods,
      clock: () => clock,
    );

    await recipes.upsert(
      aRecipe(
        id: 'recipe-1',
        title: 'Chilli',
        ingredients: <RecipeIngredient>[anIngredient('ground beef', amount: 1)],
      ),
      updatedAt: clock,
    );
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> run() =>
      export.asJson(householdId: 'household-1', userId: 'user-1');

  test('says what it is and when it was taken', () async {
    final Map<String, Object?> json = await run();

    expect(json['format'], 'hearth-export');
    expect(json['version'], DataExport.formatVersion);
    expect(json['exported_at'], '2026-09-03T12:00:00.000Z');
  });

  test('carries the recipe library whole', () async {
    final Map<String, Object?> json = await run();

    final List<Object?> out = json['recipes']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['title'], 'Chilli');
    // Its parts too, not just the header.
    expect((out.single! as Map<String, Object?>)['ingredients'], isNotEmpty);
  });

  test('and a recipe you binned, because you still wrote it', () async {
    // An export whose promise is "you are never locked in" should not quietly
    // drop the ones you deleted — every log pointing at one would otherwise
    // resolve to nothing.
    await recipes.softDelete('recipe-1', updatedAt: clock);

    final List<Object?> out = (await run())['recipes']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['is_deleted'], isTrue);
  });

  test('a logged meal keeps its frozen snapshot, verbatim', () async {
    // The §4 non-negotiable, and the sharpest form of it: log a meal, then
    // change the recipe underneath. An export that recalculated from the
    // recipe as it stands today would be a record of a past that never
    // happened.
    await plans.add(
      date: clock,
      slot: MealSlot.dinner,
      refType: PlanRefType.recipe,
      refId: 'recipe-1',
      servings: 2,
      loggedMacros: const Macros(kcal: 500, proteinG: 40, carbG: 30, fatG: 20),
      // This test is not about coverage; saying so beats letting the
      // repository infer a completeness nothing checked.
      loggedCoverage: const NutrientCoverage.notRecorded(),
    );

    await recipes.upsert(
      aRecipe(
        id: 'recipe-1',
        title: 'Chilli, now with double everything',
        ingredients: <RecipeIngredient>[
          anIngredient('ground beef', amount: 99),
        ],
      ),
      updatedAt: clock,
    );

    final List<Object?> entries =
        (await run())['meal_plan_entries']! as List<Object?>;
    final Map<String, Object?> entry = entries.single! as Map<String, Object?>;

    expect(entry['is_logged'], isTrue);
    final Map<String, Object?> snapshot =
        entry['macro_snapshot']! as Map<String, Object?>;
    // 500 a serving, two servings — what was actually eaten, and untouched by
    // the edit above.
    expect(snapshot['kcal'], 1000);
    // Real JSON, not a string holding JSON — the file is meant to be read.
    expect(entry['macro_snapshot'], isA<Map<String, Object?>>());
  });

  test('another person\'s plan is not in your export', () async {
    // Plans and logs are private per user (§5.1), household or not.
    final PlanRepository theirs = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'user-2',
      clock: () => clock,
    );
    await theirs.add(
      date: clock,
      slot: MealSlot.lunch,
      refType: PlanRefType.recipe,
      refId: 'recipe-1',
      servings: 1,
    );

    final Map<String, Object?> json = await run();
    expect(json['meal_plan_days'], isEmpty);
    expect(json['meal_plan_entries'], isEmpty);
  });

  test('a food and its serving options come along', () async {
    await foods.upsert(
      Food(
        id: 'food-1',
        householdId: 'household-1',
        name: 'Ground beef',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'serving-1',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: const Macros(kcal: 250, proteinG: 26, carbG: 0, fatG: 15),
            isReference: true,
          ),
        ],
      ),
      updatedAt: clock,
    );

    final List<Object?> out = (await run())['foods']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['name'], 'Ground beef');
    expect(
      (out.single! as Map<String, Object?>)['serving_options'],
      isNotEmpty,
    );
  });

  test('the global catalogue is left out', () async {
    // Not yours, not your data, and it would dwarf everything that is.
    await foods.upsert(
      const Food(
        id: 'global-1',
        name: 'Generic apple',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[],
      ),
      updatedAt: clock,
    );

    final List<Object?> out = (await run())['foods']! as List<Object?>;
    expect(out, isEmpty);
  });

  test('it says plainly that photos are not in it', () async {
    expect(await run(), containsPair('note', contains('photos are not')));
  });

  test('the file is named for the day and is real JSON', () async {
    final ExportedFile file = await export.build(
      householdId: 'household-1',
      userId: 'user-1',
    );

    expect(file.name, 'hearth-2026-09-03.json');
    expect(jsonDecode(file.contents), isA<Map<String, Object?>>());
    // Indented, because a person may open it.
    expect(file.contents, contains('\n  "version"'));
    expect(file.bytes, greaterThan(0));
  });
}
