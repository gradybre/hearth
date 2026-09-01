import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
    PendingWrites,
  ],
)
class HearthDatabase extends _$HearthDatabase {
  HearthDatabase() : super(_open());

  /// For tests: an isolated in-memory database.
  HearthDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

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
    },
    beforeOpen: (OpeningDetails details) async {
      // Drift leaves foreign keys off by default; without this the cascade
      // deletes declared on the child tables silently do nothing.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _open() => driftDatabase(name: 'hearth');
}
