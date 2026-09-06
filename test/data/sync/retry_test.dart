import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/sync/sync_engine.dart';

/// What a refusal costs, and for how long (spec §7.1, B01).
///
/// `attempts` was written on every failure and read by nothing. No cap and no
/// backoff: a write the server will never accept was retried on every pass
/// for ever — and passes are triggered by local writes, so somebody typing a
/// shopping list produced several a second.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late _FakeGateway gateway;
  late DateTime clock;

  SyncEngine engineAt() =>
      SyncEngine(queue: queue, gateway: gateway, clock: () => clock);

  Future<void> enqueueOne() => queue.enqueue(
    entityTable: 'meal_plan_entries',
    entityId: 'entry-1',
    operation: WriteOperation.upsert,
    payload: const <String, Object?>{'id': 'entry-1'},
    queuedAt: DateTime.utc(2026, 9, 15, 12),
  );

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    gateway = _FakeGateway();
    clock = DateTime.utc(2026, 9, 15, 12);
    await enqueueOne();
  });

  tearDown(() => db.close());

  group('a write the server refuses', () {
    test('waits before being tried again', () async {
      gateway.refuse = true;

      await engineAt().push();
      expect(gateway.attempts, 1);

      // The next pass comes a moment later, because saving a recipe queues
      // several rows and each one nudges a sync.
      clock = clock.add(const Duration(milliseconds: 300));
      await engineAt().push();

      expect(
        gateway.attempts,
        1,
        reason: 'the refusal was retried before its wait had passed',
      );
    });

    test('and is tried again once the wait has passed', () async {
      gateway.refuse = true;
      await engineAt().push();

      clock = clock.add(const Duration(seconds: 3));
      await engineAt().push();

      expect(gateway.attempts, 2);
    });

    test('gives up rather than retrying for ever', () async {
      gateway.refuse = true;

      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(hours: 3));
      }

      expect(gateway.attempts, PendingWriteStore.maxAttempts);
    });

    test('but is kept, not dropped', () async {
      // Losing a logged meal to a server that refused it is exactly the
      // failure the queue exists to prevent. Giving up means giving up
      // *asking*, never giving up the work.
      gateway.refuse = true;
      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(hours: 3));
      }

      expect(await queue.count(), 1);
      expect(await queue.strandedCount(), 1);
    });

    test('and says so, rather than reporting a clean run', () async {
      gateway.refuse = true;
      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(hours: 3));
      }

      final SyncResult result = await engineAt().push();

      expect(result.stranded, 1);
      expect(result.isFullyDrained, isFalse);
    });
  });

  group('being offline', () {
    test('is not a failed attempt, so it never burns the budget', () async {
      // Five aeroplane journeys would otherwise strand a meal that nothing
      // was ever wrong with.
      gateway.offline = true;

      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(hours: 3));
      }

      gateway.offline = false;
      final SyncResult result = await engineAt().push();

      expect(result.pushed, 1);
      expect(await queue.count(), 0);
    });
  });

  group('the schedule itself', () {
    test('has one more try than it has waits', () {
      // A wait sits between two attempts, so N waits allow N+1 tries. Set to
      // five alongside five waits, the last wait was unreachable: the cap
      // stranded the write on the very attempt that would have earned it,
      // and the schedule the docs described was a third longer than the real
      // one. A const cannot read the list's length, so this holds them
      // together instead.
      expect(
        PendingWriteStore.maxAttempts,
        PendingWriteStore.backoff.length + 1,
      );
    });

    test('reaches far enough to outlast something transient', () {
      // The first draft spent its whole budget in fifty-two seconds, which
      // sounds reasonable and is not: a deploy window, an incident, or a
      // session expiring a moment before it refreshes would strand a phone's
      // entire outbox before anyone looked up from the shopping list.
      final Duration total = PendingWriteStore.backoff.reduce(
        (Duration a, Duration b) => a + b,
      );
      expect(total, greaterThan(const Duration(hours: 2)));
    });

    test('every wait is used, in order', () async {
      // Walks the whole schedule and checks each gap is the one named, which
      // is what the off-by-one in the first version got wrong.
      gateway.refuse = true;
      final DateTime start = clock;

      for (int i = 0; i < PendingWriteStore.backoff.length; i++) {
        await engineAt().push();
        expect(
          gateway.attempts,
          i + 1,
          reason: 'attempt ${i + 1} did not happen',
        );

        // A moment short of the wait: nothing yet.
        clock = clock
            .add(PendingWriteStore.backoff[i])
            .subtract(const Duration(seconds: 1));
        await engineAt().push();
        expect(
          gateway.attempts,
          i + 1,
          reason:
              'wait ${i + 1} was shorter than ${PendingWriteStore.backoff[i]}',
        );
        clock = clock.add(const Duration(seconds: 1));
      }

      // And that was the last of them.
      await engineAt().push();
      expect(gateway.attempts, PendingWriteStore.maxAttempts);
      expect(clock.difference(start), greaterThan(const Duration(hours: 2)));
    });
  });

  group('a write that gave up', () {
    test('can be asked again, deliberately', () async {
      // Otherwise it is stuck for ever, and so is its record: a pull will not
      // overwrite something unsent. An upsert can at least be re-issued by
      // editing the record again; a stranded *delete* cannot, because the row
      // is already gone from the screen and there is nothing left to press.
      gateway.refuse = true;
      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(hours: 3));
      }
      expect(await queue.strandedCount(), 1);

      gateway.refuse = false;
      expect(await queue.retryStranded(), 1);

      final SyncResult result = await engineAt().push();

      expect(result.pushed, 1);
      expect(await queue.count(), 0);
    });

    test('right away, not in two hours', () async {
      // The failure that stranded it also set a two-hour wait. Asking again
      // has to clear that as well as the count, or the button does nothing
      // and the user is left tapping it.
      // Walked exactly, so the last failure's wait is still ahead of the
      // clock. A loop that overshoots leaves the wait in the past and cannot
      // tell whether it was cleared — which is how the first version of this
      // test passed with the clearing deleted.
      gateway.refuse = true;
      for (int i = 0; i < PendingWriteStore.maxAttempts; i++) {
        await engineAt().push();
        if (i < PendingWriteStore.backoff.length) {
          clock = clock.add(PendingWriteStore.backoff[i]);
        }
      }
      expect(await queue.strandedCount(), 1);

      gateway.refuse = false;
      await queue.retryStranded();

      // No clock movement at all: this is the user tapping the button.
      final SyncResult result = await engineAt().push();

      expect(result.pushed, 1);
    });

    test('and asking again does nothing when nothing is stuck', () async {
      expect(await queue.retryStranded(), 0);
    });
  });
}

class _FakeGateway implements RemoteGateway {
  bool refuse = false;
  bool offline = false;
  int attempts = 0;

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) async {
    if (offline) throw const RemoteUnavailable('no connection');
    attempts++;
    if (refuse) {
      throw Exception('duplicate key value violates unique constraint');
    }
  }

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async => const <RemoteRecord>[];

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async => const <RemoteRecord>[];
}
