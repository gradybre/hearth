import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/features/account/export_review_sync.dart';

const SyncStatus finished = SyncStatus.done(
  SyncResult(pushed: 0, failed: 0, stillQueued: 0),
  pulled: PullResult(applied: 0, skipped: 0),
);

class SyncSource {
  SyncStatus status = const SyncStatus.idle();
  final List<void Function(SyncStatus)> listeners =
      <void Function(SyncStatus)>[];
  Future<void> Function()? onRequest;
  int requests = 0;

  void emit(SyncStatus next) {
    status = next;
    for (final listener in List.of(listeners)) {
      listener(next);
    }
  }

  ExportReviewSync coordinator({Duration? timeout}) => ExportReviewSync(
    readStatus: () => status,
    listen: (callback) {
      listeners.add(callback);
      return () => listeners.remove(callback);
    },
    request: () async {
      requests++;
      await onRequest?.call();
    },
    timeout: timeout ?? const Duration(seconds: 1),
  );
}

void main() {
  test(
    'an old successful status and empty queue cannot certify a no-op',
    () async {
      final SyncSource source = SyncSource()..status = finished;
      final ExportSyncAttempt result = await source.coordinator().run(
        canSync: () => true,
      );
      expect(result.outcome, ExportSyncOutcome.notStarted);
      expect(result.canRefresh, isFalse);
      expect(source.requests, 1);
      expect(source.listeners, isEmpty);
    },
  );

  test('an unavailable backend never requests a pass', () async {
    final SyncSource source = SyncSource();
    final ExportSyncAttempt result = await source.coordinator().run(
      canSync: () => false,
    );
    expect(result.outcome, ExportSyncOutcome.notStarted);
    expect(result.canRefresh, isFalse);
    expect(source.requests, 0);
  });

  test('a quick pass is observed before request returns', () async {
    final SyncSource source = SyncSource();
    source.onRequest = () async {
      source.emit(const SyncStatus.syncing());
      source.emit(finished);
    };
    final ExportSyncAttempt result = await source.coordinator().run(
      canSync: () => true,
    );
    expect(result.outcome, ExportSyncOutcome.finished);
    expect(result.canRefresh, isTrue);
    expect(source.listeners, isEmpty);
  });

  test(
    'waits for the running pass and its gate before a fresh attempt',
    () async {
      final SyncSource source = SyncSource()
        ..status = const SyncStatus.syncing();
      bool gateLocked = true;
      bool returned = false;
      final Completer<void> freshStarted = Completer<void>();
      final Completer<void> freshPass = Completer<void>();
      source.onRequest = () async {
        if (gateLocked) return;
        source.emit(const SyncStatus.syncing());
        freshStarted.complete();
        await freshPass.future;
        source.emit(finished);
      };
      final Future<ExportSyncAttempt> pending = source.coordinator().run(
        canSync: () => true,
      );
      unawaited(pending.then((_) => returned = true));
      expect(source.requests, 0);
      source.emit(finished);
      // Just as SyncController does: terminal status first, unlock in finally.
      gateLocked = false;
      await freshStarted.future;
      expect(source.requests, 1);
      expect(returned, isFalse);
      freshPass.complete();
      expect((await pending).outcome, ExportSyncOutcome.finished);
    },
  );

  test(
    'losing backend availability while waiting cannot certify the old pass',
    () async {
      final SyncSource source = SyncSource()
        ..status = const SyncStatus.syncing();
      bool available = true;
      final Future<ExportSyncAttempt> pending = source.coordinator().run(
        canSync: () => available,
      );
      available = false;
      source.emit(finished);

      final ExportSyncAttempt result = await pending;
      expect(result.outcome, ExportSyncOutcome.notStarted);
      expect(result.canRefresh, isFalse);
      expect(source.requests, 0);
      expect(source.listeners, isEmpty);
    },
  );

  test('cancelled review never begins a new pass', () async {
    final SyncSource source = SyncSource();
    final ExportReviewSync coordinator = source.coordinator()..cancel();
    final ExportSyncAttempt result = await coordinator.run(canSync: () => true);
    expect(result.outcome, ExportSyncOutcome.cancelled);
    expect(result.canRefresh, isFalse);
    expect(source.requests, 0);
    expect(source.listeners, isEmpty);
  });

  for (final MapEntry<SyncStatus, ExportSyncOutcome> example
      in <SyncStatus, ExportSyncOutcome>{
        const SyncStatus.done(
          SyncResult(pushed: 0, failed: 0, stillQueued: 0),
          pulled: PullResult(
            applied: 0,
            skipped: 0,
            stoppedBecauseOffline: true,
          ),
        ): ExportSyncOutcome.offline,
        const SyncStatus.done(
          SyncResult(pushed: 0, failed: 0, stillQueued: 2),
          pulled: PullResult(applied: 0, skipped: 0),
        ): ExportSyncOutcome.pending,
        const SyncStatus.failed('private diagnostics'):
            ExportSyncOutcome.failed,
        const SyncStatus.done(
          SyncResult(pushed: 0, failed: 0, stillQueued: 0),
          pulled: PullResult(applied: 0, skipped: 0, abandonedScope: true),
        ): ExportSyncOutcome.abandoned,
        const SyncStatus.idle(): ExportSyncOutcome.abandoned,
      }.entries) {
    test(
      'a terminal ${example.value.name} status is reported honestly',
      () async {
        final SyncSource source = SyncSource();
        source.onRequest = () async {
          source.emit(const SyncStatus.syncing());
          source.emit(example.key);
        };
        final ExportSyncAttempt result = await source.coordinator().run(
          canSync: () => true,
        );
        expect(result.outcome, example.value);
        expect(result.canRefresh, example.value != ExportSyncOutcome.abandoned);
      },
    );
  }

  test('a request that throws before starting cannot refresh', () async {
    final SyncSource source = SyncSource()
      ..onRequest = () async => throw StateError('private diagnostics');
    final ExportSyncAttempt result = await source.coordinator().run(
      canSync: () => true,
    );
    expect(result.outcome, ExportSyncOutcome.failed);
    expect(result.canRefresh, isFalse);
  });

  test('a pass still running at timeout cannot refresh', () async {
    final SyncSource source = SyncSource();
    source.onRequest = () async => source.emit(const SyncStatus.syncing());
    final ExportSyncAttempt result = await source
        .coordinator(timeout: const Duration(milliseconds: 1))
        .run(canSync: () => true);
    expect(result.outcome, ExportSyncOutcome.timedOut);
    expect(result.canRefresh, isFalse);
    expect(source.listeners, isEmpty);
  });

  test(
    'cancel releases the listener without cancelling the shared sync',
    () async {
      final SyncSource source = SyncSource()
        ..status = const SyncStatus.syncing();
      final ExportReviewSync coordinator = source.coordinator();
      final Future<ExportSyncAttempt> pending = coordinator.run(
        canSync: () => true,
      );
      coordinator.cancel();
      final ExportSyncAttempt result = await pending;
      expect(result.outcome, ExportSyncOutcome.cancelled);
      expect(result.canRefresh, isFalse);
      expect(source.requests, 0);
      expect(source.status.isSyncing, isTrue);
      expect(source.listeners, isEmpty);
    },
  );
}
