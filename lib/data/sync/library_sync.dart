import '../local/food_store.dart';
import '../local/pending_write_store.dart';
import '../local/preference_store.dart';
import '../local/recipe_store.dart';
import '../mappers/sync_payload.dart';
import '../remote/remote_gateway.dart';
import 'sync_checkpoints.dart';
import 'sync_engine.dart';
import 'sync_scope.dart';

/// Brings the shared library down from the server (spec §5.1, §7.1).
///
/// This is what makes a household mean something: recipes and foods either
/// member adds become visible to the other. Meal plans and logs are private
/// per user and are not part of this.
class LibrarySync {
  LibrarySync({
    required SyncEngine engine,
    required RecipeStore recipes,
    required FoodStore foods,
    required PendingWriteStore queue,
    required PreferenceStore preferences,
    required SyncScope Function() scope,
  }) : _engine = engine,
       _recipes = recipes,
       _foods = foods,
       _queue = queue,
       _checkpoints = SyncCheckpoints(preferences: preferences, scope: scope);

  /// How far back a pull reaches beyond the last one.
  ///
  /// Two devices' clocks disagree, and `updated_at` is set by the server but
  /// compared against a watermark this device stored. Overlapping the window
  /// slightly costs a few redundant records — which last-write-wins discards
  /// anyway — and avoids the one outcome that matters: a record written in the
  /// second between two pulls being skipped forever.
  static const Duration overlap = Duration(minutes: 1);

  final SyncEngine _engine;
  final RecipeStore _recipes;
  final FoodStore _foods;
  final PendingWriteStore _queue;
  final SyncCheckpoints _checkpoints;

  Future<PullResult> pull() async {
    // One pass identity, captured before the first request. Both tables
    // belong to the same library, and half of one account's and half of
    // another's is not a library.
    final SyncPass pass = await _checkpoints.begin();

    final PullResult recipes = await _pullTable(
      pass,
      'recipes',
      localUpdatedAt: _recipes.updatedAtFor,
      apply: (RemoteRecord record) => _recipes.upsert(
        SyncPayload.recipe(record.payload),
        updatedAt: record.updatedAt,
      ),
    );
    if (recipes.abandonedScope) return recipes;

    final PullResult foods = await _pullTable(
      pass,
      'foods',
      localUpdatedAt: _foods.updatedAtFor,
      apply: (RemoteRecord record) => _foods.upsert(
        SyncPayload.food(record.payload),
        updatedAt: record.updatedAt,
      ),
    );

    return PullResult(
      applied: recipes.applied + foods.applied,
      skipped: recipes.skipped + foods.skipped,
      stoppedBecauseOffline:
          recipes.stoppedBecauseOffline || foods.stoppedBecauseOffline,
      abandonedScope: foods.abandonedScope,
    );
  }

  Future<PullResult> _pullTable(
    SyncPass pass,
    String table, {
    required Future<DateTime?> Function(String id) localUpdatedAt,
    required Future<void> Function(RemoteRecord record) apply,
  }) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final DateTime? since = await _checkpoints.since(pass, table);

    final PullResult result;
    try {
      result = await _engine.pullAggregates(
        entityTable: table,
        since: since,
        localUpdatedAt: localUpdatedAt,
        hasPendingWrite: _queue.hasPendingFor,
        // Checked per record rather than once at the end: the sooner an
        // abandoned pass stops writing, the fewer of the wrong account's
        // answers land in this device's store.
        apply: (RemoteRecord record) async {
          if (await _checkpoints.hasEnded(pass)) throw const _ScopeChanged();
          await apply(record);
        },
      );
    } on _ScopeChanged {
      return const PullResult(applied: 0, skipped: 0, abandonedScope: true);
    }

    // And again after the answers are in, because a pass that returned
    // nothing never reached the check above — and it is the checkpoint, not
    // the rows, that does the lasting damage.
    if (await _checkpoints.hasEnded(pass)) {
      return PullResult(
        applied: result.applied,
        skipped: result.skipped,
        abandonedScope: true,
      );
    }

    // The watermark only moves on a run that actually reached the server.
    // Advancing it after an offline attempt would skip everything that
    // changed while this device was away.
    if (!result.stoppedBecauseOffline) {
      await _checkpoints.record(pass, table, startedAt.subtract(overlap));
    }
    return result;
  }
}

/// Thrown to abandon a pass whose account changed underneath it.
class _ScopeChanged implements Exception {
  const _ScopeChanged();
}
