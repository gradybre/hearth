import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/sync/sync_engine.dart';

/// A gateway that can be told to be offline or to fail, so the paths that
/// matter in a supermarket basement can be exercised without a network.
class FakeGateway implements RemoteGateway {
  bool offline = false;
  String? failWithErrorForId;
  final List<String> pushedIds = <String>[];
  List<RemoteRecord> changed = <RemoteRecord>[];

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) async {
    if (offline) throw const RemoteUnavailable('no connection');
    if (entityId == failWithErrorForId) {
      throw const FormatException('server rejected the row');
    }
    pushedIds.add(entityId);
  }

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async {
    if (offline) throw const RemoteUnavailable('no connection');
    return changed;
  }

  /// What the last pull asked for, so a test can check the watermark is used.
  DateTime? askedSince;

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async {
    askedSince = since;
    if (offline) throw const RemoteUnavailable('no connection');
    return changed;
  }
}

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late FakeGateway gateway;
  late SyncEngine engine;
  final DateTime now = DateTime.utc(2026, 8, 27, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    gateway = FakeGateway();
    engine = SyncEngine(queue: queue, gateway: gateway);
  });

  tearDown(() => db.close());

  Future<void> enqueue(String id, {String table = 'recipes'}) => queue.enqueue(
    entityTable: table,
    entityId: id,
    operation: WriteOperation.upsert,
    payload: <String, Object?>{'id': id, 'title': 'Short ribs'},
    queuedAt: now,
  );

  group('the queue', () {
    test('holds writes in the order they were made', () async {
      await enqueue('a');
      await enqueue('b');
      await enqueue('c');

      final List<PendingWrite> pending = await queue.pending();
      expect(pending.map((PendingWrite w) => w.entityId), <String>[
        'a',
        'b',
        'c',
      ]);
    });

    test('a later write supersedes an unsent earlier one', () async {
      await enqueue('a');
      await queue.enqueue(
        entityTable: 'recipes',
        entityId: 'a',
        operation: WriteOperation.upsert,
        payload: <String, Object?>{'id': 'a', 'title': 'Braised short ribs'},
        queuedAt: now.add(const Duration(minutes: 1)),
      );

      final List<PendingWrite> pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.payload['title'], 'Braised short ribs');
    });

    test('payloads survive the round trip', () async {
      await enqueue('a');
      expect(
        await queue.pending().then((List<PendingWrite> w) => w.single.payload),
        <String, Object?>{'id': 'a', 'title': 'Short ribs'},
      );
    });
  });

  group('pushing', () {
    test('drains the queue when the server is reachable', () async {
      await enqueue('a');
      await enqueue('b');

      final SyncResult result = await engine.push();

      expect(result.pushed, 2);
      expect(result.isFullyDrained, isTrue);
      expect(gateway.pushedIds, <String>['a', 'b']);
      expect(await queue.count(), 0);
    });

    test('offline leaves every write queued and intact', () async {
      // The failure this whole mechanism exists to prevent: a meal logged in
      // a basement supermarket must still be there on reconnect.
      await enqueue('a');
      await enqueue('b');
      gateway.offline = true;

      final SyncResult result = await engine.push();

      expect(result.pushed, 0);
      expect(result.stoppedBecauseOffline, isTrue);
      expect(result.stillQueued, 2);
      expect(await queue.count(), 2);
    });

    test('a queued write survives offline and lands on reconnect', () async {
      await enqueue('a');
      gateway.offline = true;
      await engine.push();

      gateway.offline = false;
      final SyncResult result = await engine.push();

      expect(result.pushed, 1);
      expect(gateway.pushedIds, <String>['a']);
      expect(await queue.count(), 0);
    });

    test('offline stops early rather than failing every write', () async {
      await enqueue('a');
      await enqueue('b');
      await enqueue('c');
      gateway.offline = true;

      await engine.push();

      // No attempt counter should have been incremented: being offline is not
      // the write's fault.
      final List<PendingWrite> pending = await queue.pending();
      expect(pending.every((PendingWrite w) => w.attempts == 0), isTrue);
    });

    test('a rejected write stays queued with its error recorded', () async {
      await enqueue('a');
      await enqueue('bad');
      gateway.failWithErrorForId = 'bad';

      final SyncResult result = await engine.push();

      expect(result.pushed, 1);
      expect(result.failed, 1);
      expect(result.stillQueued, 1);

      final PendingWrite failed = (await queue.pending()).single;
      expect(failed.entityId, 'bad');
      expect(failed.attempts, 1);
      expect(failed.lastError, contains('server rejected'));
    });

    test('a rejected write does not block the ones after it', () async {
      await enqueue('bad');
      await enqueue('good');
      gateway.failWithErrorForId = 'bad';

      await engine.push();
      expect(gateway.pushedIds, contains('good'));
    });
  });

  group('last-write-wins (spec §7.1)', () {
    final DateTime older = DateTime.utc(2026, 8, 27, 10);
    final DateTime newer = DateTime.utc(2026, 8, 27, 11);

    test('a newer remote record replaces the local copy', () {
      expect(
        SyncEngine.shouldAcceptRemote(
          remoteUpdatedAt: newer,
          localUpdatedAt: older,
          hasPendingLocalWrite: false,
        ),
        isTrue,
      );
    });

    test('an older remote record is ignored', () {
      expect(
        SyncEngine.shouldAcceptRemote(
          remoteUpdatedAt: older,
          localUpdatedAt: newer,
          hasPendingLocalWrite: false,
        ),
        isFalse,
      );
    });

    test('a tie keeps the local copy', () {
      expect(
        SyncEngine.shouldAcceptRemote(
          remoteUpdatedAt: newer,
          localUpdatedAt: newer,
          hasPendingLocalWrite: false,
        ),
        isFalse,
      );
    });

    test('an unseen record is always accepted', () {
      expect(
        SyncEngine.shouldAcceptRemote(
          remoteUpdatedAt: older,
          localUpdatedAt: null,
          hasPendingLocalWrite: false,
        ),
        isTrue,
      );
    });

    test('an unsent local write is never overwritten by a pull', () {
      // Even a newer remote record must not discard something the user did
      // offline before it had any chance to reach the server.
      expect(
        SyncEngine.shouldAcceptRemote(
          remoteUpdatedAt: newer,
          localUpdatedAt: older,
          hasPendingLocalWrite: true,
        ),
        isFalse,
      );
    });
  });
}
