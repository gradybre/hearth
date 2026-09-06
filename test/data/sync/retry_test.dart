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
        clock = clock.add(const Duration(minutes: 5));
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
        clock = clock.add(const Duration(minutes: 5));
      }

      expect(await queue.count(), 1);
      expect(await queue.strandedCount(), 1);
    });

    test('and says so, rather than reporting a clean run', () async {
      gateway.refuse = true;
      for (int i = 0; i < 20; i++) {
        await engineAt().push();
        clock = clock.add(const Duration(minutes: 5));
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
        clock = clock.add(const Duration(minutes: 5));
      }

      gateway.offline = false;
      final SyncResult result = await engineAt().push();

      expect(result.pushed, 1);
      expect(await queue.count(), 0);
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
