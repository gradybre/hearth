import 'package:meta/meta.dart';

import '../local/pending_write_store.dart';
import '../remote/remote_gateway.dart';

/// What one pull achieved.
@immutable
class PullResult {
  const PullResult({
    required this.applied,
    required this.skipped,
    this.stoppedBecauseOffline = false,
    this.abandonedScope = false,
  });

  final int applied;

  /// Records the server sent that were not applied — because the local copy
  /// was newer, or because it had an unsent local change.
  final int skipped;

  final bool stoppedBecauseOffline;

  /// True when the pass was thrown away because the account or household
  /// changed while it was running. The answers it was still receiving belong
  /// to whoever is signed in now, not to whoever it started asking for, so
  /// nothing further is applied and no checkpoint is written.
  final bool abandonedScope;
}

/// What one sync attempt achieved.
@immutable
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.failed,
    required this.stillQueued,
    this.stranded = 0,
    this.stoppedBecauseOffline = false,
  });

  final int pushed;
  final int failed;
  final int stillQueued;

  /// Writes that have stopped being asked, having been refused [
  /// PendingWriteStore.maxAttempts] times. They are still here — giving up
  /// means giving up asking, never giving up the work — but nothing will send
  /// them without something changing.
  final int stranded;

  /// True when the run stopped early because the server was unreachable. Not
  /// a failure — the queue is intact and will drain on reconnect.
  final bool stoppedBecauseOffline;

  bool get isFullyDrained => stillQueued == 0;
}

/// Drains the offline write queue (spec §7.1).
///
/// Two rules make this safe to run at any moment:
///
///  * Writes replay in the order they were made, so the result matches having
///    been online throughout.
///  * A write is only dropped from the queue once the server has taken it. A
///    failure leaves it queued with the error recorded — losing a meal you
///    logged offline is the one outcome this must never produce.
class SyncEngine {
  SyncEngine({
    required PendingWriteStore queue,
    required RemoteGateway gateway,
    DateTime Function()? clock,
  }) : _queue = queue,
       _gateway = gateway,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final PendingWriteStore _queue;
  final RemoteGateway _gateway;

  /// Injectable so a test can watch a backoff elapse without waiting for it.
  final DateTime Function() _clock;

  /// Pushes everything queued.
  ///
  /// Stops at the first sign the server is unreachable rather than marching
  /// through the whole queue racking up failures against every write.
  Future<SyncResult> push() async {
    final DateTime now = _clock();
    final List<PendingWrite> writes = await _queue.pending(now: now);
    int pushed = 0;
    int failed = 0;
    bool offline = false;

    for (final PendingWrite write in writes) {
      try {
        await _gateway.push(
          entityTable: write.entityTable,
          entityId: write.entityId,
          operation: write.operation,
          payload: write.payload,
        );
        await _queue.markSynced(write.sequence);
        pushed++;
      } on RemoteUnavailable {
        // Offline is an expected state, not an error worth counting against
        // the write. Leave the queue untouched and try again later.
        offline = true;
        break;
      } on Exception catch (error) {
        await _queue.markFailed(write.sequence, error.toString(), now: now);
        failed++;
      }
    }

    return SyncResult(
      pushed: pushed,
      failed: failed,
      stillQueued: await _queue.count(),
      stranded: await _queue.strandedCount(),
      stoppedBecauseOffline: offline,
    );
  }

  /// Brings down everything that changed since [since] and applies it.
  ///
  /// Push runs first, always: sending what this device did before accepting
  /// what another device did means a local change can never be silently
  /// overwritten by a server copy that predates it.
  Future<PullResult> pullAggregates({
    required String entityTable,
    required DateTime? since,
    required Future<DateTime?> Function(String id) localUpdatedAt,
    required Future<bool> Function(String id) hasPendingWrite,
    required Future<void> Function(RemoteRecord record) apply,
  }) async {
    final List<RemoteRecord> records;
    try {
      records = await _gateway.fetchChangedAggregates(
        entityTable: entityTable,
        since: since,
      );
    } on RemoteUnavailable {
      return const PullResult(
        applied: 0,
        skipped: 0,
        stoppedBecauseOffline: true,
      );
    }

    int applied = 0;
    int skipped = 0;
    for (final RemoteRecord record in records) {
      final bool accept = shouldAcceptRemote(
        remoteUpdatedAt: record.updatedAt,
        localUpdatedAt: await localUpdatedAt(record.id),
        hasPendingLocalWrite: await hasPendingWrite(record.id),
      );
      if (!accept) {
        skipped++;
        continue;
      }
      await apply(record);
      applied++;
    }
    return PullResult(applied: applied, skipped: skipped);
  }

  /// The flat-table equivalent of [pullAggregates].
  Future<PullResult> pullRecords({
    required String entityTable,
    required DateTime? since,
    required Future<DateTime?> Function(String id) localUpdatedAt,
    required Future<bool> Function(String id) hasPendingWrite,
    required Future<void> Function(RemoteRecord record) apply,
  }) async {
    final List<RemoteRecord> records;
    try {
      records = await _gateway.fetchChanged(
        entityTable: entityTable,
        since: since,
      );
    } on RemoteUnavailable {
      return const PullResult(
        applied: 0,
        skipped: 0,
        stoppedBecauseOffline: true,
      );
    }

    int applied = 0;
    int skipped = 0;
    for (final RemoteRecord record in records) {
      final bool accept = shouldAcceptRemote(
        remoteUpdatedAt: record.updatedAt,
        localUpdatedAt: await localUpdatedAt(record.id),
        hasPendingLocalWrite: await hasPendingWrite(record.id),
      );
      if (!accept) {
        skipped++;
        continue;
      }
      await apply(record);
      applied++;
    }
    return PullResult(applied: applied, skipped: skipped);
  }

  /// Every row of a table, for the ones with no timestamp to filter on.
  Future<List<RemoteRecord>> fetchAll(String entityTable) =>
      _gateway.fetchChanged(entityTable: entityTable);

  /// Decides whether an incoming remote record should replace the local copy.
  ///
  /// Whole-record last-write-wins: the newer `updatedAt` wins outright. A tie
  /// keeps the local copy, because the only way to hold an equally-timestamped
  /// record is to have written it here.
  ///
  /// A record with an unsent local write is never overwritten — otherwise a
  /// pull could quietly discard something the user did offline before it ever
  /// reached the server.
  static bool shouldAcceptRemote({
    required DateTime remoteUpdatedAt,
    required DateTime? localUpdatedAt,
    required bool hasPendingLocalWrite,
  }) {
    if (hasPendingLocalWrite) return false;
    if (localUpdatedAt == null) return true;
    return remoteUpdatedAt.isAfter(localUpdatedAt);
  }
}
