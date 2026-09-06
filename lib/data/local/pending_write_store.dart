import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'hearth_database.dart';

/// What a queued write does to the remote record.
enum WriteOperation {
  /// Insert or replace the whole record.
  upsert,

  /// Physically remove it. Recipes and foods are soft-deleted instead, so this
  /// only ever reaches rows the spec allows to disappear (spec §4).
  delete,
}

/// A write made locally that has not yet reached Supabase.
@immutable
class PendingWrite {
  const PendingWrite({
    required this.sequence,
    required this.entityTable,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  /// Monotonic; replaying in this order is what makes the queue equivalent to
  /// having been online the whole time.
  final int sequence;

  final String entityTable;
  final String entityId;
  final WriteOperation operation;

  /// The entire record, never a patch — whole-record last-write-wins has
  /// nothing to merge (spec §7.1).
  final Map<String, Object?> payload;

  final DateTime queuedAt;
  final int attempts;
  final String? lastError;
}

/// The offline write queue (spec §7.1).
///
/// Writes land in the local database and here, in one transaction, so a write
/// can never be visible on the device without also being scheduled to sync —
/// which is the failure that would silently lose a meal you logged in a
/// basement supermarket.
class PendingWriteStore {
  PendingWriteStore(this._db);

  final HearthDatabase _db;

  static String operationToSql(WriteOperation operation) => switch (operation) {
    WriteOperation.upsert => 'upsert',
    WriteOperation.delete => 'delete',
  };

  static WriteOperation operationFromSql(String value) => switch (value) {
    'delete' => WriteOperation.delete,
    _ => WriteOperation.upsert,
  };

  /// Queues a write. Call inside the same transaction as the local change.
  Future<void> enqueue({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
    required DateTime queuedAt,
  }) async {
    // Supersede any earlier unsent write for the same record: the newest whole
    // record is the only one that can win, so replaying the older ones would
    // be wasted round trips that briefly resurrect stale data.
    await (_db.delete(_db.pendingWrites)..where(
          ($PendingWritesTable t) =>
              t.entityTable.equals(entityTable) & t.entityId.equals(entityId),
        ))
        .go();

    await _db
        .into(_db.pendingWrites)
        .insert(
          PendingWritesCompanion.insert(
            entityTable: entityTable,
            entityId: entityId,
            operation: operationToSql(operation),
            payload: jsonEncode(payload),
            queuedAt: queuedAt,
          ),
        );
  }

  /// How many times a write is asked before it stops being asked.
  ///
  /// The same five as photo sync, which solved this first and whose candidate
  /// query has enforced a cap since it was built. The outbox never learned:
  /// it counted attempts and read the count nowhere.
  static const int maxAttempts = 5;

  /// How long a refused write waits before the next try.
  ///
  /// Passes are triggered by local writes rather than a timer, so somebody
  /// typing a shopping list can produce several a second — and a write the
  /// server will keep refusing would be refused several times a second.
  static const List<Duration> backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Everything ready to sync now, oldest first.
  ///
  /// Excludes writes still waiting out a backoff, and writes that have given
  /// up. Neither is dropped — see [strandedCount] and [count].
  Future<List<PendingWrite>> pending({int? limit, DateTime? now}) async {
    final DateTime at = now ?? DateTime.now().toUtc();
    final SimpleSelectStatement<$PendingWritesTable, PendingWriteRow> query =
        _db.select(_db.pendingWrites)
          ..where(
            ($PendingWritesTable t) =>
                t.attempts.isSmallerThanValue(maxAttempts) &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(at)),
          )
          ..orderBy(<OrderClauseGenerator<$PendingWritesTable>>[
            ($PendingWritesTable t) => OrderingTerm.asc(t.sequence),
          ]);
    if (limit != null) query.limit(limit);

    final List<PendingWriteRow> rows = await query.get();
    return <PendingWrite>[
      for (final PendingWriteRow row in rows)
        PendingWrite(
          sequence: row.sequence,
          entityTable: row.entityTable,
          entityId: row.entityId,
          operation: operationFromSql(row.operation),
          payload: _decode(row.payload),
          queuedAt: row.queuedAt,
          attempts: row.attempts,
          lastError: row.lastError,
        ),
    ];
  }

  /// Whether this record has a local change that has not reached the server.
  ///
  /// A pull must never overwrite one: the server's copy predates the local
  /// change by definition, so accepting it would discard something the user
  /// did offline before it was ever sent.
  Future<bool> hasPendingFor(String entityId) async {
    final List<PendingWriteRow> rows = await (_db.select(
      _db.pendingWrites,
    )..where(($PendingWritesTable t) => t.entityId.equals(entityId))).get();
    return rows.isNotEmpty;
  }

  Future<int> count() async {
    final List<PendingWriteRow> rows = await _db
        .select(_db.pendingWrites)
        .get();
    return rows.length;
  }

  /// How many writes are waiting, re-emitted as the queue changes.
  ///
  /// Doubles as the signal that something was written locally, which is what
  /// prompts a sync — there is no separate "something changed" event to
  /// listen for, and inventing one would be a second thing to keep in step.
  Stream<int> watchCount() => _db
      .select(_db.pendingWrites)
      .watch()
      .map((List<PendingWriteRow> rows) => rows.length);

  /// Removes a write that reached the server.
  Future<void> markSynced(int sequence) async {
    await (_db.delete(
      _db.pendingWrites,
    )..where(($PendingWritesTable t) => t.sequence.equals(sequence))).go();
  }

  /// How many writes have stopped being asked.
  ///
  /// Kept, not dropped. Giving up means giving up *asking* — losing a logged
  /// meal to a server that refused it is exactly the failure the queue exists
  /// to prevent.
  Future<int> strandedCount() async {
    final List<PendingWriteRow> rows =
        await (_db.select(_db.pendingWrites)..where(
              ($PendingWritesTable t) =>
                  t.attempts.isBiggerOrEqualValue(maxAttempts),
            ))
            .get();
    return rows.length;
  }

  /// Records a failure and leaves the write queued to try again later.
  ///
  /// The write is never dropped on error: losing a logged meal to a flaky
  /// connection is exactly the failure the queue exists to prevent.
  Future<void> markFailed(int sequence, String error, {DateTime? now}) async {
    final DateTime at = now ?? DateTime.now().toUtc();
    final PendingWriteRow? row =
        await (_db.select(_db.pendingWrites)
              ..where(($PendingWritesTable t) => t.sequence.equals(sequence)))
            .getSingleOrNull();
    if (row == null) return;

    final int attempts = row.attempts + 1;
    // The last step repeats for the final try rather than growing without
    // bound; the cap is what ends it, not the delay.
    final Duration wait = backoff[attempts.clamp(1, backoff.length) - 1];

    await (_db.update(
      _db.pendingWrites,
    )..where(($PendingWritesTable t) => t.sequence.equals(sequence))).write(
      PendingWritesCompanion.custom(
        attempts: Constant<int>(attempts),
        lastError: Constant<String>(error),
        nextAttemptAt: Constant<DateTime>(at.add(wait)),
      ),
    );
  }

  static Map<String, Object?> _decode(String payload) {
    final Object? decoded = jsonDecode(payload);
    return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
  }
}
