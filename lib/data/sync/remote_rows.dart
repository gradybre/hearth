import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/text/text_normaliser.dart';
import '../local/hearth_database.dart';
import '../mappers/shopping_mapper.dart';
import '../remote/supabase_remote_gateway.dart';

/// Writes records that arrived from the server straight into the local cache.
///
/// Deliberately row-level rather than domain-level. These tables carry values
/// this device must not reinterpret — above all `macro_snapshot`, which is
/// frozen history: what the meal was when it was logged, never what the recipe
/// says today (spec §4). Round-tripping it through the domain would invite
/// exactly the recomputation that rule forbids, so the stored text is copied
/// across verbatim.
class RemoteRows {
  RemoteRows(this._db);

  final HearthDatabase _db;

  // ── Timestamped records, resolved by last-write-wins ──────────────────────

  Future<DateTime?> updatedAtFor(String table, String id) async {
    // Most tables are keyed by id; the food profile is one row per user and
    // keyed that way on both sides. Asking for `id` there would be a query
    // against a column that does not exist.
    final String key = SupabaseRemoteGateway.keyColumns[table] ?? 'id';
    final List<QueryRow> rows = await _db
        .customSelect(
          'select updated_at from $table where $key = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.read<DateTime?>('updated_at');
  }

  Future<void> applyDay(Map<String, Object?> json) => _db
      .into(_db.mealPlanDays)
      .insertOnConflictUpdate(
        MealPlanDayRow(
          id: '${json['id']}',
          userId: '${json['user_id']}',
          day: _date(json['day']),
          notes: json['notes'] as String?,
          updatedAt: _time(json['updated_at']),
        ),
      );

  /// Whether an arriving row says it has been deleted.
  ///
  /// The five record tables soft-delete now (spec §7.1): the row stays on the
  /// server so the deletion can travel, and each device removes its own copy
  /// on the way past. Local storage is a cache of what exists, so there is
  /// nothing here for a tombstone to be useful for.
  static bool _isDeleted(Map<String, Object?> json) =>
      json['is_deleted'] == true;

  Future<void> applyEntry(Map<String, Object?> json) async {
    if (_isDeleted(json)) {
      await (_db.delete(
        _db.mealPlanEntries,
      )..where(($MealPlanEntriesTable e) => e.id.equals('${json['id']}'))).go();
      return;
    }
    await _db
        .into(_db.mealPlanEntries)
        .insertOnConflictUpdate(
          MealPlanEntryRow(
            id: '${json['id']}',
            dayId: '${json['meal_plan_day_id']}',
            mealSlot: '${json['meal_slot']}',
            refType: '${json['ref_type']}',
            refId: '${json['ref_id']}',
            servings: _double(json['servings']) ?? 0,
            isPlanned: json['is_planned'] == true,
            isLogged: json['is_logged'] == true,
            loggedAt: json['logged_at'] == null
                ? null
                : _time(json['logged_at']),
            // Copied as text, never rebuilt: this is the frozen record of what
            // was eaten (spec §4).
            macroSnapshot: json['macro_snapshot'] == null
                ? null
                : jsonEncode(json['macro_snapshot']),
            updatedAt: _time(json['updated_at']),
          ),
        );
  }

  /// A week's targets arriving from another device.
  ///
  /// Resolved on (user, week) rather than on the id. The table is unique on
  /// that pair, and a row written on the other phone carries that phone's own
  /// id — so conflicting on the primary key means an insert, which the unique
  /// key then refuses, and the exception takes the whole table's pull down
  /// with it. New rows derive their id from the pair now, but rows written
  /// before that, or by an older build, still carry a random one.
  Future<void> applyTargets(
    Map<String, Object?> json, {
    required Future<bool> Function(String entityId) hasPendingWrite,
  }) async {
    final String incomingId = '${json['id']}';
    final String userId = '${json['user_id']}';
    final DateTime week = _date(json['week_start_date']);

    final MacroTargetRow? local =
        await (_db.select(_db.macroTargets)..where(
              ($MacroTargetsTable t) =>
                  t.userId.equals(userId) & t.weekStartDate.equals(week),
            ))
            .getSingleOrNull();

    // The pull's own guard asks whether the *incoming* id has an unsent write,
    // and on this table the incoming id is the other phone's — so it cannot
    // see that this phone has its own unsent change to the same week under an
    // id of its own. Resolving on the pair without checking would make that
    // change disappear, which is the one thing the queue exists to prevent.
    if (local != null &&
        local.id != incomingId &&
        await hasPendingWrite(local.id)) {
      return;
    }

    final MacroTargetsCompanion row = MacroTargetsCompanion(
      id: Value<String>(incomingId),
      userId: Value<String>(userId),
      weekStartDate: Value<DateTime>(week),
      kcal: Value<double>(_double(json['kcal']) ?? 0),
      proteinG: Value<double>(_double(json['protein_g']) ?? 0),
      carbG: Value<double>(_double(json['carb_g']) ?? 0),
      fatG: Value<double>(_double(json['fat_g']) ?? 0),
      fiberG: Value<double?>(_double(json['fiber_g'])),
      sodiumMg: Value<double?>(_double(json['sodium_mg'])),
      cholesterolMg: Value<double?>(_double(json['cholesterol_mg'])),
      updatedAt: Value<DateTime>(_time(json['updated_at'])),
    );

    // The same values for the insert and for the update. Written twice, a
    // column added later would land on the way in and never be updated after
    // — a value that silently stops changing.
    await _db
        .into(_db.macroTargets)
        .insert(
          row,
          onConflict: DoUpdate<$MacroTargetsTable, MacroTargetRow>(
            ($MacroTargetsTable _) => row,
            target: <Column<Object>>[
              _db.macroTargets.userId,
              _db.macroTargets.weekStartDate,
            ],
          ),
        );
  }

  Future<void> applyFoodProfile(Map<String, Object?> json) => _db
      .into(_db.foodProfiles)
      .insertOnConflictUpdate(
        FoodProfileRow(
          userId: '${json['user_id']}',
          caloriesPerMealTarget: _double(json['calories_per_meal_target']),
          proteinTargetG: _double(json['protein_target_g']),
          allergies: _joinList(json['allergies']),
          dislikes: _joinList(json['dislikes']),
          dietaryPreferences: _joinList(json['dietary_preferences']),
          preferredMealTypes: _joinList(json['preferred_meal_types']),
          updatedAt: _time(json['updated_at']),
        ),
      );

  /// A Postgres text[] arrives as a list; stored newline-joined to match
  /// [FoodProfileStore].
  static String _joinList(Object? value) => value is List<Object?>
      ? <String>[
          for (final Object? item in value)
            if ('$item'.trim().isNotEmpty) '$item'.trim(),
        ].join('\n')
      : '';

  Future<void> applyCollection(Map<String, Object?> json) async {
    if (_isDeleted(json)) {
      await (_db.delete(
        _db.collections,
      )..where(($CollectionsTable c) => c.id.equals('${json['id']}'))).go();
      return;
    }
    await _db
        .into(_db.collections)
        .insertOnConflictUpdate(
          CollectionRow(
            id: '${json['id']}',
            householdId: '${json['household_id']}',
            name: '${json['name'] ?? ''}',
            sortOrder: _int(json['sort_order']) ?? 0,
            updatedAt: _time(json['updated_at']),
          ),
        );
  }

  /// A menu's provenance arriving from another device (review N08).
  ///
  /// One row per restaurant, so the newest import wins by ordinary
  /// last-write-wins — which is the right answer: whoever read the menu most
  /// recently knows best how old it is.
  Future<void> applyMenuImport(Map<String, Object?> json) async {
    if (_isDeleted(json)) {
      await (_db.delete(
        _db.menuImports,
      )..where(($MenuImportsTable t) => t.id.equals('${json['id']}'))).go();
      return;
    }
    await _db
        .into(_db.menuImports)
        .insertOnConflictUpdate(
          MenuImportRow(
            id: '${json['id']}',
            householdId: '${json['household_id']}',
            restaurantKey: '${json['restaurant_key'] ?? ''}',
            restaurant: '${json['restaurant'] ?? ''}',
            source: json['source'] as String?,
            documentDate: json['document_date'] == null
                ? null
                : _time(json['document_date']),
            itemCount: _int(json['item_count']) ?? 0,
            importedAt: _time(json['imported_at']),
            updatedAt: _time(json['updated_at']),
          ),
        );
  }

  /// A saved week arriving from another device (spec §5.6).
  Future<void> applyPlanTemplate(Map<String, Object?> json) async {
    if (_isDeleted(json)) {
      await (_db.delete(
        _db.planTemplates,
      )..where(($PlanTemplatesTable t) => t.id.equals('${json['id']}'))).go();
      return;
    }
    await _db
        .into(_db.planTemplates)
        .insertOnConflictUpdate(
          PlanTemplateRow(
            id: '${json['id']}',
            userId: '${json['user_id']}',
            name: '${json['name'] ?? ''}',
            // The server column is jsonb, so this arrives decoded; the local
            // column holds the text. Re-encoding beats storing "[object]".
            entries: jsonEncode(json['entries'] ?? const <Object?>[]),
            updatedAt: _time(json['updated_at']),
          ),
        );
  }

  Future<void> applyShoppingList(Map<String, Object?> json) => _db
      .into(_db.shoppingLists)
      .insertOnConflictUpdate(
        ShoppingListRow(
          id: '${json['id']}',
          householdId: '${json['household_id']}',
          fromDate: _date(json['from_date']),
          toDate: _date(json['to_date']),
          status: '${json['status'] ?? 'draft'}',
          updatedAt: _time(json['updated_at']),
        ),
      );

  /// One line of a partner's list.
  ///
  /// Skipped when its list is not here yet, the same guard
  /// [applyIngredientMatch] makes: the foreign key would refuse the row and
  /// take the rest of the table's pull down with it, and the list is one
  /// place ahead in the same pass.
  Future<void> applyShoppingItem(Map<String, Object?> json) async {
    if (_isDeleted(json)) {
      await (_db.delete(
            _db.shoppingListItems,
          )..where(($ShoppingListItemsTable i) => i.id.equals('${json['id']}')))
          .go();
      return;
    }
    final String listId = '${json['shopping_list_id']}';
    final bool haveList =
        await (_db.select(_db.shoppingLists)
              ..where(($ShoppingListsTable l) => l.id.equals(listId)))
            .getSingleOrNull() !=
        null;
    if (!haveList) return;

    await _db
        .into(_db.shoppingListItems)
        .insertOnConflictUpdate(
          ShoppingItemRow(
            id: '${json['id']}',
            listId: listId,
            itemKey: '${json['item_key'] ?? ''}',
            foodId: json['food_id'] == null ? null : '${json['food_id']}',
            name: '${json['raw_name'] ?? ''}',
            plannedCanonical: _double(json['planned_canonical']),
            plannedKind: _text(json['planned_kind']),
            plannedUnit: _text(json['planned_unit']),
            wantedCanonical: _double(json['wanted_canonical']),
            wantedKind: _text(json['wanted_kind']),
            wantedUnit: _text(json['wanted_unit']),
            onHandCanonical: _double(json['on_hand_canonical']),
            onHandKind: _text(json['on_hand_kind']),
            onHandUnit: _text(json['on_hand_unit']),
            checked: json['checked'] == true,
            isManual: json['is_manual'] == true,
            hasUnquantified: json['has_unquantified'] == true,
            storeTag: _text(json['store_tag']),
            sortOrder: _int(json['sort_order']) ?? 0,
            sourceRecipeIds: ShoppingMapper.sourceIdsFromJson(
              json['source_recipe_ids'],
            ),
            // jsonb arrives decoded; the local column holds the text.
            plannedRest: jsonEncode(json['planned_rest'] ?? const <Object?>[]),
            // Absent from a row a phone on an older build wrote. Empty reads
            // as the plan having asked for the whole line, which is what it
            // meant on that build (spec §5.7).
            contributions: jsonEncode(
              json['contributions'] ?? const <Object?>[],
            ),
            updatedAt: _time(json['updated_at']),
          ),
        );
  }

  static String? _text(Object? value) {
    final String text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  /// A remembered answer for an ingredient wording (spec §5.3).
  ///
  /// Upserted on the wording rather than on the id: the id is derived from the
  /// wording now, but a row written before that could still be carrying a
  /// random one, and inserting beside it would break the unique index on a
  /// device that has done nothing wrong.
  Future<void> applyIngredientMatch(
    Map<String, Object?> json, {
    required Future<bool> Function(String entityId) hasPendingWrite,
  }) async {
    final String key = normaliseKey('${json['ingredient_string'] ?? ''}');
    if (key.isEmpty) return;

    final String household = '${json['household_id']}';

    // The same guard `applyTargets` needs, for the same reason. The pull asks
    // whether the *incoming* id has an unsent write, and on this table the
    // incoming id is whatever the server row happens to carry — which for a
    // row written before ids were derived is not the id this phone queued
    // under. Without this, an answer given here and not yet sent is replaced
    // by the one it was correcting, and a tombstone erases it outright.
    final IngredientMatchRow? local =
        await (_db.select(_db.ingredientMatches)..where(
              ($IngredientMatchesTable m) =>
                  m.householdId.equals(household) &
                  m.ingredientString.equals(key),
            ))
            .getSingleOrNull();
    if (local != null &&
        local.id != '${json['id']}' &&
        await hasPendingWrite(local.id)) {
      return;
    }

    if (_isDeleted(json)) {
      // By household and wording, not by id. The insert below deliberately
      // resolves on `(household_id, ingredient_string)` because a local row
      // may still carry a random id rather than the derived one — and a
      // tombstone that matched on the id the insert does not trust would
      // leave the forgotten wording in place, quietly answering ingredients
      // the household said to stop answering.
      await (_db.delete(_db.ingredientMatches)..where(
            ($IngredientMatchesTable m) =>
                m.householdId.equals(household) &
                m.ingredientString.equals(key),
          ))
          .go();
      return;
    }

    // A match naming a food this device has not got is skipped rather than
    // inserted. Foods are pulled before records so this is rare, but the row
    // has a foreign key onto them and a failure here would abort the whole
    // table's pull over one row. Nothing is lost by skipping: a match to a
    // food that is not here is already ignored by the matcher, which only
    // suggests foods the library actually holds.
    final String? foodId = json['food_id'] as String?;
    if (foodId != null) {
      final List<QueryRow> known = await _db
          .customSelect(
            'select 1 from foods where id = ?',
            variables: <Variable<Object>>[Variable<String>(foodId)],
          )
          .get();
      if (known.isEmpty) return;
    }

    await _db
        .into(_db.ingredientMatches)
        .insert(
          IngredientMatchesCompanion.insert(
            id: '${json['id']}',
            householdId: household,
            ingredientString: key,
            foodId: Value<String?>(foodId),
            needsNoMatch: Value<bool>(json['needs_no_match'] == true),
            updatedAt: _time(json['updated_at']),
          ),
          onConflict: DoUpdate(
            (_) => IngredientMatchesCompanion(
              id: Value<String>('${json['id']}'),
              foodId: Value<String?>(foodId),
              needsNoMatch: Value<bool>(json['needs_no_match'] == true),
              updatedAt: Value<DateTime>(_time(json['updated_at'])),
            ),
            target: <Column<Object>>[
              _db.ingredientMatches.householdId,
              _db.ingredientMatches.ingredientString,
            ],
          ),
        );
  }

  // ── Membership, which has no timestamps to compare ────────────────────────

  /// Replaces the local favourites with the server's, keeping any the queue
  /// has not sent yet.
  ///
  /// These tables record only that a pair exists — there is no `updated_at` to
  /// resolve, so the server's set is authoritative except where this device
  /// has an unsent opinion. Dropping that exception would undo a heart tapped
  /// on a train before it reached the server.
  Future<void> replaceFavorites({
    required String userId,
    required Set<String> remoteRecipeIds,
    required Future<bool> Function(String entityId) hasPendingWrite,
    required DateTime now,
  }) async {
    final List<RecipeFavoriteRow> local = await (_db.select(
      _db.recipeFavorites,
    )..where(($RecipeFavoritesTable f) => f.userId.equals(userId))).get();

    for (final RecipeFavoriteRow row in local) {
      if (remoteRecipeIds.contains(row.recipeId)) continue;
      if (await hasPendingWrite('$userId/${row.recipeId}')) continue;
      await (_db.delete(_db.recipeFavorites)..where(
            ($RecipeFavoritesTable f) =>
                f.userId.equals(userId) & f.recipeId.equals(row.recipeId),
          ))
          .go();
    }

    // Same guard as the memberships below: a favourite naming a recipe this
    // device has not got would break the local foreign key and take the whole
    // pull down with it.
    final Set<String> knownRecipes = <String>{
      for (final RecipeRow row in await _db.select(_db.recipes).get()) row.id,
    };

    for (final String recipeId in remoteRecipeIds) {
      if (!knownRecipes.contains(recipeId)) continue;
      await _db
          .into(_db.recipeFavorites)
          .insertOnConflictUpdate(
            RecipeFavoriteRow(
              userId: userId,
              recipeId: recipeId,
              createdAt: now,
            ),
          );
    }
  }

  /// The same reconcile for which recipes are in which cookbook.
  Future<void> replaceMemberships({
    required Set<(String collectionId, String recipeId)> remote,
    required Future<bool> Function(String entityId) hasPendingWrite,
    required DateTime now,
  }) async {
    final List<RecipeCollectionRow> local = await _db
        .select(_db.recipeCollections)
        .get();

    for (final RecipeCollectionRow row in local) {
      final (String, String) pair = (row.collectionId, row.recipeId);
      if (remote.contains(pair)) continue;
      if (await hasPendingWrite('${row.collectionId}/${row.recipeId}')) {
        continue;
      }
      await (_db.delete(_db.recipeCollections)..where(
            ($RecipeCollectionsTable rc) =>
                rc.collectionId.equals(row.collectionId) &
                rc.recipeId.equals(row.recipeId),
          ))
          .go();
    }

    // Only pairs whose two ends are actually here.
    //
    // A cookbook that is deleted now leaves its membership rows behind on the
    // server: the delete is a tombstone rather than a removal, so the cascade
    // that used to take them with it never fires, and their own policy still
    // returns them because it asks about the recipe rather than the parent.
    // The local row is gone and the local cascade took the local memberships
    // with it — so re-inserting those pairs breaks the local foreign key, and
    // the exception escapes the whole pull. Every sync on both phones would
    // fail from then on, for ever, because the orphans never go away.
    //
    // Skipping is the same answer this file already gives for a shopping line
    // whose list has not arrived and a match naming a food this device has
    // not got: a row that cannot be attached to anything waits for the pass
    // that brings its parent, and costs nothing until then.
    final Set<String> knownCollections = <String>{
      for (final CollectionRow row in await _db.select(_db.collections).get())
        row.id,
    };
    final Set<String> knownRecipes = <String>{
      for (final RecipeRow row in await _db.select(_db.recipes).get()) row.id,
    };

    for (final (String collectionId, String recipeId) pair in remote) {
      if (!knownCollections.contains(pair.$1)) continue;
      if (!knownRecipes.contains(pair.$2)) continue;
      await _db
          .into(_db.recipeCollections)
          .insertOnConflictUpdate(
            RecipeCollectionRow(
              collectionId: pair.$1,
              recipeId: pair.$2,
              createdAt: now,
            ),
          );
    }
  }

  /// Server timestamps arrive as ISO text; a date column carries no time.
  static DateTime _date(Object? value) =>
      DateTime.tryParse('$value')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime _time(Object? value) =>
      DateTime.tryParse('$value')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static double? _double(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}
