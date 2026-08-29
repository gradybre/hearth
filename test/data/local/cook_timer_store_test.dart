import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/cook_timer_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/cooking/cook_session.dart';

void main() {
  late HearthDatabase db;
  late CookTimerStore store;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 18);

  CookTimer aTimer({
    String id = 'timer-1',
    Duration duration = const Duration(minutes: 10),
    DateTime? startedAt,
    Duration? pausedAfter,
    String? stepId = 'step-2',
  }) => CookTimer(
    id: id,
    label: 'Simmer the sauce',
    duration: duration,
    startedAt: startedAt ?? t0,
    stepId: stepId,
    stepNumber: 2,
    elapsedWhenPaused: pausedAfter,
  );

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = CookTimerStore(db);
  });

  tearDown(() => db.close());

  group('a timer outlives the app', () {
    test('what is stored is when it started, not how much is left', () async {
      // This is the whole point: a stored countdown would be wrong by however
      // long the app was closed, which for a braise is most of the cook.
      await store.upsert(aTimer(duration: const Duration(hours: 3)));

      final CookTimer restored = (await store.all(
        now: t0.add(const Duration(hours: 1)),
      )).single;

      expect(
        restored.remainingAt(t0.add(const Duration(hours: 1))),
        const Duration(hours: 2),
      );
    });

    test('a paused timer comes back paused, with its time intact', () async {
      await store.upsert(
        aTimer(
          duration: const Duration(minutes: 10),
          pausedAfter: const Duration(minutes: 3),
        ),
      );

      final CookTimer restored = (await store.all(now: t0)).single;

      expect(restored.isPaused, isTrue);
      expect(
        restored.remainingAt(t0.add(const Duration(days: 1))),
        const Duration(minutes: 7),
        reason: 'a paused timer must not have been running while away',
      );
    });

    test('every field survives the round trip', () async {
      await store.upsert(aTimer(), recipeTitle: 'Braised short ribs');
      final CookTimer restored = (await store.all(now: t0)).single;

      expect(restored.id, 'timer-1');
      expect(restored.label, 'Simmer the sauce');
      expect(restored.stepNumber, 2);
      expect(restored.duration, const Duration(minutes: 10));
      // Compared as an instant, not as an object: Drift stores a unix
      // timestamp and hands back local time, which is the same moment wearing
      // a different offset. The timer only ever does difference arithmetic on
      // it, so the instant is what has to survive.
      expect(restored.startedAt.isAtSameMomentAs(t0), isTrue);
    });

    test('several timers all come back', () async {
      await store.upsert(aTimer(id: 'sauce'));
      await store.upsert(aTimer(id: 'pasta'));
      await store.upsert(aTimer(id: 'oven'));

      expect(await store.all(now: t0), hasLength(3));
    });
  });

  group('what comes back and what does not', () {
    test('one that finished an hour ago still comes back', () async {
      // You want to know the braise is done, even if you are late to it.
      await store.upsert(aTimer(duration: const Duration(minutes: 10)));

      final List<CookTimer> restored = await store.all(
        now: t0.add(const Duration(hours: 1)),
      );

      expect(restored, hasLength(1));
      expect(
        restored.single.isDoneAt(t0.add(const Duration(hours: 1))),
        isTrue,
      );
    });

    test('one from last week is not resurrected', () async {
      await store.upsert(aTimer(duration: const Duration(minutes: 10)));

      expect(await store.all(now: t0.add(const Duration(days: 7))), isEmpty);
    });

    test('and the stale row is cleared out, not left to pile up', () async {
      await store.upsert(aTimer(duration: const Duration(minutes: 10)));
      await store.all(now: t0.add(const Duration(days: 7)));

      expect(
        await store.all(now: t0),
        isEmpty,
        reason: 'the stale timer should have been deleted, not just hidden',
      );
    });

    test('a paused timer is never stale, however long it sits', () async {
      // It is not overdue — it is waiting for you.
      await store.upsert(
        aTimer(
          duration: const Duration(minutes: 10),
          pausedAfter: const Duration(minutes: 1),
        ),
      );

      expect(
        await store.all(now: t0.add(const Duration(days: 7))),
        hasLength(1),
      );
    });
  });

  group('updates', () {
    test('pausing replaces the row rather than adding one', () async {
      final CookTimer timer = aTimer();
      await store.upsert(timer);
      await store.upsert(timer.pausedAt(t0.add(const Duration(minutes: 2))));

      final List<CookTimer> all = await store.all(now: t0);
      expect(all, hasLength(1));
      expect(all.single.isPaused, isTrue);
    });

    test('stopping one removes it', () async {
      await store.upsert(aTimer(id: 'sauce'));
      await store.upsert(aTimer(id: 'pasta'));

      await store.delete('sauce');

      expect((await store.all(now: t0)).single.id, 'pasta');
    });
  });

  group('a timer belongs to its step', () {
    test('the step it came from survives the round trip', () async {
      // The step *number* would not do: it shifts when a recipe is edited, so
      // two timers could collide or a step could quietly acquire a second.
      await store.upsert(aTimer(stepId: 'step-7'));

      expect((await store.all(now: t0)).single.stepId, 'step-7');
    });

    test('a timer with no step is still stored', () async {
      // Nothing creates one today, but the column is nullable and a null must
      // not read back as the string "null".
      await store.upsert(aTimer(stepId: null));

      expect((await store.all(now: t0)).single.stepId, isNull);
    });
  });
}
