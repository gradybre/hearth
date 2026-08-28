import 'package:meta/meta.dart';

import '../models/recipe.dart';

/// One timer in a cook session (spec §5.2).
///
/// The remaining time is derived from wall-clock arithmetic — `startedAt` plus
/// `duration` — never from a counter ticked once a frame. A ticking counter
/// stops when the app is backgrounded, which is exactly when a cook puts the
/// phone down and walks away from the pot. Deriving it means the timer is
/// right the moment the screen comes back, and right after a cold start too.
@immutable
class CookTimer {
  const CookTimer({
    required this.id,
    required this.label,
    required this.duration,
    required this.startedAt,
    this.stepNumber,
    this.elapsedWhenPaused,
  });

  final String id;

  /// What the timer is for, in the cook's words — the step it came from.
  final String label;

  final Duration duration;
  final DateTime startedAt;
  final int? stepNumber;

  /// How much had elapsed when it was paused; null while running.
  final Duration? elapsedWhenPaused;

  bool get isPaused => elapsedWhenPaused != null;

  Duration elapsedAt(DateTime now) =>
      elapsedWhenPaused ?? now.difference(startedAt);

  /// Never negative: an overdue timer reports zero left and reports itself
  /// done. How far past due it is belongs to [overdueBy].
  Duration remainingAt(DateTime now) {
    final Duration left = duration - elapsedAt(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isDoneAt(DateTime now) => elapsedAt(now) >= duration;

  /// How long ago it finished — shown so a cook who missed the alert knows
  /// whether it was thirty seconds or ten minutes.
  Duration overdueBy(DateTime now) {
    final Duration over = elapsedAt(now) - duration;
    return over.isNegative ? Duration.zero : over;
  }

  CookTimer pausedAt(DateTime now) =>
      isPaused ? this : _copy(elapsedWhenPaused: elapsedAt(now));

  /// Resuming re-anchors the start so the elapsed time is preserved rather
  /// than the timer restarting from the top.
  CookTimer resumedAt(DateTime now) => isPaused
      ? CookTimer(
          id: id,
          label: label,
          duration: duration,
          startedAt: now.subtract(elapsedWhenPaused!),
          stepNumber: stepNumber,
        )
      : this;

  /// When it will fire, for scheduling an alert that survives backgrounding.
  DateTime? firesAt() => isPaused ? null : startedAt.add(duration);

  CookTimer _copy({Duration? elapsedWhenPaused}) => CookTimer(
    id: id,
    label: label,
    duration: duration,
    startedAt: startedAt,
    stepNumber: stepNumber,
    elapsedWhenPaused: elapsedWhenPaused ?? this.elapsedWhenPaused,
  );
}

/// A cook-along in progress (spec §5.2).
///
/// The recipe held here is a *snapshot*, taken when cooking started. A partner
/// editing the shared recipe mid-cook must not change the steps under your
/// hands — you are standing at the stove following step 4, and step 4 moving
/// is worse than seeing a stale ingredient list.
@immutable
class CookSession {
  const CookSession({
    required this.recipe,
    this.currentStep = 0,
    this.checkedStepIds = const <String>{},
    this.timers = const <CookTimer>[],
  });

  /// The frozen recipe for this session.
  final Recipe recipe;

  final int currentStep;
  final Set<String> checkedStepIds;
  final List<CookTimer> timers;

  List<RecipeStep> get steps => recipe.allSteps;

  int get stepCount => steps.length;

  RecipeStep? get step => currentStep >= 0 && currentStep < steps.length
      ? steps[currentStep]
      : null;

  bool get isFirstStep => currentStep <= 0;
  bool get isLastStep => currentStep >= steps.length - 1;

  bool isChecked(RecipeStep step) => checkedStepIds.contains(step.id);

  /// Every step ticked off — the point at which the app can offer to log it.
  bool get isComplete =>
      steps.isNotEmpty && steps.every((RecipeStep s) => isChecked(s));

  int get checkedCount => steps.where(isChecked).length;

  /// Advancing past the last step stays on the last step.
  ///
  /// Tap-anywhere-to-advance means an accidental brush at the end must not
  /// throw the cook out of the session they are still using.
  CookSession next() => _copy(
    currentStep: currentStep >= steps.length - 1
        ? currentStep
        : currentStep + 1,
  );

  CookSession previous() =>
      _copy(currentStep: currentStep <= 0 ? 0 : currentStep - 1);

  CookSession goTo(int index) =>
      _copy(currentStep: index.clamp(0, steps.length - 1));

  /// Ticking a step off also moves on: checking is what a cook does when the
  /// step is finished, and making them tick *and* advance taxes every step.
  CookSession check(RecipeStep step, {bool advance = true}) {
    if (isChecked(step)) return this;
    final CookSession checked = _copy(
      checkedStepIds: <String>{...checkedStepIds, step.id},
    );
    return advance ? checked.next() : checked;
  }

  CookSession uncheck(RecipeStep step) =>
      _copy(checkedStepIds: <String>{...checkedStepIds}..remove(step.id));

  CookSession toggle(RecipeStep step, {bool advance = true}) =>
      isChecked(step) ? uncheck(step) : check(step, advance: advance);

  /// Timers run side by side — sauce, pasta, and oven at once (spec §5.2).
  CookSession addTimer(CookTimer timer) =>
      _copy(timers: <CookTimer>[...timers, timer]);

  CookSession removeTimer(String id) => _copy(
    timers: <CookTimer>[
      for (final CookTimer timer in timers)
        if (timer.id != id) timer,
    ],
  );

  CookSession replaceTimer(CookTimer timer) => _copy(
    timers: <CookTimer>[
      for (final CookTimer existing in timers)
        if (existing.id == timer.id) timer else existing,
    ],
  );

  /// Timers that have gone off, oldest first — the order they need attention.
  List<CookTimer> ringingAt(DateTime now) =>
      <CookTimer>[
        for (final CookTimer timer in timers)
          if (!timer.isPaused && timer.isDoneAt(now)) timer,
      ]..sort(
        (CookTimer a, CookTimer b) =>
            b.overdueBy(now).compareTo(a.overdueBy(now)),
      );

  /// The same session reading a different set of timers.
  ///
  /// Timers are owned app-wide rather than by the session, because they outlive
  /// the screen; this lets the session's ringing logic still be asked about
  /// them without the session having to own them.
  CookSession copyWithTimers(List<CookTimer> timers) => _copy(timers: timers);

  CookSession _copy({
    int? currentStep,
    Set<String>? checkedStepIds,
    List<CookTimer>? timers,
  }) => CookSession(
    recipe: recipe,
    currentStep: currentStep ?? this.currentStep,
    checkedStepIds: checkedStepIds ?? this.checkedStepIds,
    timers: timers ?? this.timers,
  );
}
