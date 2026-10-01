import 'dart:async';

import '../../app/sync_controller.dart';
import '../../data/sync/sync_engine.dart';

/// The outcome of an observed sync pass, rather than of asking for one.
enum ExportSyncOutcome {
  finished,
  pending,
  offline,
  failed,
  abandoned,
  notStarted,
  timedOut,
  cancelled,
}

class ExportSyncAttempt {
  const ExportSyncAttempt(this.outcome, {this.finishedAttempt = false});

  final ExportSyncOutcome outcome;

  /// False for a no-op, an interrupted wait, and a pass still running.
  final bool finishedAttempt;

  bool get canRefresh =>
      finishedAttempt && outcome != ExportSyncOutcome.abandoned;
}

/// Waits for the status transitions that prove a pass actually ran.
///
/// SyncController.sync returns immediately when a pass is already running,
/// or when it cannot start. Awaiting that method alone would relabel an old
/// snapshot as refreshed. The callbacks keep this feature helper testable
/// without changing the shared controller's lifecycle.
class ExportReviewSync {
  ExportReviewSync({
    required this.readStatus,
    required this.listen,
    required this.request,
    this.timeout = const Duration(seconds: 45),
  });

  final SyncStatus Function() readStatus;
  final void Function() Function(void Function(SyncStatus)) listen;
  final Future<void> Function() request;
  final Duration timeout;

  bool _cancelled = false;
  void Function()? _stopWaiting;

  void cancel() {
    _cancelled = true;
    _stopWaiting?.call();
  }

  Future<ExportSyncAttempt> run({required bool Function() canSync}) async {
    if (_cancelled) {
      return const ExportSyncAttempt(ExportSyncOutcome.cancelled);
    }
    if (!canSync()) {
      return const ExportSyncAttempt(ExportSyncOutcome.notStarted);
    }

    if (readStatus().isSyncing) {
      final ExportSyncAttempt waiting = await _observe(requestPass: false);
      if (!waiting.finishedAttempt || _cancelled) {
        return _cancelled
            ? const ExportSyncAttempt(ExportSyncOutcome.cancelled)
            : waiting;
      }
      if (!canSync()) {
        return const ExportSyncAttempt(ExportSyncOutcome.notStarted);
      }
      // The terminal status is emitted before SyncController's finally
      // releases its gate. Yield an event turn before requesting our pass.
      await Future<void>.delayed(Duration.zero);
      if (_cancelled) {
        return const ExportSyncAttempt(ExportSyncOutcome.cancelled);
      }
      if (!canSync()) {
        return const ExportSyncAttempt(ExportSyncOutcome.notStarted);
      }
    }

    return _observe(requestPass: true);
  }

  Future<ExportSyncAttempt> _observe({required bool requestPass}) async {
    final Completer<ExportSyncAttempt> done = Completer<ExportSyncAttempt>();
    bool sawStart = !requestPass && readStatus().isSyncing;

    void finish(ExportSyncAttempt result) {
      if (!done.isCompleted) done.complete(result);
    }

    final void Function() stopListening = listen((SyncStatus status) {
      if (status.isSyncing) {
        sawStart = true;
      } else if (sawStart) {
        finish(_result(status));
      }
    });
    _stopWaiting = () =>
        finish(const ExportSyncAttempt(ExportSyncOutcome.cancelled));
    final Timer timer = Timer(
      timeout,
      () => finish(const ExportSyncAttempt(ExportSyncOutcome.timedOut)),
    );

    try {
      if (_cancelled) {
        _stopWaiting!();
      } else if (requestPass) {
        // Observe first: the start notification is synchronous, and a fake
        // or a fast pass may also finish before request's future returns.
        unawaited(
          Future<void>.sync(request).then(
            (_) {
              if (!sawStart) {
                finish(const ExportSyncAttempt(ExportSyncOutcome.notStarted));
              }
            },
            onError: (Object _, StackTrace _) {
              finish(
                ExportSyncAttempt(
                  ExportSyncOutcome.failed,
                  finishedAttempt: sawStart,
                ),
              );
            },
          ),
        );
      }
      return await done.future;
    } finally {
      timer.cancel();
      stopListening();
      _stopWaiting = null;
    }
  }

  static ExportSyncAttempt _result(SyncStatus status) {
    final SyncResult? pushed = status.result;
    final PullResult? pulled = status.pulled;
    final ExportSyncOutcome outcome;
    if (pulled?.abandonedScope ?? false) {
      outcome = ExportSyncOutcome.abandoned;
    } else if (status.hasProblem) {
      outcome = ExportSyncOutcome.failed;
    } else if ((pushed?.stoppedBecauseOffline ?? false) ||
        (pulled?.stoppedBecauseOffline ?? false)) {
      outcome = ExportSyncOutcome.offline;
    } else if (pushed == null || pulled == null) {
      // A reset to idle is not proof that either half of the pull completed.
      outcome = ExportSyncOutcome.abandoned;
    } else if (!pushed.isFullyDrained) {
      outcome = ExportSyncOutcome.pending;
    } else {
      outcome = ExportSyncOutcome.finished;
    }
    return ExportSyncAttempt(outcome, finishedAttempt: true);
  }
}
