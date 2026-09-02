import 'dart:convert';

import 'package:drift/drift.dart' show OrderClauseGenerator, OrderingTerm;
import 'package:meta/meta.dart';

import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../local/food_store.dart';
import '../local/hearth_database.dart';
import '../local/recipe_store.dart';
import '../mappers/food_mapper.dart';
import '../mappers/plan_mapper.dart';
import '../mappers/recipe_mapper.dart';
import '../mappers/shopping_mapper.dart';

/// A file, ready to hand to the operating system.
@immutable
class ExportedFile {
  const ExportedFile({required this.name, required this.contents});

  final String name;
  final String contents;

  int get bytes => utf8.encode(contents).length;
}

/// Handing a file to the OS (rule 7).
///
/// An interface so the builder can be exercised without a share sheet, and so
/// `share_plus` is touched in exactly one file.
abstract interface class FileShare {
  Future<void> share(ExportedFile file);
}

/// Everything this household and this person have, as JSON (spec §7.4).
///
/// Cheap insurance and on-brand for a personal tool: the point is that Hearth
/// can be walked away from. It reads the local database rather than the
/// server, which is the same data — the local copy is what sync maintains —
/// and means an export works on a plane.
///
/// **Photos are not included.** They are binary, they would turn a 200 KB
/// share into tens of megabytes, and after Phase 5 they live in the
/// household's bucket anyway. The screen says so rather than leaving it to be
/// discovered.
class DataExport {
  DataExport({
    required HearthDatabase database,
    required RecipeStore recipes,
    required FoodStore foods,
    DateTime Function()? clock,
  }) : _db = database,
       _recipes = recipes,
       _foods = foods,
       _now = clock ?? DateTime.now;

  /// Bumped when the shape changes in a way a reader would care about.
  static const int formatVersion = 1;

  final HearthDatabase _db;
  final RecipeStore _recipes;
  final FoodStore _foods;
  final DateTime Function() _now;

