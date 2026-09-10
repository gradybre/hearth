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

  /// How long a refused write waits before each next try.
  ///
  /// Passes are triggered by local writes rather than a timer, so somebody
  /// typing a shopping list can produce several a second — and a write the
  /// server keeps refusing would be refused several times a second.
  ///
  /// The tail is deliberately long. The first draft ran 2s, 5s, 15s, 30s, 60s
  /// and gave up after five tries, which sounds reasonable and is not: the
  /// whole budget is spent in **fifty-two seconds**. Anything the server is
  /// briefly unhappy about — a deploy window, an incident, a session expiring
  /// a moment before it refreshes — would strand a phone's entire outbox
  /// before anyone could look up from the shopping list. These waits span
  /// about two and a half hours, which is long enough for the transient
  /// things to stop being true.
  static const List<Duration> backoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 2),
  ];

  /// How many times a write is asked before it stops being asked.
  ///
  /// One more than the number of waits, and it has to stay that way: a wait
  /// sits *between* two attempts, so N waits allow N+1 tries. Set to five
  /// alongside five waits, the last wait was unreachable — the cap stranded
  /// the write on the very attempt that would have earned it, and the
  /// schedule the docs described was a third longer than the real one.
  ///
  /// A test holds the two together, since a const cannot read the list's
  /// length.
  static const int maxAttempts = 6;

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

  /// When the queue is next worth asking about, or null if it is not.
  ///
  /// Null covers three different situations that all mean the same thing to a
  /// caller setting an alarm: nothing queued, something queued and already
  /// due, or everything left has stopped being asked. Only a write that is
  /// *waiting* has a moment worth waking for.
  ///
  /// Exists because [backoff] gave a refused write a wait and gave nobody a
  /// reason to come back when it was over: passes are triggered by local
  /// writes, sign-in and resume, and a write sitting out two hours changes
  /// none of those. On a phone left on a counter, nothing happens at all.
  ///
  /// Deliberately answers *when* rather than being polled — see
  /// `SyncController`, which sets one timer off this.
  Future<DateTime?> nextAttemptDue({DateTime? now}) async {
    final DateTime at = now ?? DateTime.now().toUtc();
    final List<PendingWriteRow> waiting =
        await (_db.select(_db.pendingWrites)..where(
              ($PendingWritesTable t) =>
                  t.attempts.isSmallerThanValue(maxAttempts) &
                  t.nextAttemptAt.isNotNull() &
                  t.nextAttemptAt.isBiggerThanValue(at),
            ))
            .get();
    if (waiting.isEmpty) return null;

    // UTC, because a caller comparing this against a moment it already holds
    // uses `DateTime` equality, and Dart counts the same instant in local
    // time and in UTC as two unequal values. The drafts store learned this
    // the same way.
    return waiting
        .map((PendingWriteRow row) => row.nextAttemptAt!.toUtc())
        .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);
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

  /// Asks the stranded writes again, from the beginning.
  ///
  /// Without this a write that gave up is stuck for ever, and so is its
  /// record: `hasPendingFor` still refuses to let a pull overwrite something
  /// that has not been sent, which is right — the local copy is the newer
  /// one, and discarding it to unstick the sync would lose the very work the
  /// queue exists to protect. But that leaves two devices quietly disagreeing
  /// with no way back, and an upsert can at least be re-issued by editing the
  /// record again while a stranded *delete* cannot: the row is already gone
  /// from this screen, so there is nothing left to press.
  ///
  /// So the way back is deliberate and the user's: Settings offers it when
  /// there is something to offer it for.
  Future<int> retryStranded({DateTime? now}) async {
    final int stranded = await strandedCount();
    if (stranded == 0) return 0;

    await (_db.update(_db.pendingWrites)..where(
          ($PendingWritesTable t) =>
              t.attempts.isBiggerOrEqualValue(maxAttempts),
        ))
        .write(
          const PendingWritesCompanion(
            attempts: Value<int>(0),
            nextAttemptAt: Value<DateTime?>(null),
          ),
        );
    return stranded;
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
    // One wait between attempts, so attempt N is followed by wait N. The last
    // attempt is followed by nothing, because the cap is what ends it.
    final Duration wait = backoff[(attempts - 1).clamp(0, backoff.length - 1)];

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
