import 'package:drift/drift.dart';

import '../../domain/foods/food_merge.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
import 'food_repository.dart';
import 'ingredient_match_repository.dart';
import 'plan_repository.dart';
import 'recipe_repository.dart';
import 'shopping_repository.dart';

/// Why a merge cannot go ahead.
enum MergeRefusal {
  /// One of the two foods has writes the other phone has not seen yet.
  ///
  /// Merging now would race them: the partner's device could receive the
  /// retirement before the edit it supersedes, and the edit would land on a
  /// food that no longer exists there.
  writesStillQueued,

  /// A planned meal's serving cannot be converted, so the plan would come out
  /// meaning a different amount of food.
  plannedMealCannotConvert,
}

class MergeRefused implements Exception {
  const MergeRefused(this.reason);

  final MergeRefusal reason;

  @override
  String toString() => 'MergeRefused(${reason.name})';
}

/// Merging two foods that are the same thing (review N05).
///
/// Reads are done here, directly, because the question — "what points at this
/// food" — crosses four tables and belongs to none of them. **Writes go
/// through the repository that owns each record**, so every change is
/// persisted and queued for sync exactly the way an ordinary edit would be;
/// a merge that wrote rows itself would be a second, untested way to save
/// every one of them.
class FoodMergeRepository {
  FoodMergeRepository({
    required HearthDatabase database,
    required FoodRepository foods,
    required RecipeRepository recipes,
    required IngredientMatchRepository matches,
    required PlanRepository plan,
    required ShoppingRepository shopping,
    required PendingWriteStore queue,
  }) : _db = database,
       _foods = foods,
       _recipes = recipes,
       _matches = matches,
       _plan = plan,
       _shopping = shopping,
       _queue = queue;

  final HearthDatabase _db;
  final FoodRepository _foods;
  final RecipeRepository _recipes;
  final IngredientMatchRepository _matches;
  final PlanRepository _plan;
  final ShoppingRepository _shopping;
  final PendingWriteStore _queue;

  /// What merging [retiring] into [survivor] would do. Writes nothing.
  Future<MergePlan> plan({
    required Food survivor,
    required Food retiring,
  }) async {
    // The survivor as it *will* be, not as it is: whether a recipe line still
    // counts depends on the servings the merge is about to give it, and
    // asking the old survivor would strand lines the merge would have saved.
    final Food after = MergePlan.build(
      survivor: survivor,
      retiring: retiring,
      recipeLines: 0,
      stranded: const <StrandedLine>[],
      plannedEntries: const <({String id, double servings})>[],
      shoppingLines: 0,
      rememberedMatches: 0,
      loggedMeals: 0,
    ).merged;

    int counted = 0;
    final List<StrandedLine> stranded = <StrandedLine>[];
    for (final Recipe recipe in await _recipes.all()) {
      for (final RecipeIngredient line in recipe.allIngredients) {
        if (line.foodId != retiring.id) continue;
        final IngredientMacros part = MacroCalculator.forIngredient(
          line,
          food: after,
        );
        if (part.status == IngredientMacroStatus.unconvertible) {
          stranded.add(
            StrandedLine(
              recipeId: recipe.id,
              recipeTitle: recipe.title,
              ingredientName: line.name,
              unitLabel: line.quantity?.preferredUnit?.label ?? 'that unit',
            ),
          );
        } else {
          counted++;
        }
      }
    }

    final List<MealPlanEntryRow> entries = await _entriesFor(retiring.id);

    return MergePlan.build(
      survivor: survivor,
      retiring: retiring,
      recipeLines: counted,
      stranded: stranded,
      plannedEntries: <({String id, double servings})>[
        for (final MealPlanEntryRow row in entries)
          if (!row.isLogged) (id: row.id, servings: row.servings),
      ],
      shoppingLines: await _shoppingLineIds(retiring.id)
          .then((List<String> ids) => ids.length),
      rememberedMatches: await _matchStrings(retiring.id)
          .then((List<String> all) => all.length),
      loggedMeals: entries.where((MealPlanEntryRow r) => r.isLogged).length,
      // `merged` is recomputed from the same inputs, so this stays the plan
      // the caller was shown.
    );
  }

