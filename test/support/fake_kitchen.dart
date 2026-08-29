import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearth/app/cook_timers.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/kitchen_devices.dart';
import 'package:hearth/data/local/cook_session_store.dart';
import 'package:hearth/domain/cooking/cook_session.dart';

/// Records what cook mode asked of the platform.
class FakeScreenKeeper implements ScreenKeeper {
  int awake = 0;
  int released = 0;

  @override
  Future<void> keepAwake() async => awake++;

  @override
  Future<void> release() async => released++;
}

class FakeTimerAlerts implements TimerAlerts {
  final List<String> scheduled = <String>[];
  final List<String> cancelled = <String>[];
  final List<DateTime> firesAt = <DateTime>[];
  int permissionRequests = 0;
  int cancelAlls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    scheduled.add(id);
    firesAt.add(at);
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAlls++;
}

/// The timer notifier with the database swapped for a list.
///
/// Widget tests run under fake async, which cannot drive real sqlite, so a
/// DB-backed notifier would never resolve and the screen would sit on its
/// spinner. Alert scheduling still goes through the real provider, so what
/// these tests assert about alerts is the real wiring; persistence is covered
/// against a real database in cook_timer_store_test.dart.
class FakeCookTimers extends CookTimersNotifier {
  FakeCookTimers([this._timers = const <CookTimer>[]]);

  List<CookTimer> _timers;

  @override
  Future<List<CookTimer>> build() async => _timers;

  @override
  Future<void> start(CookTimer timer, {String? recipeTitle}) async {
    // Mirrors the real notifier: one timer per step.
    final String? stepId = timer.stepId;
    if (stepId != null &&
        _timers.any((CookTimer existing) => existing.stepId == stepId)) {
      return;
    }
    _timers = <CookTimer>[..._timers, timer];
    final DateTime? fires = timer.firesAt();
    if (fires != null) {
      await ref
          .read(timerAlertsProvider)
          .schedule(id: timer.id, title: timer.label, body: '', at: fires);
    }
    state = AsyncValue<List<CookTimer>>.data(_timers);
  }

  @override
  Future<void> dismiss(String id) async {
    _timers = <CookTimer>[
      for (final CookTimer timer in _timers)
        if (timer.id != id) timer,
    ];
    await ref.read(timerAlertsProvider).cancel(id);
    state = AsyncValue<List<CookTimer>>.data(_timers);
  }

  @override
  Future<void> dismissAll() async {
    _timers = const <CookTimer>[];
    await ref.read(timerAlertsProvider).cancelAll();
    state = const AsyncValue<List<CookTimer>>.data(<CookTimer>[]);
  }

  @override
  Future<void> togglePause(CookTimer timer) async {
    final DateTime now = DateTime.now();
    final CookTimer updated = timer.isPaused
        ? timer.resumedAt(now)
        : timer.pausedAt(now);
    _timers = <CookTimer>[
      for (final CookTimer existing in _timers)
        if (existing.id == timer.id) updated else existing,
    ];
    final TimerAlerts alerts = ref.read(timerAlertsProvider);
    await alerts.cancel(timer.id);
    final DateTime? fires = updated.firesAt();
    if (fires != null) {
      await alerts.schedule(
        id: updated.id,
        title: updated.label,
        body: '',
        at: fires,
      );
    }
    state = AsyncValue<List<CookTimer>>.data(_timers);
  }
}

/// The cook-along view preference, held in memory.
///
/// Widget tests run under fake async and cannot drive sqlite; persistence is
/// covered against a real database in preference_store_test.dart.
class FakeCookStepView extends CookStepViewNotifier {
  FakeCookStepView([this._showAll = false]);

  bool _showAll;

  @override
  Future<bool> build() async => _showAll;

  @override
  Future<void> toggle() async {
    _showAll = !_showAll;
    state = AsyncValue<bool>.data(_showAll);
  }
}

/// The cook-session store, held in memory.
///
/// Widget tests run under fake async and cannot drive sqlite; the real store is
/// covered in cook_session_store_test.dart.
class FakeCookSessionStore implements CookSessionStore {
  FakeCookSessionStore([StoredCookProgress? saved]) : _saved = saved;

  StoredCookProgress? _saved;
  int clears = 0;
  int saves = 0;

  @override
  Future<StoredCookProgress?> read(
    String recipeId, {
    required DateTime now,
  }) async => _saved;

  @override
  Future<void> save({
    required String recipeId,
    required int currentStep,
    required Set<String> checkedStepIds,
    required DateTime now,
  }) async {
    saves++;
    _saved = StoredCookProgress(
      currentStep: currentStep,
      checkedStepIds: checkedStepIds,
    );
  }

  @override
  Future<void> clear(String recipeId) async {
    clears++;
    _saved = null;
  }
}
