import '../local/pending_write_store.dart';
import '../local/preference_store.dart';
import '../remote/remote_gateway.dart';
import 'remote_rows.dart';
import 'sync_engine.dart';

/// Brings down the flat tables: plans, logs, targets, cookbooks (spec §7.1).
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
    required String Function() userId,
  }) : _engine = engine,
       _rows = rows,
       _queue = queue,
       _preferences = preferences,
       _userId = userId;

  /// Same reasoning as the library's: overlap rather than risk a gap.
  static const Duration overlap = Duration(minutes: 1);

  final SyncEngine _engine;
  final RemoteRows _rows;
  final PendingWriteStore _queue;
  final PreferenceStore _preferences;
  final String Function() _userId;

  Future<PullResult> pull() async {
    int applied = 0;
    int skipped = 0;
    bool offline = false;

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
        ]) {
      final PullResult result = await _pullTable(spec.table, spec.apply);
      applied += result.applied;
      skipped += result.skipped;
      offline = offline || result.stoppedBecauseOffline;
    }

    if (!offline) offline = !await _pullMemberships();

    return PullResult(
      applied: applied,
      skipped: skipped,
      stoppedBecauseOffline: offline,
    );
  }

  Future<PullResult> _pullTable(
    String table,
    Future<void> Function(Map<String, Object?> json) apply,
  ) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final String key = 'sync.watermark.$table';
    final String? stored = await _preferences.read(key);

    final PullResult result = await _engine.pullRecords(
      entityTable: table,
      since: stored == null ? null : DateTime.tryParse(stored)?.toUtc(),
      localUpdatedAt: (String id) => _rows.updatedAtFor(table, id),
      hasPendingWrite: _queue.hasPendingFor,
      apply: (RemoteRecord record) => apply(record.payload),
    );

    if (!result.stoppedBecauseOffline) {
      await _preferences.write(
        key,
        startedAt.subtract(overlap).toIso8601String(),
      );
    }
    return result;
  }

  /// Favourites and cookbook membership, which carry no timestamps.
  ///
  /// Fetched whole every time rather than by watermark: there is nothing to
  /// compare, and these are a handful of rows. Returns false when the server
  /// could not be reached.
  Future<bool> _pullMemberships() async {
    try {
      final List<RemoteRecord> favorites = await _engine.fetchAll(
        'recipe_favorites',
      );
      final List<RemoteRecord> memberships = await _engine.fetchAll(
        'recipe_collections',
      );
      final DateTime now = DateTime.now().toUtc();

      await _rows.replaceFavorites(
        userId: _userId(),
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
