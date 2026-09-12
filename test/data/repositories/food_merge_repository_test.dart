import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/food_merge_repository.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/repositories/recipe_repository.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/foods/food_merge.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Merging two foods, for real (review N05).
///
/// The safety note this has to satisfy: "preserve or convert compatible
/// serving references explicitly, protect pending writes, and never
/// recalculate old logs. Soft-delete superseded definitions only after their
/// live references are safely handled."
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late FoodRepository foods;
  late RecipeRepository recipes;
  late FoodMergeRepository merger;

  final DateTime now = DateTime.utc(2026, 9, 11, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    foods = FoodRepository(
      database: db,
      store: FoodStore(db),
      queue: queue,
      householdId: 'household-1',
      clock: () => now,
    );
    recipes = RecipeRepository(
      database: db,
      store: RecipeStore(db),
      queue: queue,
      householdId: 'household-1',
      clock: () => now,
    );
    merger = FoodMergeRepository(
      database: db,
      foods: foods,
      recipes: recipes,
      matches: IngredientMatchRepository(
        database: db,
        store: IngredientMatchStore(db),
        queue: queue,
        householdId: 'household-1',
        now: () => now,
      ),
      plan: PlanRepository(
        database: db,
        store: PlanStore(db),
        queue: queue,
        userId: 'user-1',
        clock: () => now,
      ),
      shopping: ShoppingRepository(
        database: db,
        store: ShoppingStore(db),
        queue: queue,
        householdId: 'household-1',
        now: () => now,
      ),
      queue: queue,
    );
  });

  tearDown(() => db.close());

  Food yogurt({
    required String id,
    double amount = 170,
    Unit unit = Units.gram,
    String? barcode,
  }) => aFood(
    'Greek yogurt',
    id: id,
    barcode: barcode,
    servingOptions: <ServingOption>[
      aServing(
        id: '$id-s',
        amount: amount,
        unit: unit,
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  /// Both foods in the library, and the queue emptied afterwards — saving
  /// enqueues, and a merge refuses while anything is queued.
  Future<(Food, Food)> twoFoods({
    double retiringAmount = 170,
    Unit retiringUnit = Units.gram,
    String? retiringBarcode,
  }) async {
    final Food keep = yogurt(id: 'f-keep', amount: 100);
    final Food go = yogurt(
      id: 'f-go',
      amount: retiringAmount,
      unit: retiringUnit,
      barcode: retiringBarcode,
    );
    await FoodStore(db).upsert(keep, updatedAt: now);
    await FoodStore(db).upsert(go, updatedAt: now);
    return (keep, go);
  }

  Future<void> drainQueue() async {
    await db.delete(db.pendingWrites).go();
  }

  group('what the plan finds', () {
    test(
      'a recipe line that will keep counting, and one that will not',
      () async {
        final (Food keep, Food go) = await twoFoods();
        await recipes.save(
          aRecipe(
            id: 'r1',
            title: 'Chilli',
            sections: <RecipeSection>[
              aSection(
                id: 's1',
                ingredients: <RecipeIngredient>[
                  anIngredient(
                    'yogurt',
                    amount: 200,
                    unit: Units.gram,
                    foodId: 'f-go',
                    sectionId: 's1',
                  ),
                  anIngredient(
                    'yogurt again',
                    amount: 2,
                    unit: Units.item,
                    foodId: 'f-go',
                    sectionId: 's1',
                  ),
                ],
              ),
            ],
          ),
        );
        await drainQueue();

        final MergePlan plan = await merger.plan(survivor: keep, retiring: go);

        expect(plan.recipeLines, 1, reason: 'the gram line still counts');
        expect(plan.stranded, hasLength(1));
        expect(plan.stranded.single.ingredientName, 'yogurt again');
      },
    );

    test('and a logged meal, reported but not moved', () async {
      final (Food keep, Food go) = await twoFoods();
      await _logAMeal(db, foodId: 'f-go', servings: 1, logged: true);
      await _logAMeal(db, foodId: 'f-go', servings: 2, logged: false);
      await drainQueue();

      final MergePlan plan = await merger.plan(survivor: keep, retiring: go);

      expect(plan.loggedMeals, 1);
      expect(plan.plannedMeals, hasLength(1));
    });
  });

  group('applying it', () {
    test('moves the recipe line to the surviving food', () async {
      final (Food keep, Food go) = await twoFoods();
      await recipes.save(
        aRecipe(
          id: 'r1',
          title: 'Chilli',
          sections: <RecipeSection>[
            aSection(
              id: 's1',
              ingredients: <RecipeIngredient>[
                anIngredient(
                  'yogurt',
                  amount: 200,
                  unit: Units.gram,
                  foodId: 'f-go',
                  sectionId: 's1',
                ),
              ],
            ),
          ],
        ),
      );
      await drainQueue();

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final Recipe after = (await recipes.all()).single;
      expect(after.allIngredients.single.foodId, 'f-keep');
    });

    test('rewrites a planned meal so it still means the same food', () async {
      // 1 x 170 g becomes 1.7 x 100 g.
      final (Food keep, Food go) = await twoFoods();
      await _logAMeal(db, foodId: 'f-go', servings: 1, logged: false);
      await drainQueue();

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final MealPlanEntryRow row =
          (await db.select(db.mealPlanEntries).get()).single;
      expect(row.refId, 'f-keep');
      expect(row.servings, closeTo(1.7, 0.0001));
    });

    test('and leaves a logged meal exactly alone', () async {
      // Rule 3, and the reason a merge is safe at all. The entry keeps its
      // reference, its portion and its frozen macros; the food it points at
      // is soft-deleted, so the day view reads the name off the snapshot.
      final (Food keep, Food go) = await twoFoods();
      await _logAMeal(db, foodId: 'f-go', servings: 3, logged: true);
      await drainQueue();
      final MealPlanEntryRow before =
          (await db.select(db.mealPlanEntries).get()).single;

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final MealPlanEntryRow after =
          (await db.select(db.mealPlanEntries).get()).single;
      expect(after.refId, 'f-go');
      expect(after.servings, 3);
      expect(after.macroSnapshot, before.macroSnapshot);
    });

    test('soft-deletes the retired food, never removing it', () async {
      // A logged meal still points at it, and an absence cannot travel to the
      // other phone (rule 3).
      final (Food keep, Food go) = await twoFoods();
      await drainQueue();

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows, hasLength(2));
      expect(rows.firstWhere((FoodRow r) => r.id == 'f-go').isDeleted, isTrue);
    });

    test('gives the survivor both servings and the retired barcode', () async {
      final (Food keep, Food go) = await twoFoods(
        retiringBarcode: '5000157024671',
      );
      await drainQueue();

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final Food? after = await foods.byId('f-keep');
      expect(after!.servingOptions, hasLength(2));
      expect(after.barcode, '5000157024671');
    });

    test('and queues every change for the other phone', () async {
      // Every one, not just the foods. The retirement syncs whatever else
      // does, so a moved plan entry that never left this device leaves the
      // partner's phone with a planned meal pointing at a food that has been
      // deleted there — and a planned entry has no snapshot to fall back on,
      // so it reads as "Removed food".
      final (Food keep, Food go) = await twoFoods();
      await _logAMeal(db, foodId: 'f-go', servings: 1, logged: false);
      await _aShoppingLine(db, foodId: 'f-go');
      await drainQueue();

      await merger.apply(await merger.plan(survivor: keep, retiring: go));

      final List<String> queued = (await db.select(db.pendingWrites).get())
          .map((PendingWriteRow r) => r.entityTable)
          .toList();
      expect(queued, contains('foods'));
      expect(
        queued,
        contains('meal_plan_entries'),
        reason: 'the moved plan entry has to travel',
      );
      expect(
        queued,
        contains('shopping_list_items'),
        reason: 'the moved shopping line has to travel',
      );
    });

    test('and never rewrites a meal logged after the plan was drawn', () async {
      // The race rule 3 cares about: the plan counts an entry as planned, the
      // user logs it while reading the review, and the merge then rewrites a
      // *logged* meal's reference and portion. The snapshot would survive but
      // the entry would not be the one that was eaten.
      final (Food keep, Food go) = await twoFoods();
      await _logAMeal(db, foodId: 'f-go', servings: 1, logged: false);
      await drainQueue();
      final MergePlan plan = await merger.plan(survivor: keep, retiring: go);
      expect(plan.plannedMeals, hasLength(1));

      // Logged in the meantime.
      await db
          .update(db.mealPlanEntries)
          .write(const MealPlanEntriesCompanion(isLogged: Value(true)));

      await merger.apply(plan);

      final MealPlanEntryRow after =
          (await db.select(db.mealPlanEntries).get()).single;
      expect(after.refId, 'f-go', reason: 'a logged meal is never repointed');
      expect(after.servings, 1);
    });
  });

  group('and it refuses', () {
    test('while either food has writes still queued', () async {
      // Merging now would race them: the partner could receive the retirement
      // before the edit it supersedes.
      final (Food keep, Food go) = await twoFoods();
      await drainQueue();
      final MergePlan plan = await merger.plan(survivor: keep, retiring: go);
      await foods.save(go);

      await expectLater(
        merger.apply(plan),
        throwsA(
          isA<MergeRefused>().having(
            (MergeRefused e) => e.reason,
            'reason',
            MergeRefusal.writesStillQueued,
          ),
        ),
      );
      expect(
        (await db.select(db.foods).get())
            .firstWhere((FoodRow r) => r.id == 'f-go')
            .isDeleted,
        isFalse,
        reason: 'a refused merge writes nothing',
      );
    });

    test('when a planned meal cannot be converted', () async {
      // "1 pot" against a food measured in grams: nothing says what one pot
      // weighs, and inventing a number would change what somebody planned.
      final (Food keep, Food go) = await twoFoods(
        retiringAmount: 1,
        retiringUnit: Units.item,
      );
      await _logAMeal(db, foodId: 'f-go', servings: 1, logged: false);
      await drainQueue();

      final MergePlan plan = await merger.plan(survivor: keep, retiring: go);
      expect(plan.canProceed, isFalse);

      await expectLater(
        merger.apply(plan),
        throwsA(
          isA<MergeRefused>().having(
            (MergeRefused e) => e.reason,
            'reason',
            MergeRefusal.plannedMealCannotConvert,
          ),
        ),
      );
      expect(
        (await db.select(db.mealPlanEntries).get()).single.refId,
        'f-go',
        reason: 'the plan was left exactly where it was',
      );
    });
  });
}

/// One shopping line against a food.
Future<void> _aShoppingLine(HearthDatabase db, {required String foodId}) async {
  await db
      .into(db.shoppingLists)
      .insertOnConflictUpdate(
        ShoppingListsCompanion.insert(
          id: 'list-1',
          householdId: 'household-1',
          fromDate: DateTime.utc(2026, 9, 7),
          toDate: DateTime.utc(2026, 9, 13),
          status: const Value<String>('draft'),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );
  await db
      .into(db.shoppingListItems)
      .insert(
        ShoppingListItemsCompanion.insert(
          id: 'line-1',
          listId: 'list-1',
          itemKey: 'yogurt',
          name: 'Greek yogurt',
          foodId: Value(foodId),
          sortOrder: const Value<int>(0),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );
}

/// One plan entry against a food, logged or merely planned.
Future<void> _logAMeal(
  HearthDatabase db, {
  required String foodId,
  required double servings,
  required bool logged,
}) async {
  const String dayId = 'day-1';
  await db
      .into(db.mealPlanDays)
      .insertOnConflictUpdate(
        MealPlanDaysCompanion.insert(
          id: dayId,
          userId: 'user-1',
          day: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );
  await db
      .into(db.mealPlanEntries)
      .insert(
        MealPlanEntriesCompanion.insert(
          id: 'entry-$foodId-$servings-$logged',
          dayId: dayId,
          mealSlot: 'breakfast',
          refType: 'food',
          refId: foodId,
          servings: servings,
          isLogged: Value(logged),
          macroSnapshot: Value(
            logged ? '{"label":"Greek yogurt","kcal":100}' : null,
          ),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );
}
