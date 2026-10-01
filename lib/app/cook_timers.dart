import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/adapters/kitchen_devices.dart';
import '../data/local/cook_timer_store.dart';
import '../domain/cooking/cook_session.dart';
import 'providers.dart';

/// Every running cook timer, for the whole app (spec §5.2).
///
/// Deliberately **not** owned by the cook-along screen. A timer outlives the
/// screen that started it: you set a three-hour braise, back out to check the
/// planner, and the braise is still cooking. Holding the timers in the screen's
/// state meant leaving the screen threw them away, which is the one thing a
/// kitchen timer must never do.
///
/// Every change is written through to the database, so the timers also outlive
/// the *app* — force-quit, a low-memory eviction, or a phone that ran flat all
/// leave the timer intact, because what is stored is when it started, not how
/// much is left.
class CookTimersNotifier extends AsyncNotifier<List<CookTimer>> {
  CookTimersNotifier({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Future<void> _pending = Future<void>.value();

  CookTimerStore get _store => ref.read(cookTimerStoreProvider);
  TimerAlerts get _alerts => ref.read(timerAlertsProvider);

  @override
  Future<List<CookTimer>> build() => _store.all(now: _now());

  /// Reads, writes and alert changes share one queue. Two quick presses must
  /// see each other's result, and Stop must run after an in-flight edit.
  Future<T> _inOrder<T>(Future<T> Function() action) {
    final Future<T> result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// The timer already running for a step, if there is one.
  CookTimer? forStep(String stepId) {
    for (final CookTimer timer in state.value ?? const <CookTimer>[]) {
      if (timer.stepId == stepId) return timer;
    }
    return null;
  }

  /// Starts a timer and schedules the alert that will reach a cook who has put
  /// the phone down and walked away.
  ///
  /// One timer per step. Tapping the control again does nothing rather than
  /// stacking a second countdown on the same pot — three identical timers all
  /// going off a second apart is noise, and dismissing two of them while
  /// cooking is exactly the sort of fiddling this screen exists to avoid.
  /// Two *different* steps still each get their own.
  Future<void> start(CookTimer timer, {String? recipeTitle}) =>
      _inOrder(() async {
        final List<CookTimer> current = await _store.all(now: _now());
        final String? stepId = timer.stepId;
        if (current.any(
          (CookTimer existing) =>
              existing.id == timer.id ||
              (stepId != null && existing.stepId == stepId),
        )) {
          return;
        }

        await _store.upsert(timer, recipeTitle: recipeTitle);
        _publish(<CookTimer>[...current, timer]);
        await _schedule(timer);
      });

  Future<void> dismiss(String id) => _inOrder(() async {
    final List<CookTimer> current = await _store.all(now: _now());
    await _store.delete(id);
    _publish(<CookTimer>[
      for (final CookTimer timer in current)
        if (timer.id != id) timer,
    ]);
    await _replaceAlert(id, null);
  });

  /// Pauses or resumes, rewriting the scheduled alert to match.
  ///
  /// A paused timer that still goes off is worse than no timer at all, and a
  /// resumed one whose alert was never rescheduled is silently dead.
  Future<void> togglePause(CookTimer timer) async {
    await _change(timer.id, (CookTimer current, DateTime now) {
      if (!current.isPaused && current.isDoneAt(now)) return current;
      return current.isPaused ? current.resumedAt(now) : current.pausedAt(now);
    });
  }

  /// Returns false when this timer has been stopped since the control opened.
  Future<bool> addTime(String id, Duration amount) => _change(
    id,
    (CookTimer current, DateTime now) => current.addingTime(amount, now: now),
  );

  Future<bool> setTimeLeft(String id, Duration remaining) => _change(
    id,
    (CookTimer current, DateTime now) =>
        current.withTimeLeft(remaining, now: now),
  );

  Future<bool> _change(
    String id,
    CookTimer Function(CookTimer, DateTime) update,
  ) => _inOrder(() async {
    final List<CookTimer> timers = await _store.all(now: _now());
    CookTimer? current;
    for (final CookTimer timer in timers) {
      if (timer.id == id) current = timer;
    }
    if (current == null) {
      _publish(timers);
      return false;
    }
    final CookTimer changed = update(current, _now());
    if (!await _store.updateExisting(changed)) {
      _publish(<CookTimer>[
        for (final CookTimer timer in timers)
          if (timer.id != id) timer,
      ]);
      return false;
    }
    // Publish the durable result before asking the OS. An alert failure must
    // not make a successful +1 minute appear unsaved and invite a second add.
    _publish(<CookTimer>[
      for (final CookTimer timer in timers)
        if (timer.id == id) changed else timer,
    ]);
    await _replaceAlert(id, changed);
    return true;
  });

  /// Retries only the alert, using today's stored state, never the adjustment.
  Future<void> retryAlert(String id) => _inOrder(() async {
    final List<CookTimer> timers = await _store.all(now: _now());
    CookTimer? current;
    for (final CookTimer timer in timers) {
      if (timer.id == id) current = timer;
    }
    _publish(timers);
    await _replaceAlert(id, current);
  });

  Future<void> _replaceAlert(String id, CookTimer? timer) async {
    try {
      await _alerts.cancel(id);
      if (timer != null) await _schedule(timer);
    } catch (error) {
      throw CookTimerAlertFailure(id, error);
    }
  }

  Future<void> _schedule(CookTimer timer) async {
    final DateTime? fires = timer.firesAt();
    if (fires == null || !fires.isAfter(_now())) return;
    try {
      await _alerts.schedule(
        id: timer.id,
        title: timer.label,
        body: 'Your timer is up.',
        at: fires,
      );
    } catch (error) {
      throw CookTimerAlertFailure(timer.id, error);
    }
  }

  Future<void> dismissAll() => _inOrder(() async {
    await _store.clear();
    _publish(const <CookTimer>[]);
    await _alerts.cancelAll();
  });

  void _publish(List<CookTimer> timers) =>
      state = AsyncValue<List<CookTimer>>.data(timers);
}

/// The timer was saved, but its existing platform alert needs a retry.
class CookTimerAlertFailure implements Exception {
  const CookTimerAlertFailure(this.timerId, this.cause);

  final String timerId;
  final Object cause;
}
