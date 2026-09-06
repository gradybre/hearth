import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/data/sync/sync_engine.dart';

void main() {
  group('what the status says', () {
    test('a clean run reports no problem', () {
      const SyncStatus status = SyncStatus.done(
        SyncResult(pushed: 3, failed: 0, stillQueued: 0),
      );
      expect(status.hasProblem, isFalse);
      expect(status.isSyncing, isFalse);
    });

    test('writes waiting for a network are not a problem', () {
      // Offline is an expected state in a supermarket basement, not something
      // to put a warning in front of the user about.
      const SyncStatus status = SyncStatus.done(
        SyncResult(
          pushed: 0,
          failed: 0,
          stillQueued: 4,
          stoppedBecauseOffline: true,
        ),
      );
      expect(status.hasProblem, isFalse);
    });

    test('a write the server refused is a problem', () {
      // It will not resolve itself, so someone has to be told.
      const SyncStatus status = SyncStatus.done(
        SyncResult(pushed: 2, failed: 1, stillQueued: 1),
      );
      expect(status.hasProblem, isTrue);
    });

    test('a write that has stopped being tried is a problem', () {
      // Nothing attempted it this pass, so `failed` is zero — which is
      // exactly how it would sit there unnoticed for ever. It has stopped
      // being asked, so it cannot resolve itself.
      const SyncStatus status = SyncStatus.done(
        SyncResult(pushed: 0, failed: 0, stillQueued: 1, stranded: 1),
      );
      expect(status.hasProblem, isTrue);
    });

    test('a failed run is a problem', () {
      const SyncStatus status = SyncStatus.failed('everything broke');
      expect(status.hasProblem, isTrue);
    });
  });
}
