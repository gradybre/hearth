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
    test('adjusting a stopped timer cannot insert it again', () async {
      final CookTimer timer = aTimer();
      await store.upsert(timer, recipeTitle: 'Braised short ribs');
      await store.delete(timer.id);

      expect(
        await store.updateExisting(
          timer.addingTime(const Duration(minutes: 1), now: t0),
        ),
        isFalse,
      );
      expect(await db.select(db.cookTimers).get(), isEmpty);
    });

    test('adjusting preserves the existing recipe and step linkage', () async {
      final CookTimer timer = aTimer();
      await store.upsert(timer, recipeTitle: 'Braised short ribs');

      expect(
        await store.updateExisting(
          timer.addingTime(const Duration(minutes: 5), now: t0),
        ),
        isTrue,
      );

      final CookTimerRow row = (await db.select(db.cookTimers).get()).single;
      expect(row.id, timer.id);
      expect(row.label, timer.label);
      expect(row.stepId, timer.stepId);
      expect(row.stepNumber, timer.stepNumber);
      expect(row.recipeTitle, 'Braised short ribs');
      expect(row.durationSeconds, 15 * 60);
    });

    test('a resumed adjusted timer clears its stored pause', () async {
      final DateTime pausedAt = t0.add(const Duration(minutes: 2));
      final CookTimer timer = aTimer().pausedAt(pausedAt);
      await store.upsert(timer, recipeTitle: 'Braised short ribs');
      final CookTimer adjusted = timer.withTimeLeft(
        const Duration(minutes: 3, seconds: 20),
        now: pausedAt,
      );
      await store.updateExisting(adjusted);
      final DateTime resumedAt = t0.add(const Duration(hours: 1));
      await store.updateExisting(adjusted.resumedAt(resumedAt));

      final CookTimerStore restarted = CookTimerStore(db);
      final DateTime later = resumedAt.add(const Duration(minutes: 1));
      final CookTimer restored = (await restarted.all(now: later)).single;
      expect(restored.isPaused, isFalse);
      expect(
        restored.remainingAt(later),
        const Duration(minutes: 2, seconds: 20),
      );
      expect(
        (await db.select(db.cookTimers).get()).single.elapsedWhenPausedSeconds,
        isNull,
      );
    });

    test('an adjusted paused timer restores with the same time left', () async {
      final CookTimer timer = aTimer(pausedAfter: const Duration(minutes: 2));
      await store.upsert(timer);
      await store.updateExisting(
        timer.withTimeLeft(const Duration(seconds: 45), now: t0),
      );

      final DateTime later = t0.add(const Duration(days: 7));
      final CookTimer restored = (await CookTimerStore(db).all(now: later))
          .single;
      expect(restored.isPaused, isTrue);
      expect(restored.remainingAt(later), const Duration(seconds: 45));
    });

    test('a restarted finished timer restores from its new deadline', () async {
      final CookTimer timer = aTimer();
      await store.upsert(timer);
      final DateTime restartedAt = t0.add(const Duration(hours: 1));
      await store.updateExisting(
        timer.addingTime(const Duration(minutes: 5), now: restartedAt),
      );

      final DateTime later = restartedAt.add(const Duration(minutes: 2));
      final CookTimer restored = (await CookTimerStore(db).all(now: later))
          .single;
      expect(restored.id, timer.id);
      expect(restored.isPaused, isFalse);
      expect(restored.remainingAt(later), const Duration(minutes: 3));
    });

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
