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
  CookTimerStore get _store => ref.read(cookTimerStoreProvider);
  TimerAlerts get _alerts => ref.read(timerAlertsProvider);

  @override
  Future<List<CookTimer>> build() => _store.all(now: DateTime.now());

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
  Future<void> start(CookTimer timer, {String? recipeTitle}) async {
    final String? stepId = timer.stepId;
    if (stepId != null && forStep(stepId) != null) return;

    await _store.upsert(timer, recipeTitle: recipeTitle);
    await _reload();

    final DateTime? fires = timer.firesAt();
    if (fires != null) {
      await _alerts.schedule(
        id: timer.id,
        title: timer.label,
        body: 'Your timer is up.',
        at: fires,
      );
    }
  }

  Future<void> dismiss(String id) async {
    await _store.delete(id);
    await _alerts.cancel(id);
    await _reload();
  }

  /// Pauses or resumes, rewriting the scheduled alert to match.
  ///
  /// A paused timer that still goes off is worse than no timer at all, and a
  /// resumed one whose alert was never rescheduled is silently dead.
  Future<void> togglePause(CookTimer timer) async {
    final DateTime now = DateTime.now();
    final CookTimer updated = timer.isPaused
        ? timer.resumedAt(now)
        : timer.pausedAt(now);

    await _store.upsert(updated);
    await _alerts.cancel(timer.id);
    final DateTime? fires = updated.firesAt();
    if (fires != null) {
      await _alerts.schedule(
        id: updated.id,
        title: updated.label,
        body: 'Your timer is up.',
        at: fires,
      );
    }
    await _reload();
  }

  Future<void> dismissAll() async {
    await _store.clear();
    await _alerts.cancelAll();
    await _reload();
  }

  Future<void> _reload() async => state = AsyncValue<List<CookTimer>>.data(
    await _store.all(now: DateTime.now()),
  );
}
