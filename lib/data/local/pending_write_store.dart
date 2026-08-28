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

  /// Everything waiting to sync, oldest first.
  Future<List<PendingWrite>> pending({int? limit}) async {
    final SimpleSelectStatement<$PendingWritesTable, PendingWriteRow> query =
        _db.select(_db.pendingWrites)
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

  /// Records a failure and leaves the write queued to try again.
  ///
  /// The write is never dropped on error: losing a logged meal to a flaky
  /// connection is exactly the failure the queue exists to prevent.
  Future<void> markFailed(int sequence, String error) async {
    await (_db.update(
      _db.pendingWrites,
    )..where(($PendingWritesTable t) => t.sequence.equals(sequence))).write(
      PendingWritesCompanion.custom(
        attempts: _db.pendingWrites.attempts + const Constant<int>(1),
        lastError: Constant<String>(error),
      ),
    );
  }

  static Map<String, Object?> _decode(String payload) {
    final Object? decoded = jsonDecode(payload);
    return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
  }
}