  Future<ExportedFile> build({
    required String householdId,
    required String userId,
  }) async {
    final Map<String, Object?> data = await asJson(
      householdId: householdId,
      userId: userId,
    );
    final DateTime at = _now();
    return ExportedFile(
      name:
          'hearth-${at.year.toString().padLeft(4, '0')}-'
          '${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}.json',
      // Indented on purpose. This is a file a person may open and read, and
      // the few extra kilobytes buy that.
      contents: const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  /// The export as a map, which is the part worth testing.
  Future<Map<String, Object?>> asJson({
    required String householdId,
    required String userId,
  }) async {
    final DateTime at = _now();

    // Deleted records are included deliberately. A soft-deleted recipe is
    // still a recipe you wrote, and an export whose promise is "you are never
    // locked in" should not quietly drop the ones you binned — every log
    // entry pointing at one would otherwise resolve to nothing.
    final List<Recipe> recipes = await _recipes.all(
      householdId: householdId,
      includeDeleted: true,
    );
    final List<Food> foods = await _foods.all(
      householdId: householdId,
      includeDeleted: true,
      includeGlobal: false,
    );

    final List<MealPlanDayRow> days =
        await (_db.select(_db.mealPlanDays)
              ..where(($MealPlanDaysTable d) => d.userId.equals(userId))
              ..orderBy(<OrderClauseGenerator<$MealPlanDaysTable>>[
                ($MealPlanDaysTable d) => OrderingTerm(expression: d.day),
              ]))
            .get();
    final Set<String> dayIds = <String>{
      for (final MealPlanDayRow d in days) d.id,
    };

    final List<MealPlanEntryRow> entries = await _db
        .select(_db.mealPlanEntries)
        .get();

    return <String, Object?>{
      'format': 'hearth-export',
      'version': formatVersion,
      'exported_at': at.toUtc().toIso8601String(),
      'household_id': householdId,
      'user_id': userId,
      'note':
          'Recipe photos are not included. Everything else Hearth holds is '
          'here.',
      'recipes': <Map<String, Object?>>[
        for (final Recipe recipe in recipes)
          RecipeMapper.toJson(recipe, updatedAt: recipe.updatedAt ?? at),
      ],
      'foods': <Map<String, Object?>>[
        for (final Food food in foods)
          FoodMapper.toJson(food, updatedAt: food.updatedAt ?? at),
      ],
      'meal_plan_days': <Map<String, Object?>>[
        for (final MealPlanDayRow day in days)
          PlanMapper.dayToJson(day: day, userId: userId),
      ],
      'meal_plan_entries': <Map<String, Object?>>[
        for (final MealPlanEntryRow entry in entries)
          if (dayIds.contains(entry.dayId)) _entry(entry),
      ],
      'macro_targets': <Map<String, Object?>>[
        for (final MacroTargetRow row in await (_db.select(
          _db.macroTargets,
        )..where(($MacroTargetsTable t) => t.userId.equals(userId))).get())
          <String, Object?>{
            'id': row.id,
            'week_start_date': _dateOnly(row.weekStartDate),
            'kcal': row.kcal,
            'protein_g': row.proteinG,
            'carb_g': row.carbG,
            'fat_g': row.fatG,
          },
      ],
      'collections': <Map<String, Object?>>[
        for (final CollectionRow row
            in await (_db.select(_db.collections)..where(
                  ($CollectionsTable c) => c.householdId.equals(householdId),
                ))
                .get())
          <String, Object?>{
            'id': row.id,
            'name': row.name,
            'sort_order': row.sortOrder,
            'recipe_ids': <String>[
              for (final RecipeCollectionRow m
                  in await (_db.select(_db.recipeCollections)..where(
                        ($RecipeCollectionsTable r) =>
                            r.collectionId.equals(row.id),
                      ))
                      .get())
                m.recipeId,
            ],
          },
      ],
      'favorite_recipe_ids': <String>[
        for (final RecipeFavoriteRow row in await (_db.select(
          _db.recipeFavorites,
        )..where(($RecipeFavoritesTable f) => f.userId.equals(userId))).get())
          row.recipeId,
      ],
      'ingredient_matches': <Map<String, Object?>>[
        for (final IngredientMatchRow row
            in await (_db.select(_db.ingredientMatches)..where(
                  ($IngredientMatchesTable m) =>
                      m.householdId.equals(householdId),
                ))
                .get())
          <String, Object?>{
            'ingredient_string': row.ingredientString,
            'food_id': row.foodId,
            'needs_no_match': row.needsNoMatch,
          },
      ],
      'food_profile': await _profile(userId),
      'shopping_lists': <Map<String, Object?>>[
        for (final ShoppingListRow list
            in await (_db.select(_db.shoppingLists)..where(
                  ($ShoppingListsTable l) => l.householdId.equals(householdId),
                ))
                .get())
          <String, Object?>{
            ...ShoppingMapper.listToJson(list),
            'items': <Map<String, Object?>>[
              for (final ShoppingItemRow item
                  in await (_db.select(_db.shoppingListItems)..where(
                        ($ShoppingListItemsTable i) => i.listId.equals(list.id),
                      ))
                      .get())
                ShoppingMapper.itemToJson(item),
            ],
          },
      ],
    };
  }

  /// A logged entry carries its frozen snapshot **verbatim**.
  ///
  /// Copied as stored rather than recomputed from the recipe as it stands
  /// today. That is the §4 non-negotiable, and an export that quietly
  /// recalculated it would be a record of a past that never happened.
  Map<String, Object?> _entry(MealPlanEntryRow entry) => <String, Object?>{
    'id': entry.id,
    'meal_plan_day_id': entry.dayId,
    'meal_slot': entry.mealSlot,
    'ref_type': entry.refType,
    'ref_id': entry.refId,
    'servings': entry.servings,
    'is_planned': entry.isPlanned,
    'is_logged': entry.isLogged,
    'logged_at': entry.loggedAt?.toUtc().toIso8601String(),
    'macro_snapshot': entry.macroSnapshot == null
        ? null
        : jsonDecode(entry.macroSnapshot!),
  };

  Future<Map<String, Object?>?> _profile(String userId) async {
    final FoodProfileRow? row =
        await (_db.select(_db.foodProfiles)
              ..where(($FoodProfilesTable p) => p.userId.equals(userId)))
            .getSingleOrNull();
    if (row == null) return null;
    return <String, Object?>{
      'calories_per_meal_target': row.caloriesPerMealTarget,
      'protein_target_g': row.proteinTargetG,
      'preferred_meal_types': row.preferredMealTypes,
      'dietary_preferences': row.dietaryPreferences,
      'dislikes': row.dislikes,
      'allergies': row.allergies,
    };
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
