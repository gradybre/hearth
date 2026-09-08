import 'dart:convert';

import 'package:drift/drift.dart' show OrderClauseGenerator, OrderingTerm;
import 'package:meta/meta.dart';

import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week_template.dart';
import '../local/food_store.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
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
  ///
  /// 2 adds the manifest, the referenced global definitions, the three minor
  /// targets and the saved weeks — all of which a v1 reader simply will not
  /// find, which is the whole reason this is a number rather than a habit.
  static const int formatVersion = 2;

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
  ///
  /// Read inside one transaction. Every section used to be its own query, so
  /// a sync pass landing halfway through could leave the file holding an
  /// entry whose day had not been written yet — a file that fails its own
  /// reference check for no reason anybody could reconstruct afterwards.
  Future<Map<String, Object?>> asJson({
    required String householdId,
    required String userId,
  }) => _db.transaction(() => _read(householdId: householdId, userId: userId));

  Future<Map<String, Object?>> _read({
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
    // What the household owns. What it merely points at is fetched further
    // down, by name, once there is a list of names — reading the whole global
    // catalogue to keep six rows out of it would be loading somebody else's
    // library, with its serving options, on every export.
    final List<Food> owned = await _foods.all(
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

    final List<MealPlanEntryRow> entries = <MealPlanEntryRow>[
      for (final MealPlanEntryRow entry
          in await _db.select(_db.mealPlanEntries).get())
        if (dayIds.contains(entry.dayId)) entry,
    ];

    final List<PlanTemplateRow> templates = await (_db.select(
      _db.planTemplates,
    )..where(($PlanTemplatesTable t) => t.userId.equals(userId))).get();

    final List<CollectionRow> collections = await (_db.select(
      _db.collections,
    )..where(($CollectionsTable c) => c.householdId.equals(householdId))).get();
    final Map<String, List<String>> collectionRecipes =
        <String, List<String>>{};
    for (final RecipeCollectionRow m
        in await _db.select(_db.recipeCollections).get()) {
      (collectionRecipes[m.collectionId] ??= <String>[]).add(m.recipeId);
    }

    final List<IngredientMatchRow> matches =
        await (_db.select(_db.ingredientMatches)..where(
              ($IngredientMatchesTable m) => m.householdId.equals(householdId),
            ))
            .get();

    final List<String> favorites = <String>[
      for (final RecipeFavoriteRow row in await (_db.select(
        _db.recipeFavorites,
      )..where(($RecipeFavoritesTable f) => f.userId.equals(userId))).get())
        row.recipeId,
    ];

    final List<MacroTargetRow> targets = await (_db.select(
      _db.macroTargets,
    )..where(($MacroTargetsTable t) => t.userId.equals(userId))).get();

    // Decoded by the domain's own reader rather than by a second one written
    // here. A parallel decoder knowing the key names is a decoder that stops
    // knowing them: rename a field on `TemplateEntry` and this one yields
    // nothing, silently, and the manifest quietly stops seeing every
    // reference a saved week makes.
    final List<TemplateEntry> templateEntries = <TemplateEntry>[
      for (final PlanTemplateRow template in templates)
        ...WeekTemplate.decodeEntries(template.entries),
    ];

    // Which food definitions the file points at, from every direction it can
    // point from. A referenced global joins the export; a reference to
    // nothing at all is named in the manifest rather than left to be
    // discovered by whatever tries to read the file next.
    final Set<String> foodRefs = <String>{
      for (final Recipe recipe in recipes)
        for (final RecipeSection section in recipe.sections)
          for (final RecipeIngredient ingredient in section.ingredients)
            if (ingredient.foodId case final String id) id,
      for (final MealPlanEntryRow entry in entries)
        if (entry.refType == 'food') entry.refId,
      for (final IngredientMatchRow match in matches)
        if (match.foodId case final String id) id,
      for (final TemplateEntry entry in templateEntries)
        if (entry.refType == PlanRefType.food) entry.refId,
    };
    final Set<String> recipeRefs = <String>{
      for (final MealPlanEntryRow entry in entries)
        if (entry.refType == 'recipe') entry.refId,
      // The collections this file actually contains, not every membership row
      // the device happens to hold. A row left behind for a collection that
      // is not in the export would otherwise be reported as a missing
      // reference — a false alarm in the one field whose whole job is to be
      // believed.
      for (final CollectionRow collection in collections)
        ...?collectionRecipes[collection.id],
      ...favorites,
      for (final TemplateEntry entry in templateEntries)
        if (entry.refType == PlanRefType.recipe) entry.refId,
    };

    // A referenced global joins the export, marked as somebody else's
    // definition. Closure, not a copy of the world: an unreferenced global
    // stays where it is, because the catalogue would dwarf what is actually
    // yours and exporting it would not make it yours either.
    final Set<String> ownedIds = <String>{
      for (final Food food in owned) food.id,
    };
    final List<Food> exportedFoods = <Food>[
      ...owned,
      for (final Food food in await _foods.byIds(foodRefs.difference(ownedIds)))
        if (food.isGlobal) food,
    ];

    final Set<String> exportedFoodIds = <String>{
      for (final Food food in exportedFoods) food.id,
    };
    final Set<String> exportedRecipeIds = <String>{
      for (final Recipe recipe in recipes) recipe.id,
    };
    final List<String> missing = <String>[
      for (final String id
          in foodRefs.difference(exportedFoodIds).toList()..sort())
        'food $id',
      for (final String id
          in recipeRefs.difference(exportedRecipeIds).toList()..sort())
        'recipe $id',
    ];

    // A queue with anything in it is proof the server does not have
    // everything this file does — which makes "everything Hearth holds" a
    // claim about a phone rather than about an account, and worth saying out
    // loud rather than leaving to be assumed.
    final int unsent = await PendingWriteStore(_db).count();

    final List<ShoppingListRow> lists =
        await (_db.select(_db.shoppingLists)..where(
              ($ShoppingListsTable l) => l.householdId.equals(householdId),
            ))
            .get();
    final Set<String> listIds = <String>{
      for (final ShoppingListRow list in lists) list.id,
    };
    final List<ShoppingItemRow> shoppingItems = <ShoppingItemRow>[
      for (final ShoppingItemRow item
          in await _db.select(_db.shoppingListItems).get())
        if (listIds.contains(item.listId)) item,
    ];

    return <String, Object?>{
      'format': 'hearth-export',
      'version': formatVersion,
      'exported_at': at.toUtc().toIso8601String(),
      'household_id': householdId,
      'user_id': userId,
      'note':
          'Recipe photos are not included. See the manifest for what else is '
          'not, and for whether this device had sent everything when the file '
          'was made.',
      'recipes': <Map<String, Object?>>[
        for (final Recipe recipe in recipes)
          RecipeMapper.toJson(recipe, updatedAt: recipe.updatedAt ?? at),
      ],
      'foods': <Map<String, Object?>>[
        for (final Food food in exportedFoods)
          <String, Object?>{
            ...FoodMapper.toJson(food, updatedAt: food.updatedAt ?? at),
            // Somebody else's definition, included because this file points
            // at it. Holding a copy is not authority to edit the original,
            // and a reader that treats it as the household's own would be
            // wrong about who it belongs to.
            'is_global': food.isGlobal,
          },
      ],
      'meal_plan_days': <Map<String, Object?>>[
        for (final MealPlanDayRow day in days)
          PlanMapper.dayToJson(day: day, userId: userId),
      ],
      'meal_plan_entries': <Map<String, Object?>>[
        for (final MealPlanEntryRow entry in entries) _entry(entry),
      ],
      'macro_targets': <Map<String, Object?>>[
        for (final MacroTargetRow row in targets)
          <String, Object?>{
            'id': row.id,
            'week_start_date': _dateOnly(row.weekStartDate),
            'kcal': row.kcal,
            'protein_g': row.proteinG,
            'carb_g': row.carbG,
            'fat_g': row.fatG,
            // All seven. Fibre, sodium and cholesterol were lifted out of the
            // deferred list deliberately (§5.6), and dropping them here loses
            // a decision somebody made — silently, and only noticeably later.
            // Null is a real answer: it means the Daily Value, not "no
            // target", so it is written rather than omitted.
            'fiber_g': row.fiberG,
            'sodium_mg': row.sodiumMg,
            'cholesterol_mg': row.cholesterolMg,
          },
      ],
      // A week somebody built and kept. Not exported at all before this.
      'plan_templates': <Map<String, Object?>>[
        for (final PlanTemplateRow row in templates)
          <String, Object?>{
            'id': row.id,
            'name': row.name,
            // Decoded, like the frozen snapshot below: this is a file a
            // person may open, and a string holding JSON is not readable.
            'entries': _decodeList(row.entries),
          },
      ],
      'collections': <Map<String, Object?>>[
        for (final CollectionRow row in collections)
          <String, Object?>{
            'id': row.id,
            'name': row.name,
            'sort_order': row.sortOrder,
            'recipe_ids': collectionRecipes[row.id] ?? const <String>[],
          },
      ],
      'favorite_recipe_ids': favorites,
      'ingredient_matches': <Map<String, Object?>>[
        for (final IngredientMatchRow row in matches)
          <String, Object?>{
            'ingredient_string': row.ingredientString,
            'food_id': row.foodId,
            'needs_no_match': row.needsNoMatch,
          },
      ],
      'food_profile': await _profile(userId),
      'shopping_lists': <Map<String, Object?>>[
        for (final ShoppingListRow list in lists)
          <String, Object?>{
            ...ShoppingMapper.listToJson(list),
            'items': <Map<String, Object?>>[
              for (final ShoppingItemRow item in shoppingItems)
                if (item.listId == list.id) ShoppingMapper.itemToJson(item),
            ],
          },
      ],
      // What is in the file, what is not, and whether it is all of it.
      //
      // The file used to open with "everything else Hearth holds is here",
      // which was false in five separate ways at once and was the first thing
      // a reader saw. A count somebody can check against beats a sentence
      // nobody can.
      'manifest': <String, Object?>{
        'schema_version': formatVersion,
        'exported_at': at.toUtc().toIso8601String(),
        'scope': <String, Object?>{
          'household_id': householdId,
          'user_id': userId,
        },
        'counts': <String, Object?>{
          'recipes': recipes.length,
          'foods': exportedFoods.length,
          'global_foods_referenced': exportedFoods.length - owned.length,
          'meal_plan_days': days.length,
          'meal_plan_entries': entries.length,
          'macro_targets': targets.length,
          'plan_templates': templates.length,
          'collections': collections.length,
          'favorite_recipes': favorites.length,
          'ingredient_matches': matches.length,
          'shopping_lists': lists.length,
          'shopping_items': shoppingItems.length,
        },
        'excluded': <String>[
          'Recipe photos. The file names them where a recipe has one, which '
              'is a reference and not a backup.',
          'The global food catalogue, apart from the definitions this file '
              'points at.',
          'Anybody else\'s plans, logs, targets, favourites or food profile.',
        ],
        // Named rather than hidden. A reference to something that is not here
        // is a fact about the file, and the alternative is a file that looks
        // whole and is not.
        'missing_references': missing,
        // A claim about an account, not about a phone. Anything still in the
        // outbox means the server has less than this file does, so this file
        // cannot be called complete without saying which way it is wrong.
        'complete': unsent == 0 && missing.isEmpty,
        'note': unsent == 0
            ? (missing.isEmpty
                  ? 'This device had sent everything it had when the file was '
                        'made.'
                  : 'Some records point at things this device does not hold. '
                        'They are listed above.')
            : '\$unsent ${unsent == 1 ? 'change has' : 'changes have'} not '
                  'been sent to '
                  'the server when this file was made, so the server holds '
                  'less than this file does.',
      },
    };
  }

  /// A stored JSON list, decoded, or an empty list if it is not one.
  ///
  /// Tolerant on purpose: a template written by an older build is still
  /// somebody's saved week, and refusing the whole export over one row that
  /// will not parse would be the wrong trade by a distance.
  static List<Object?> _decodeList(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is List ? decoded : const <Object?>[];
    } on FormatException {
      return const <Object?>[];
    }
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
