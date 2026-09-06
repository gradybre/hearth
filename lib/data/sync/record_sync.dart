import '../local/pending_write_store.dart';
import '../local/preference_store.dart';
import '../remote/remote_gateway.dart';
import 'remote_rows.dart';
import 'sync_checkpoints.dart';
import 'sync_engine.dart';
import 'sync_scope.dart';

/// Brings down the flat tables: plans, logs, targets, cookbooks, and the
/// household's remembered ingredient answers (spec §7.1).
///
/// Recipes and foods need whole-aggregate handling and have their own path.
/// Everything else is one row per record, which makes this the ordinary case
/// rather than the interesting one.
class RecordSync {
  RecordSync({
    required SyncEngine engine,
    required RemoteRows rows,
    required PendingWriteStore queue,
    required PreferenceStore preferences,
    required SyncScope Function() scope,
  }) : _engine = engine,
       _rows = rows,
       _queue = queue,
       _checkpoints = SyncCheckpoints(preferences: preferences, scope: scope);

  /// Same reasoning as the library's: overlap rather than risk a gap.
  static const Duration overlap = Duration(minutes: 1);

  final SyncEngine _engine;
  final RemoteRows _rows;
  final PendingWriteStore _queue;
  final SyncCheckpoints _checkpoints;

  Future<PullResult> pull() async {
    int applied = 0;
    int skipped = 0;
    bool offline = false;

    // Captured once, before the first request. These tables are one person's
    // plan and one person's logs; half of two people's is neither.
    final SyncScope scope = _checkpoints.current;

    // Days before entries: an entry references its day, and a foreign key
    // does not care that the day is two milliseconds behind.
    for (final ({
          String table,
          Future<void> Function(Map<String, Object?>) apply,
        })
        spec
        in <
          ({String table, Future<void> Function(Map<String, Object?>) apply})
        >[
          (table: 'meal_plan_days', apply: _rows.applyDay),
          (table: 'meal_plan_entries', apply: _rows.applyEntry),
          (table: 'macro_targets', apply: _rows.applyTargets),
          (table: 'collections', apply: _rows.applyCollection),
          (table: 'food_profiles', apply: _rows.applyFoodProfile),
          (table: 'plan_templates', apply: _rows.applyPlanTemplate),
          // After foods: a match points at one, and a foreign key does not
          // care that the food arrived two milliseconds earlier.
          (table: 'ingredient_matches', apply: _rows.applyIngredientMatch),
          // The list before its lines, for the foreign key.
          (table: 'shopping_lists', apply: _rows.applyShoppingList),
          (table: 'shopping_list_items', apply: _rows.applyShoppingItem),
        ]) {
      final PullResult result = await _pullTable(scope, spec.table, spec.apply);
      applied += result.applied;
      skipped += result.skipped;
      offline = offline || result.stoppedBecauseOffline;
      if (result.abandonedScope) {
        return PullResult(
          applied: applied,
          skipped: skipped,
          abandonedScope: true,
        );
      }
    }

    if (!offline) offline = !await _pullMemberships(scope);

    return PullResult(
      applied: applied,
      skipped: skipped,
      stoppedBecauseOffline: offline,
    );
  }

  Future<PullResult> _pullTable(
    SyncScope scope,
    String table,
    Future<void> Function(Map<String, Object?> json) apply,
  ) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final DateTime? since = await _checkpoints.since(scope, table);

    final PullResult result;
    try {
      result = await _engine.pullRecords(
        entityTable: table,
        since: since,
        localUpdatedAt: (String id) => _rows.updatedAtFor(table, id),
        hasPendingWrite: _queue.hasPendingFor,
        apply: (RemoteRecord record) async {
          if (_checkpoints.changedSince(scope)) throw const _ScopeChanged();
          await apply(record.payload);
        },
      );
    } on _ScopeChanged {
      return const PullResult(applied: 0, skipped: 0, abandonedScope: true);
    }

    if (_checkpoints.changedSince(scope)) {
      return PullResult(
        applied: result.applied,
        skipped: result.skipped,
        abandonedScope: true,
      );
    }

    if (!result.stoppedBecauseOffline) {
      await _checkpoints.record(scope, table, startedAt.subtract(overlap));
    }
    return result;
  }

  /// Favourites and cookbook membership, which carry no timestamps.
  ///
  /// Fetched whole every time rather than by watermark: there is nothing to
  /// compare, and these are a handful of rows. Returns false when the server
  /// could not be reached.
  Future<bool> _pullMemberships(SyncScope scope) async {
    try {
      final List<RemoteRecord> favorites = await _engine.fetchAll(
        'recipe_favorites',
      );
      final List<RemoteRecord> memberships = await _engine.fetchAll(
        'recipe_collections',
      );
      final DateTime now = DateTime.now().toUtc();

      await _rows.replaceFavorites(
        userId: scope.userId,
        remoteRecipeIds: <String>{
          for (final RemoteRecord record in favorites)
            '${record.payload['recipe_id']}',
        },
        hasPendingWrite: _queue.hasPendingFor,
        now: now,
      );

      await _rows.replaceMemberships(
        remote: <(String, String)>{
          for (final RemoteRecord record in memberships)
            (
              '${record.payload['collection_id']}',
              '${record.payload['recipe_id']}',
            ),
        },
        hasPendingWrite: _queue.hasPendingFor,
        now: now,
      );
      return true;
    } on RemoteUnavailable {
      return false;
    }
  }
}

/// Thrown to abandon a pass whose account changed underneath it.
class _ScopeChanged implements Exception {
  const _ScopeChanged();
}
