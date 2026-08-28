import 'package:meta/meta.dart';

import '../local/pending_write_store.dart';
import '../remote/remote_gateway.dart';

/// What one sync attempt achieved.
@immutable
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.failed,
    required this.stillQueued,
    this.stoppedBecauseOffline = false,
  });

  final int pushed;
  final int failed;
  final int stillQueued;

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
  SyncEngine({required PendingWriteStore queue, required RemoteGateway gateway})
    : _queue = queue,
      _gateway = gateway;

  final PendingWriteStore _queue;
  final RemoteGateway _gateway;

  /// Pushes everything queued.
  ///
  /// Stops at the first sign the server is unreachable rather than marching
  /// through the whole queue racking up failures against every write.
  Future<SyncResult> push() async {
    final List<PendingWrite> writes = await _queue.pending();
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
        await _queue.markFailed(write.sequence, error.toString());
        failed++;
      }
    }

    return SyncResult(
      pushed: pushed,
      failed: failed,
      stillQueued: await _queue.count(),
      stoppedBecauseOffline: offline,
    );
  }

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
