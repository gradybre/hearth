import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:meta/meta.dart';

import '../../domain/text/text_normaliser.dart';
import 'tables.dart';

part 'hearth_database.g.dart';

/// The local SQLite cache (spec §7.1).
///
/// This is a *cache plus a write queue*, not a second source of truth. Reads
/// come from here so cooking and logging work with no network; writes land
/// here first and are replayed against Supabase on reconnect.
///
/// The device holds personal health data, so it relies on OS disk encryption
/// plus the optional biometric app lock. SQLCipher is noted as defence in
/// depth but is explicitly out of v1 scope (spec §8.4).
@DriftDatabase(
  tables: <Type>[
    Recipes,
    RecipeSections,
    RecipeIngredients,
    RecipeSteps,
    RecipeFavorites,
    Collections,
    RecipeCollections,
    Foods,
    FoodServingOptions,
    MealPlanDays,
    MealPlanEntries,
    MacroTargets,
    IngredientMatches,
    CookTimers,
    FoodProfiles,
    Preferences,
    CookSessions,
    RecipePhotos,
    PlanTemplates,
    PendingWrites,
    ShoppingLists,
    ShoppingListItems,
  ],
)
class HearthDatabase extends _$HearthDatabase {
  HearthDatabase() : super(_open());

  /// For tests: an isolated in-memory database.
  HearthDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      // v2 adds remembered ingredient matches (spec §5.3). Nothing else
      // changes, so the existing cache is kept rather than rebuilt.
      if (from < 2) {
        await m.createTable(ingredientMatches);
      }
      // v3 adds favourites and collections (spec §5.2). Additive again — the
      // cached library is untouched, so no re-sync is needed to upgrade.
      if (from < 3) {
        await m.createTable(recipeFavorites);
        await m.createTable(collections);
        await m.createTable(recipeCollections);
      }
      // v4 keeps cook timers across launches (spec §5.2), so a braise started
      // before the app was closed is still counting when it comes back.
      if (from < 4) {
        await m.createTable(cookTimers);
      }
      // v5 remembers small device-local view choices (spec §5.2).
      if (from < 5) {
        await m.createTable(preferences);
      }
      // v6 keeps your place in a cook across launches (spec §5.2).
      if (from < 6) {
        await m.createTable(cookSessions);
      }
      // v7 remembers a recipe's hero photo on this device (spec §5.2).
      if (from < 7) {
        await m.createTable(recipePhotos);
      }
      // v9 caches the food profile, so the generator can read allergies and
      // dislikes offline and without a round trip (spec §5.4).
      if (from < 9) {
        await m.createTable(foodProfiles);
      }
      // v8 ties a timer to its step, so a step can only ever have one.
      if (from < 8) {
        await m.addColumn(cookTimers, cookTimers.stepId);
      }
      // v10 marks a food as one of the household's standing choices, so a
      // recipe line naming the same thing matches itself (spec §5.3).
      if (from < 10) {
        await m.addColumn(foods, foods.isDefault);
      }
      // v11 marks a line as needing no food at all — salt, pepper, a spice —
      // so it stops being counted among the gaps (spec §5.3).
      if (from < 11) {
        await m.addColumn(recipeIngredients, recipeIngredients.needsNoMatch);
        // `food_id` becomes nullable and gains a companion flag. SQLite
        // cannot drop a NOT NULL in place, so the table is rebuilt — which
        // also installs the CHECK that replaces the constraint.
        await m.alterTable(TableMigration(ingredientMatches));
      }
      // v12 lets a food say its zeros are the answer rather than a gap, so
      // the black coffee stops being flagged for ever (spec §5.5).
      if (from < 12) {
        await m.addColumn(foods, foods.isZeroCalorie);
      }
      // v13 is the shopping list (spec §5.7, phase 4). Additive: the cached
      // library and plan are untouched, so no re-sync is needed to upgrade.
      if (from < 13) {
        await m.createTable(shoppingLists);
        await m.createTable(shoppingListItems);
      }
      // v14 is photo sync (spec §5.2, §7.2). Existing rows get a null
      // remotePath, which is exactly the "needs uploading" predicate — so
      // every photo already on this device backfills through the ordinary
      // upload loop with no migration that reads a file or touches a network.
      if (from < 14) {
        await m.addColumn(recipePhotos, recipePhotos.remotePath);
        await m.addColumn(recipePhotos, recipePhotos.syncAttempts);
        await m.addColumn(recipePhotos, recipePhotos.syncError);
        // fileName becomes nullable: a device can know about a photo it has
        // not managed to download.
        await m.alterTable(TableMigration(recipePhotos));
      }
      // v15 is week templates (spec §5.6). Additive.
      if (from < 15) {
        await m.createTable(planTemplates);
      }
      // v16 re-keys remembered ingredient matches: a hyphen is a separator
      // now, so "sun-dried tomatoes" and "sun dried tomatoes" are one key
      // rather than two. Data only — no columns move.
      if (from < 16) {
        await _renormaliseIngredientMatches();
        await _renormaliseShoppingKeys();
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Drift leaves foreign keys off by default; without this the cascade
      // deletes declared on the child tables silently do nothing.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Brings stored ingredient keys into line with [normaliseKey].
  ///
  /// Public so it can be tested: this runs exactly once on a real device with
  /// real data, and a migration that merges the wrong row or trips the unique
  /// key has no second chance.
  @visibleForTesting
  Future<void> renormaliseForV16() async {
    await _renormaliseIngredientMatches();
    await _renormaliseShoppingKeys();
  }

  ///
  /// Done in Dart rather than SQL because sqlite has no regexp_replace, and
  /// because reusing the very function the app matches with is the only way
  /// to be sure the two agree — a hand-written SQL counterpart that drifted
  /// would put this device permanently out of step with the server.
  Future<void> _renormaliseIngredientMatches() async {
    final List<IngredientMatchRow> rows = await select(ingredientMatches).get();

    // Newest answer per key wins, ties broken by id so the result does not
    // depend on row order — the same rule the server migration uses.
    final Map<String, IngredientMatchRow> keep = <String, IngredientMatchRow>{};
    for (final IngredientMatchRow row in rows) {
      final String key = normaliseKey(row.ingredientString);
      if (key.isEmpty) continue;

      final String slot = '${row.householdId}\u0000$key';
      final IngredientMatchRow? held = keep[slot];
      if (held == null ||
          row.updatedAt.isAfter(held.updatedAt) ||
          (row.updatedAt == held.updatedAt && row.id.compareTo(held.id) > 0)) {
        keep[slot] = row;
      }
    }

    await transaction(() async {
      await delete(ingredientMatches).go();
      for (final MapEntry<String, IngredientMatchRow> entry in keep.entries) {
        final IngredientMatchRow row = entry.value;
        await into(ingredientMatches).insert(
          row.copyWith(ingredientString: entry.key.split('\u0000').last),
        );
      }
    });
  }

  /// Keeps an in-flight shopping list mergeable across the key change.
  ///
  /// Lines are merged by [item_key], which for an ingredient with no matched
  /// food is the normalised wording. Left alone, the first rebuild after this
  /// change would see a hyphenated line as brand new and drop its tick, its
  /// on-hand amount and any hand-edited quantity — which is exactly what
  /// merging rather than replacing exists to prevent. A matched line is keyed
  /// by food id and is untouched.
  Future<void> _renormaliseShoppingKeys() async {
    final List<ShoppingItemRow> rows = await select(shoppingListItems).get();
    await transaction(() async {
      for (final ShoppingItemRow row in rows) {
        if (row.foodId != null) continue;
        final String key = normaliseKey(row.itemKey);
        if (key.isEmpty || key == row.itemKey) continue;
        await (update(shoppingListItems)
              ..where(($ShoppingListItemsTable i) => i.id.equals(row.id)))
            .write(ShoppingListItemsCompanion(itemKey: Value<String>(key)));
      }
    });
  }

  static QueryExecutor _open() => driftDatabase(name: 'hearth');
}
