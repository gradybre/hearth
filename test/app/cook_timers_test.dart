import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/cook_timers.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/cook_timer_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/cooking/cook_session.dart';

import '../support/fake_kitchen.dart';

void main() {
  late HearthDatabase db;
  late ProviderContainer container;
  late CookTimersNotifier control;
  late _FailingAlerts alerts;
  late CookTimer original;
  late DateTime now;
  late _ObservedStore store;

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = _ObservedStore(db);
    alerts = _FailingAlerts();
    now = DateTime.utc(2026, 10, 1, 18);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        cookTimerStoreProvider.overrideWithValue(store),
        timerAlertsProvider.overrideWithValue(alerts),
        cookTimersProvider.overrideWith(
          () => CookTimersNotifier(now: () => now),
        ),
      ],
    );
    await container.read(cookTimersProvider.future);
    control = container.read(cookTimersProvider.notifier);
    original = CookTimer(
      id: 'pasta-timer',
      label: 'Simmer the pasta',
      duration: const Duration(minutes: 10),
      startedAt: now,
      stepId: 'pasta-step',
      stepNumber: 2,
    );
    await control.start(original, recipeTitle: 'Pasta supper');
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a stale pause callback updates the current timer state', () async {
    await control.togglePause(original);
    expect(container.read(cookTimersProvider).value!.single.isPaused, isTrue);
    await control.togglePause(original);
    expect(container.read(cookTimersProvider).value!.single.isPaused, isFalse);
  });

  test('a stale timer callback cannot resurrect a dismissed timer', () async {
    await control.dismiss(original.id);
    await control.togglePause(original);
    expect(await db.select(db.cookTimers).get(), isEmpty);
    expect(container.read(cookTimersProvider).value, isEmpty);
  });

  test('editing a timer keeps its stored recipe linkage', () async {
    await control.togglePause(original);
    final CookTimerRow stored = (await db.select(db.cookTimers).get()).single;
    expect(stored.recipeTitle, 'Pasta supper');
    expect(stored.stepId, 'pasta-step');
    expect(stored.stepNumber, 2);
    expect(stored.id, original.id);
  });

  test('overlapping starts still create only one timer per step', () async {
    await control.dismiss(original.id);
    CookTimer duplicate(String id) => CookTimer(
      id: id,
      label: original.label,
      duration: original.duration,
      startedAt: original.startedAt,
      stepId: original.stepId,
      stepNumber: original.stepNumber,
    );
    await Future.wait(<Future<void>>[
      control.start(duplicate('first')),
      control.start(duplicate('second')),
    ]);
    expect(await db.select(db.cookTimers).get(), hasLength(1));
  });

  test(
    'an alert failure does not hide the timer state already saved',
    () async {
      await control.togglePause(original);
      final CookTimer paused = container.read(cookTimersProvider).value!.single;
      alerts.failSchedule = true;
      await expectLater(control.togglePause(paused), throwsA(isA<Exception>()));
      expect(
        container.read(cookTimersProvider).value!.single.isPaused,
        isFalse,
      );
      expect(
        (await db.select(db.cookTimers).get()).single.elapsedWhenPausedSeconds,
        isNull,
      );
    },
  );

  test(
    'concurrent additions use current stored time without duplicates',
    () async {
      now = now.add(const Duration(minutes: 2));
      await Future.wait(<Future<bool>>[
        control.addTime(original.id, const Duration(minutes: 1)),
        control.addTime(original.id, const Duration(minutes: 5)),
      ]);
      final CookTimer current = container
          .read(cookTimersProvider)
          .value!
          .single;
      expect(current.remainingAt(now), const Duration(minutes: 14));
      final CookTimerRow row = (await db.select(db.cookTimers).get()).single;
      expect(row.recipeTitle, 'Pasta supper');
      expect(row.stepId, original.stepId);
      expect(row.id, original.id);
      expect(alerts.cancelled, <String>[original.id, original.id]);
      expect(alerts.firesAt.last.toUtc(), now.add(const Duration(minutes: 14)));
    },
  );

  test(
    'an adjusted running timer restores against the advanced clock',
    () async {
      now = now.add(const Duration(minutes: 2));
      await control.addTime(original.id, const Duration(minutes: 5));
      container.dispose();
      now = now.add(const Duration(minutes: 3));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          timerAlertsProvider.overrideWithValue(alerts),
          cookTimersProvider.overrideWith(
            () => CookTimersNotifier(now: () => now),
          ),
        ],
      );
      final CookTimer restored = (await container.read(
        cookTimersProvider.future,
      )).single;
      expect(restored.remainingAt(now), const Duration(minutes: 10));
      expect(restored.isPaused, isFalse);
      expect(restored.id, original.id);
    },
  );

  test(
    'paused adjustments remain paused and cancel rather than schedule',
    () async {
      now = now.add(const Duration(minutes: 3));
      await control.togglePause(original);
      now = now.add(const Duration(hours: 1));
      await control.addTime(original.id, const Duration(minutes: 5));
      expect(
        container.read(cookTimersProvider).value!.single.remainingAt(now),
        const Duration(minutes: 12),
      );
      await control.setTimeLeft(
        original.id,
        const Duration(minutes: 4, seconds: 30),
      );
      final CookTimer current = container
          .read(cookTimersProvider)
          .value!
          .single;
      expect(current.isPaused, isTrue);
      expect(
        current.remainingAt(now.add(const Duration(hours: 4))),
        const Duration(minutes: 4, seconds: 30),
      );
      expect(alerts.scheduled, <String>[original.id]);
      expect(alerts.cancelled, hasLength(3));
      await control.togglePause(original);
      expect(
        container.read(cookTimersProvider).value!.single.isPaused,
        isFalse,
      );
      expect(
        alerts.firesAt.last,
        now.add(const Duration(minutes: 4, seconds: 30)),
      );
    },
  );

  test('finished additions and setting time both restart from now', () async {
    now = now.add(const Duration(hours: 1));
    await control.addTime(original.id, const Duration(minutes: 1));
    CookTimer current = container.read(cookTimersProvider).value!.single;
    expect(current.remainingAt(now), const Duration(minutes: 1));
    expect(current.startedAt, now);
    now = now.add(const Duration(minutes: 2));
    await control.setTimeLeft(original.id, const Duration(seconds: 20));
    current = container.read(cookTimersProvider).value!.single;
    expect(current.isPaused, isFalse);
    expect(current.remainingAt(now), const Duration(seconds: 20));
    expect(alerts.firesAt.last, now.add(const Duration(seconds: 20)));
  });

  test('an adjustment saved before Stop cannot revive after Stop', () async {
    await Future.wait(<Future<void>>[
      control.addTime(original.id, const Duration(minutes: 1)),
      control.dismiss(original.id),
      control.addTime(original.id, const Duration(minutes: 5)),
    ]);
    expect(await db.select(db.cookTimers).get(), isEmpty);
    expect(container.read(cookTimersProvider).value, isEmpty);
    expect(
      await control.setTimeLeft(original.id, const Duration(minutes: 1)),
      isFalse,
    );
  });

  test('alert retry never reapplies a saved addition', () async {
    alerts.failSchedule = true;
    await expectLater(
      control.addTime(original.id, const Duration(minutes: 5)),
      throwsA(isA<CookTimerAlertFailure>()),
    );
    expect(
      container.read(cookTimersProvider).value!.single.duration,
      const Duration(minutes: 15),
    );
    alerts.failSchedule = false;
    await control.retryAlert(original.id);
    expect(
      container.read(cookTimersProvider).value!.single.duration,
      const Duration(minutes: 15),
    );
    expect(alerts.firesAt.last.toUtc(), now.add(const Duration(minutes: 15)));
    expect(await db.select(db.cookTimers).get(), hasLength(1));
  });

  test(
    'alert retry after Stop only cancels and never recreates a timer',
    () async {
      await control.dismiss(original.id);
      final int scheduled = alerts.scheduled.length;
      await control.retryAlert(original.id);
      expect(alerts.scheduled.length, scheduled);
      expect(alerts.cancelled.last, original.id);
      expect(await db.select(db.cookTimers).get(), isEmpty);
    },
  );

  test('invalid time leaves stored state and alerts unchanged', () async {
    final CookTimerRow before = (await db.select(db.cookTimers).get()).single;
    await expectLater(
      control.setTimeLeft(original.id, Duration.zero),
      throwsArgumentError,
    );
    await expectLater(
      control.addTime(original.id, const Duration(minutes: -1)),
      throwsArgumentError,
    );
    expect((await db.select(db.cookTimers).get()).single, before);
    expect(alerts.cancelled, isEmpty);
    expect(alerts.scheduled, hasLength(1));
  });

  test(
    'a timer finishing during storage read restarts from the current clock',
    () async {
      now = now.add(const Duration(minutes: 9));
      store.afterRead = () => now = now.add(const Duration(minutes: 2));
      await control.addTime(original.id, const Duration(minutes: 1));
      expect(
        container.read(cookTimersProvider).value!.single.remainingAt(now),
        const Duration(minutes: 1),
      );
    },
  );

  test(
    'an edit uses current stored state even before a screen refresh',
    () async {
      now = now.add(const Duration(minutes: 3));
      await store.updateExisting(original.pausedAt(now));
      await control.addTime(original.id, const Duration(minutes: 5));
      final CookTimer current = container
          .read(cookTimersProvider)
          .value!
          .single;
      expect(current.isPaused, isTrue);
      expect(current.remainingAt(now), const Duration(minutes: 12));
      expect(alerts.scheduled, hasLength(1));
    },
  );

  test(
    'a failed write leaves the timer and existing alert untouched',
    () async {
      store.failUpdate = true;
      await expectLater(
        control.addTime(original.id, const Duration(minutes: 1)),
        throwsA(isA<Exception>()),
      );
      expect(
        container.read(cookTimersProvider).value!.single.duration,
        original.duration,
      );
      expect(alerts.cancelled, isEmpty);
      store.failUpdate = false;
      await control.addTime(original.id, const Duration(minutes: 1));
      expect(
        container.read(cookTimersProvider).value!.single.duration,
        const Duration(minutes: 11),
      );
    },
  );

  test('a failed cancellation can retry against the saved timer', () async {
    alerts.failCancel = true;
    await expectLater(
      control.addTime(original.id, const Duration(minutes: 1)),
      throwsA(isA<CookTimerAlertFailure>()),
    );
    expect(
      container.read(cookTimersProvider).value!.single.duration,
      const Duration(minutes: 11),
    );
    alerts.failCancel = false;
    await control.retryAlert(original.id);
    expect(alerts.cancelled, <String>[original.id]);
    expect(alerts.firesAt.last.toUtc(), now.add(const Duration(minutes: 11)));
  });
}

class _ObservedStore extends CookTimerStore {
  _ObservedStore(super.db);
  void Function()? afterRead;
  bool failUpdate = false;

  @override
  Future<List<CookTimer>> all({required DateTime now}) async {
    final List<CookTimer> timers = await super.all(now: now);
    afterRead?.call();
    return timers;
  }

  @override
  Future<bool> updateExisting(CookTimer timer) {
    if (failUpdate) throw Exception('Storage unavailable');
    return super.updateExisting(timer);
  }
}

class _FailingAlerts extends FakeTimerAlerts {
  bool failSchedule = false;
  bool failCancel = false;

  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw Exception('Cancellation unavailable');
    await super.cancel(id);
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (failSchedule) throw Exception('Alert unavailable');
    await super.schedule(id: id, title: title, body: body, at: at);
  }
}
