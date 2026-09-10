import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';

/// When the queue is next worth asking about (spec §7.1, review F07).
///
/// #22 gave a refused write a backoff — 2s, 30s, 5m, 30m, 2h — so a server
/// having a bad afternoon does not burn a phone's whole outbox in a minute.
/// What it did not give anybody was a reason to come back when the wait was
/// over.
///
/// Sync is triggered by local writes, sign-in, resume and the manual button,
/// and a write waiting out two hours changes none of those. So a meal logged
/// on a train, refused once for a reason that has since passed, sits there
/// until something unrelated happens to nudge the app — which on a phone left
/// on a counter is nothing at all.
///
/// This is the fact the controller needs to set an alarm by. Deliberately not
/// a poll: it answers *when*, so nothing has to ask repeatedly.
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  final DateTime at = DateTime.utc(2026, 9, 15, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
  });

  tearDown(() => db.close());

  Future<void> enqueue(String id) => queue.enqueue(
    entityTable: 'meal_plan_entries',
    entityId: id,
    operation: WriteOperation.upsert,
    payload: <String, Object?>{'id': id},
    queuedAt: at,
  );

  test('nothing waiting means no alarm to set', () async {
    expect(await queue.nextAttemptDue(), isNull);
  });

  test('and a write that can be sent now does not need one either', () async {
    // It is already due. An alarm for the present is a wasted wake-up.
    await enqueue('a');
    expect(await queue.nextAttemptDue(), isNull);
  });

  test('a refused write says when it is worth asking again', () async {
    await enqueue('a');
    final PendingWrite write = (await queue.pending(now: at)).single;
    await queue.markFailed(write.sequence, 'the server said no', now: at);

    expect(
      await queue.nextAttemptDue(),
      at.add(PendingWriteStore.backoff.first),
      reason: 'the wait is known and nothing was going to act on it',
    );
  });

  test(
    'and with several waiting, the soonest is the one to wake for',
    () async {
      // Two failures at different times. Waking for the later one leaves the
      // earlier write sitting past its own turn.
      await enqueue('a');
      await enqueue('b');
      final List<PendingWrite> both = await queue.pending(now: at);
      await queue.markFailed(both.first.sequence, 'no', now: at);
      await queue.markFailed(
        both.last.sequence,
        'no',
        now: at.add(const Duration(minutes: 5)),
      );

      expect(
        await queue.nextAttemptDue(),
        at.add(PendingWriteStore.backoff.first),
      );
    },
  );

  test('a write that has stopped being asked sets no alarm', () async {
    // Stranded, after `maxAttempts`. Waking for it would be a timer that
    // fires for ever over a write nothing will send without a person.
    await enqueue('a');
    // The clock has to move: each failure pushes the next attempt further
    // out, so asking again at the same instant finds nothing due and the
    // loop stops after one — which is how the first version of this test
    // asserted against a write that had failed once.
    for (int i = 0; i < PendingWriteStore.maxAttempts; i++) {
      final DateTime later = at.add(Duration(days: i + 1));
      final List<PendingWrite> due = await queue.pending(now: later);
      expect(due, isNotEmpty, reason: 'stopped short at attempt $i');
      await queue.markFailed(due.single.sequence, 'no', now: later);
    }

    expect(await queue.nextAttemptDue(), isNull);
  });
}
