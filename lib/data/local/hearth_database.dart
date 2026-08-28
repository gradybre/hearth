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
    Foods,
    FoodServingOptions,
    MealPlanDays,
    MealPlanEntries,
    MacroTargets,
    IngredientMatches,
    PendingWrites,
  ],
)
class HearthDatabase extends _$HearthDatabase {
  HearthDatabase() : super(_open());

  /// For tests: an isolated in-memory database.
  HearthDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      // v2 adds remembered ingredient matches (spec §5.3). Nothing else
      // changes, so the existing cache is kept rather than rebuilt.
      if (from < 2) {
        await m.createTable(ingredientMatches);
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
