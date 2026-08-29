import '../local/food_store.dart';
import '../local/pending_write_store.dart';
import '../local/preference_store.dart';
import '../local/recipe_store.dart';
import '../mappers/sync_payload.dart';
import '../remote/remote_gateway.dart';
import 'sync_engine.dart';

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
  }) : _engine = engine,
       _recipes = recipes,
       _foods = foods,
       _queue = queue,
       _preferences = preferences;

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
  final PreferenceStore _preferences;

  Future<PullResult> pull() async {
    final PullResult recipes = await _pullTable(
      'recipes',
      localUpdatedAt: _recipes.updatedAtFor,
      apply: (RemoteRecord record) => _recipes.upsert(
        SyncPayload.recipe(record.payload),
        updatedAt: record.updatedAt,
      ),
    );
    final PullResult foods = await _pullTable(
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
    );
  }

  Future<PullResult> _pullTable(
    String table, {
    required Future<DateTime?> Function(String id) localUpdatedAt,
    required Future<void> Function(RemoteRecord record) apply,
  }) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final DateTime? since = await _watermark(table);

    final PullResult result = await _engine.pullAggregates(
      entityTable: table,
      since: since,
      localUpdatedAt: localUpdatedAt,
      hasPendingWrite: _queue.hasPendingFor,
      apply: apply,
    );

    // The watermark only moves on a run that actually reached the server.
    // Advancing it after an offline attempt would skip everything that
    // changed while this device was away.
    if (!result.stoppedBecauseOffline) {
      await _preferences.write(
        _watermarkKey(table),
        startedAt.subtract(overlap).toIso8601String(),
      );
    }
    return result;
  }

  Future<DateTime?> _watermark(String table) async {
    final String? stored = await _preferences.read(_watermarkKey(table));
    return stored == null ? null : DateTime.tryParse(stored)?.toUtc();
  }

  static String _watermarkKey(String table) => 'sync.watermark.$table';
}