  /// Applies [plan], or throws [MergeRefused] without writing anything.
  ///
  /// One transaction: a merge that stopped half way would leave references
  /// pointing at a food that had already been retired, which is worse than
  /// either state on its own.
  Future<void> apply(MergePlan plan) async {
    if (!plan.canProceed) {
      throw const MergeRefused(MergeRefusal.plannedMealCannotConvert);
    }
    // Checked here rather than only when the screen was drawn: the sync
    // engine runs on its own schedule and the answer can change while
    // somebody is reading.
    if (await _queue.hasPendingFor(plan.survivor.id) ||
        await _queue.hasPendingFor(plan.retiring.id)) {
      throw const MergeRefused(MergeRefusal.writesStillQueued);
    }

    await _db.transaction(() async {
      await _foods.save(plan.merged);

      for (final Recipe recipe in await _recipes.all()) {
        if (!recipe.allIngredients.any(
          (RecipeIngredient i) => i.foodId == plan.retiring.id,
        )) {
          continue;
        }
        await _recipes.save(_repointed(recipe, plan));
      }

      for (final String wording in await _matchStrings(plan.retiring.id)) {
        await _matches.remember(
          ingredientString: wording,
          foodId: plan.survivor.id,
        );
      }

      for (final String id in await _shoppingLineIds(plan.retiring.id)) {
        await _shopping.repointFood(lineId: id, foodId: plan.survivor.id);
      }

      for (final PlannedMealMove move in plan.plannedMeals) {
        // Guarded inside the statement: this list was counted when the review
        // was drawn, and a meal logged while somebody was reading it must not
        // have its reference and portion rewritten. The update matches no row
        // in that case and the entry keeps pointing at the retired food,
        // which is soft-deleted and still resolves through its snapshot.
        await _plan.repointUnloggedEntry(
          entryId: move.entryId,
          refId: plan.survivor.id,
          servings: move.toServings!,
        );
      }

      // Last, and only once every live reference has been moved — §7.5's
      // "soft-delete superseded definitions only after their live references
      // are safely handled". Logged meals still point here, which is exactly
      // why a soft delete and not a real one.
      await _foods.delete(plan.retiring.id);
    });
  }

  /// [recipe] with every line pointing at the retired food moved across.
  static Recipe _repointed(Recipe recipe, MergePlan plan) => recipe.copyWith(
    sections: <RecipeSection>[
      for (final RecipeSection section in recipe.sections)
        section.copyWith(
          ingredients: <RecipeIngredient>[
            for (final RecipeIngredient line in section.ingredients)
              if (line.foodId == plan.retiring.id)
                line.copyWith(foodId: plan.survivor.id)
              else
                line,
          ],
        ),
    ],
  );

  Future<List<MealPlanEntryRow>> _entriesFor(String foodId) =>
      (_db.select(_db.mealPlanEntries)..where(
            ($MealPlanEntriesTable t) =>
                t.refType.equals('food') & t.refId.equals(foodId),
          ))
          .get();

  Future<List<String>> _shoppingLineIds(String foodId) async =>
      (await (_db.select(_db.shoppingListItems)
                ..where(($ShoppingListItemsTable t) => t.foodId.equals(foodId)))
              .get())
          .map((ShoppingItemRow r) => r.id)
          .toList(growable: false);

  Future<List<String>> _matchStrings(String foodId) async =>
      (await (_db.select(_db.ingredientMatches)
                ..where(($IngredientMatchesTable t) => t.foodId.equals(foodId)))
              .get())
          .map((IngredientMatchRow r) => r.ingredientString)
          .toList(growable: false);
}
