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
    EditorDrafts,
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
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      // v26 keeps an editor's work across an interruption (review N01).
      // Additive, device-local, and never synced: a half-typed recipe is a
      // fact about this phone rather than about the household.
      if (from < 26) {
        await m.createTable(editorDrafts);
      }
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
        await _addColumnIfMissing(m, cookTimers, cookTimers.stepId);
      }
      // v10 marks a food as one of the household's standing choices, so a
      // recipe line naming the same thing matches itself (spec §5.3).
      if (from < 10) {
        await _addColumnIfMissing(m, foods, foods.isDefault);
      }
      // v11 marks a line as needing no food at all — salt, pepper, a spice —
      // so it stops being counted among the gaps (spec §5.3).
      if (from < 11) {
        await _addColumnIfMissing(
          m,
          recipeIngredients,
          recipeIngredients.needsNoMatch,
        );
        // `food_id` becomes nullable and gains a companion flag. SQLite
        // cannot drop a NOT NULL in place, so the table is rebuilt — which
        // also installs the CHECK that replaces the constraint.
        await m.alterTable(TableMigration(ingredientMatches));
      }
      // v12 lets a food say its zeros are the answer rather than a gap, so
      // the black coffee stops being flagged for ever (spec §5.5).
      if (from < 12) {
        await _addColumnIfMissing(m, foods, foods.isZeroCalorie);
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
        await _addColumnIfMissing(m, recipePhotos, recipePhotos.remotePath);
        await _addColumnIfMissing(m, recipePhotos, recipePhotos.syncAttempts);
        await _addColumnIfMissing(m, recipePhotos, recipePhotos.syncError);
        // Added here as well as in v17, because the alterTable below rebuilds
        // this table from today's schema and would otherwise copy from a
        // source missing a column it expects.
        await _addColumnIfMissing(m, recipePhotos, recipePhotos.attemptedPath);
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
      // v17 answers a code review of v14 and v16. A photo row remembers which
      // object its last failed download was for, so a replacement that keeps
      // failing can be given up on without losing the old file; a shopping
      // line keeps every planned amount rather than the first; and lines the
      // v16 re-key left sharing a key are merged, since two rows with one key
      // would derive one id and refuse the next save.
      if (from < 17) {
        await _addColumnIfMissing(m, recipePhotos, recipePhotos.attemptedPath);
        await _addColumnIfMissing(
          m,
          shoppingListItems,
          shoppingListItems.plannedRest,
        );
        await _mergeDuplicateShoppingKeys();
      }
      // v18 lets a food carry the Walmart product actually bought, so the
      // shopping export can fill a basket instead of opening a search
      // (spec §5.7). Additive.
      if (from < 18) {
        await _addColumnIfMissing(m, foods, foods.walmartItemId);
        await _addColumnIfMissing(m, foods, foods.packCanonical);
        await _addColumnIfMissing(m, foods, foods.packKind);
        await _addColumnIfMissing(m, foods, foods.packUnit);
      }
      // v19 carries fibre, sodium and cholesterol on a serving (spec §5.6).
      // Additive, and nullable — an existing serving has never been asked
      // about them, which is exactly what null says.
      if (from < 19) {
        await _addColumnIfMissing(
          m,
          foodServingOptions,
          foodServingOptions.fiberG,
        );
        await _addColumnIfMissing(
          m,
          foodServingOptions,
          foodServingOptions.sodiumMg,
        );
        await _addColumnIfMissing(
          m,
          foodServingOptions,
          foodServingOptions.cholesterolMg,
        );
      }
      // v20 lets a recipe be one you order rather than one you cook, so a
      // restaurant meal can be planned and logged without being shopped for
      // (spec §5.2). Additive, and defaulted to what every existing recipe is.
      if (from < 20) {
        await _addColumnIfMissing(m, recipes, recipes.kind);
      }
      // v21 remembers where an item sits on a restaurant's menu, so the
      // builder can lay it out the way the restaurant does (spec §5.2).
      // Additive and nullable — nothing already saved is off a menu.
      if (from < 21) {
        await _addColumnIfMissing(m, foods, foods.menuGroup);
        await _addColumnIfMissing(m, foods, foods.menuOrder);
      }
      // v22 lets a week carry targets for fibre, sodium and cholesterol
      // (spec §5.6). Additive and nullable — a week with none falls back to
      // the Daily Value, which is what every existing week now does.
      if (from < 22) {
        await _addColumnIfMissing(m, macroTargets, macroTargets.fiberG);
        await _addColumnIfMissing(m, macroTargets, macroTargets.sodiumMg);
        await _addColumnIfMissing(m, macroTargets, macroTargets.cholesterolMg);
      }
      // v23 lets a food be a modifier — a menu row a chain publishes as a
      // deduction (spec §5.2). Additive, and false for everything already
      // saved, which is what every one of them is.
      if (from < 23) {
        await _addColumnIfMissing(m, foods, foods.isModifier);
        await _addColumnIfMissing(
          m,
          foodServingOptions,
          foodServingOptions.isModifier,
        );
      }
      // v24 caches a recipe's sketch icon (spec §5.2). Additive and nullable:
      // no icon is the ordinary state, and every recipe saved before today is
      // in it until something draws one.
      if (from < 24) {
        await _addColumnIfMissing(m, recipes, recipes.iconSvg);
      }
      // v25 gives a failed write a time to wait until. Without one a refusal
      // was retried on every pass for ever, and passes are triggered by local
      // writes — so somebody typing a shopping list produced several a second
      // (spec §7.1).
      if (from < 25) {
        await _addColumnIfMissing(
          m,
          pendingWrites,
          pendingWrites.nextAttemptAt,
        );
        // And the counter starts again, because it did not mean this before.
        //
        // Until now `attempts` was incremented on every failed pass and read
        // by nothing, and passes fire on every local write — so one bad
        // afternoon while somebody was typing drove a write's count into the
        // dozens. Carried across, every one of those rows would already be
        // over the new cap and would strand on the first pass after
        // upgrading, without being tried once, including the many that would
        // now succeed. The old number counted passes since a failure; the new
        // one counts tries.
        await customStatement('UPDATE pending_writes SET attempts = 0');
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Drift leaves foreign keys off by default; without this the cascade
      // deletes declared on the child tables silently do nothing.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Adds [column], treating "it is already there" as success.
  ///
  /// Migrations here are not as ordered as they look. v14 ends by recreating
  /// `recipe_photos` with `alterTable`, which rebuilds it from the schema **as
  /// it stands today** — so it silently creates columns belonging to later
  /// versions. A later step then adds one of those again, the upgrade dies
  /// partway, and `user_version` never advances: every launch after that
  /// replays the same failing step and the app can no longer open its own
  /// database. That put "duplicate column name: remote_path" on a phone.
  ///
  /// Asked by trying, never by reading. A query issued inside `onUpgrade`
  /// waits for the migration to finish while the migration waits for the
  /// query, which does not fail — it simply sits there.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    try {
      await m.addColumn(table, column);
    } on Object catch (error) {
      if (!'$error'.toLowerCase().contains('duplicate column')) rethrow;
    }
  }

  /// Brings stored ingredient keys into line with [normaliseKey].
  ///
  /// Public so it can be tested: this runs exactly once on a real device with
  /// real data, and a migration that merges the wrong row or trips the unique
  /// key has no second chance.
  @visibleForTesting
  Future<void> renormaliseForV16() async {
    await _renormaliseIngredientMatches();
    await _renormaliseShoppingKeys();
    await _mergeDuplicateShoppingKeys();
  }

  /// Leaves one row per (list, key), keeping the newest.
  ///
  /// The v16 re-key could make two unmatched lines in one list share a key —
  /// "sun-dried tomatoes" and "sun dried tomatoes" were distinct before it.
  /// The local table has no unique index to object, but the ids are derived
  /// from the key, so the next save would compute one id for both rows and
  /// fail on the primary key. Newest wins, ties by id, as everywhere else.
  Future<void> _mergeDuplicateShoppingKeys() async {
    final List<ShoppingItemRow> rows = await select(shoppingListItems).get();
    final Map<String, ShoppingItemRow> keep = <String, ShoppingItemRow>{};
    for (final ShoppingItemRow row in rows) {
      final String slot = '${row.listId}\u0000${row.itemKey}';
      final ShoppingItemRow? held = keep[slot];
      if (held == null ||
          row.updatedAt.isAfter(held.updatedAt) ||
          (row.updatedAt == held.updatedAt && row.id.compareTo(held.id) > 0)) {
        keep[slot] = row;
      }
    }
    if (keep.length == rows.length) return;

    final Set<String> keepIds = <String>{
      for (final ShoppingItemRow r in keep.values) r.id,
    };
    await transaction(() async {
      for (final ShoppingItemRow row in rows) {
        if (keepIds.contains(row.id)) continue;
        await (delete(
          shoppingListItems,
        )..where(($ShoppingListItemsTable i) => i.id.equals(row.id))).go();
      }
    });
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
