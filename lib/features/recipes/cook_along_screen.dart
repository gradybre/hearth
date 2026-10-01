import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/kitchen_devices.dart';
import '../../data/local/cook_session_store.dart';
import '../../domain/cooking/cook_session.dart';
import '../../domain/format/food_quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import 'cook_instruction_blocks.dart';
import 'step_amounts.dart';
import 'timer_bar.dart';

/// Cooking a recipe, step by step (spec §5.2).
///
/// Built for messy hands at arm's length: one step in focus at kitchen type
/// size, tap-anywhere-to-advance, tap targets well over the minimum, and the
/// screen held awake for the duration.
///
/// The recipe is snapshotted when the screen opens. A partner editing the
/// shared recipe mid-cook cannot move step 4 while you are reading it.
class CookAlongScreen extends ConsumerStatefulWidget {
  const CookAlongScreen({required this.recipe, super.key});

  final Recipe recipe;

  @override
  ConsumerState<CookAlongScreen> createState() => _CookAlongScreenState();
}

enum _CookProgressRead { loading, failed, retrying, ready }

class _CookAlongScreenState extends ConsumerState<CookAlongScreen> {
  late CookSession _session = CookSession(recipe: widget.recipe);
  late final ValueNotifier<CookSession> _sessionChanges;
  final ValueNotifier<_CookProgressRead> _progressRead =
      ValueNotifier<_CookProgressRead>(_CookProgressRead.loading);
  bool _readInFlight = false;

  // A cook can start tapping before the local read finishes. Remember the
  // choices they actually made, then apply those over the saved state. Merely
  // skipping restoration would lose untouched checks from the previous visit.
  bool _restoring = true;
  bool _editedWhileRestoring = false;
  int _progressEditRevision = 0;
  bool _ignoreSavedProgress = false;
  bool _resetPending = false;
  bool _resetInFlight = false;
  bool _ingredientsResetWhileRestoring = false;
  int? _stepChosenWhileRestoring;
  final Map<String, bool> _stepChecksWhileRestoring = <String, bool>{};
  final Map<String, bool> _ingredientChecksWhileRestoring = <String, bool>{};

  /// The recipe's sections by id, so a step can look up the ingredients of
  /// its own section — and only its own. Two teaspoons in the sauce and two
  /// in the rub must read as two in each place.
  late final Map<String, RecipeSection> _sectionsById = <String, RecipeSection>{
    for (final RecipeSection section in widget.recipe.sections)
      section.id: section,
  };
  Timer? _tick;
  bool _askedPermission = false;

  // Read once in initState and held, not read from `ref` on the way out:
  // `ref` is unsafe once the widget is being unmounted, and dispose is exactly
  // where the screen has to be handed back. Eagerly, not `late` — a lazy field
  // would still be touched for the first time inside dispose.
  late final ScreenKeeper _screen;
  late final TimerAlerts _alerts;
  late final CookSessionStore _sessions;

  @override
  void initState() {
    super.initState();
    _screen = ref.read(screenKeeperProvider);
    _alerts = ref.read(timerAlertsProvider);
    _sessions = ref.read(cookSessionStoreProvider);
    _sessionChanges = ValueNotifier<CookSession>(_session);
    _screen.keepAwake();
    _restore();
    // One second is enough to move a countdown; the remaining time itself is
    // wall-clock, so a missed tick costs nothing but a late repaint.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sessionChanges.dispose();
    _progressRead.dispose();
    // The screen is handed back however cook mode closes, including a back
    // gesture — a phone left awake in a pocket is a flat battery by evening.
    //
    // The timers are deliberately NOT cancelled here. Leaving the recipe to
    // glance at the planner must not throw away the braise you have had on for
    // an hour; they live in [cookTimersProvider] and outlive this screen.
    _screen.release();
    super.dispose();
  }

  /// Picks the cook back up where it was left.
  ///
  /// A ticked list is a record of what has already happened at the stove; it
  /// cannot be reconstructed from anywhere else, so losing it to a stray back
  /// gesture would mean guessing at what you had already done.
  Future<void> _restore() async {
    if (_readInFlight || !_restoring) return;
    _readInFlight = true;
    if (_progressRead.value == _CookProgressRead.failed) {
      _setProgressRead(_CookProgressRead.retrying);
    }
    final Recipe snapshot = _session.recipe;
    try {
      await _sessions.runInOrder(snapshot.id, () async {
        if (_ignoreSavedProgress) return;
        final StoredCookProgress? saved = await _sessions.read(
          snapshot.id,
          now: DateTime.now(),
        );
        if (_ignoreSavedProgress) return;
        if (saved != null) {
          _publishSession(
            CookSession(
              recipe: snapshot,
              // Clamped: the recipe may have been edited since, and a step
              // index past the end would leave nothing to show.
              currentStep: (_stepChosenWhileRestoring ?? saved.currentStep)
                  .clamp(
                    0,
                    snapshot.allSteps.isEmpty
                        ? 0
                        : snapshot.allSteps.length - 1,
                  ),
              // Checks for steps that no longer exist would count towards
              // "done" invisibly, so only restore IDs in this snapshot.
              checkedStepIds: <String>{
                for (final RecipeStep step in snapshot.allSteps)
                  if (_stepChecksWhileRestoring[step.id] ??
                      saved.checkedStepIds.contains(step.id))
                    step.id,
              },
              checkedIngredientIds: <String>{
                for (final RecipeIngredient ingredient
                    in snapshot.allIngredients)
                  if (_ingredientChecksWhileRestoring[ingredient.id] ??
                      (!_ingredientsResetWhileRestoring &&
                          saved.checkedIngredientIds.contains(ingredient.id)))
                    ingredient.id,
              },
              timers: _session.timers,
            ),
          );
        }
        // Keep this recipe's queue until every choice made during the read or
        // a slow save has reached storage, even if this visit has closed.
        while (_editedWhileRestoring && !_ignoreSavedProgress) {
          final int revision = _progressEditRevision;
          await _save(_session);
          if (revision == _progressEditRevision) break;
        }
        if (_ignoreSavedProgress) return;
        _restoring = false;
        _setProgressRead(_CookProgressRead.ready);
      });
    } catch (_) {
      // A failed read or flush is not an empty session. Keep collecting
      // choices until a retry can merge them with unseen saved progress.
      if (!_ignoreSavedProgress) _setProgressRead(_CookProgressRead.failed);
    } finally {
      _readInFlight = false;
    }
  }

  void _setProgressRead(_CookProgressRead state) {
    if (!mounted || _progressRead.value == state) return;
    setState(() {});
    _progressRead.value = state;
  }

  Widget? get _restoreFeedback => switch (_progressRead.value) {
    _CookProgressRead.failed => _CookRestoreFeedback(
      onRetry: _resetPending ? _persistReset : _restore,
      resetPending: _resetPending,
    ),
    _CookProgressRead.retrying => _CookRestoreFeedback(
      resetPending: _resetPending,
    ),
    _ => null,
  };

  /// Changes write through as soon as the opening read has resolved. Earlier
  /// taps are held for that read so they cannot erase unseen saved progress.
  void _update(CookSession session) {
    if (_restoring) {
      _editedWhileRestoring = true;
      _progressEditRevision++;
      if (session.currentStep != _session.currentStep) {
        _stepChosenWhileRestoring = session.currentStep;
      }
      _rememberChecks(
        _session.checkedStepIds,
        session.checkedStepIds,
        _stepChecksWhileRestoring,
      );
      _rememberChecks(
        _session.checkedIngredientIds,
        session.checkedIngredientIds,
        _ingredientChecksWhileRestoring,
      );
    }
    _publishSession(session);
    if (!_restoring) {
      unawaited(_sessions.runInOrder(session.recipe.id, () => _save(session)));
    }
  }

  static void _rememberChecks(
    Set<String> before,
    Set<String> after,
    Map<String, bool> choices,
  ) {
    for (final String id in <String>{...before, ...after}) {
      if (before.contains(id) != after.contains(id)) {
        choices[id] = after.contains(id);
      }
    }
  }

  void _publishSession(CookSession session) {
    _session = session;
    if (!mounted) return;
    setState(() {});
    _sessionChanges.value = session;
  }

  Future<void> _save(CookSession session) => _sessions.save(
    recipeId: session.recipe.id,
    currentStep: session.currentStep,
    checkedStepIds: session.checkedStepIds,
    checkedIngredientIds: session.checkedIngredientIds,
    now: DateTime.now(),
  );

  void _resetIngredients() {
    if (_restoring) _ingredientsResetWhileRestoring = true;
    _update(_session.resetIngredients());
  }

  /// Back to the top, with nothing ticked and nothing cooking.
  Future<void> _reset() async {
    // Invalidate the read before either asynchronous clear can yield.
    _ignoreSavedProgress = true;
    _restoring = true;
    _resetPending = true;
    // A second Start over while a save is pending must flush its empty state
    // too, rather than letting that earlier save bring checks back.
    _editedWhileRestoring = _resetInFlight;
    _progressEditRevision++;
    final Future<void> dismissTimers = ref
        .read(cookTimersProvider.notifier)
        .dismissAll();
    // Reset the screen and timers immediately. Keep new choices here until
    // clear and their save succeed, so a failed reset can be retried safely.
    _setProgressRead(_CookProgressRead.ready);
    _publishSession(CookSession(recipe: _session.recipe));
    await Future.wait(<Future<void>>[_persistReset(), dismissTimers]);
  }

  Future<void> _persistReset() async {
    if (_resetInFlight || !_resetPending) return;
    _resetInFlight = true;
    if (_progressRead.value == _CookProgressRead.failed) {
      _setProgressRead(_CookProgressRead.retrying);
    }
    final String recipeId = _session.recipe.id;
    try {
      await _sessions.runInOrder(recipeId, () async {
        await _sessions.clear(recipeId);
        while (_editedWhileRestoring) {
          final int revision = _progressEditRevision;
          await _save(_session);
          if (revision == _progressEditRevision) break;
        }
        _resetPending = false;
        _restoring = false;
        _setProgressRead(_CookProgressRead.ready);
      });
    } catch (_) {
      _setProgressRead(_CookProgressRead.failed);
    } finally {
      _resetInFlight = false;
    }
  }

  Future<void> _confirmReset() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            // Scrolls, so the buttons stay reachable when the type is turned up (§6.3).
            scrollable: true,
            title: const Text('Start this recipe over?'),
            content: const Text(
              'Clears all ingredient and direction checks and stops all '
              'running timers.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Start over'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _reset();
  }

  Future<void> _startTimer(RecipeStep step) async {
    // Asked at the stove, when the first timer starts — a permission prompt on
    // first launch is noise the user cannot yet evaluate.
    if (!_askedPermission) {
      _askedPermission = true;
      await _alerts.requestPermission();
    }

    await ref
        .read(cookTimersProvider.notifier)
        .start(
          CookTimer(
            id: const Uuid().v4(),
            label: _shortLabel(step.text),
            duration: Duration(seconds: step.timerSeconds!),
            startedAt: DateTime.now(),
            stepId: step.id,
            stepNumber: step.stepNumber,
          ),
          recipeTitle: widget.recipe.title,
        );
  }

  Future<void> _dismissTimer(CookTimer timer) =>
      ref.read(cookTimersProvider.notifier).dismiss(timer.id);

  Future<void> _togglePause(CookTimer timer) =>
      ref.read(cookTimersProvider.notifier).togglePause(timer);

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Widget? restoreFeedback = _restoreFeedback;
    // Two different jobs: the card is for cooking, the list is for scanning
    // ahead and seeing what is left. Remembered across launches — a cook who
    // wants the whole list should not have to say so every time.
    final bool showAllSteps =
        ref.watch(cookShowAllStepsProvider).value ?? false;
    final RecipeStep? step = _session.step;
    final Map<String, Food> foods = <String, Food>{
      for (final Food food
          in _session.recipe.allIngredients.any((i) => i.foodId != null)
              ? ref.watch(foodLibraryProvider).value ?? const <Food>[]
              : const <Food>[])
        food.id: food,
    };
    final DateTime now = DateTime.now();
    // Timers come from the app-wide store, not from the session: they are
    // shared with the rest of the app and survive this screen closing.
    final List<CookTimer> timers =
        ref.watch(cookTimersProvider).value ?? const <CookTimer>[];
    final List<CookTimer> ringing = _session
        .copyWithTimers(timers)
        .ringingAt(now);
    // One timer per step, so the controls can show the countdown in place
    // rather than offering to start a second one.
    final Map<String, CookTimer> timerByStep = <String, CookTimer>{
      for (final CookTimer timer in timers)
        if (timer.stepId != null) timer.stepId!: timer,
    };

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        // One way out, not two: the explicit close below reads as "finish
        // cooking", and a second chevron beside it only invites the question
        // of whether they do different things.
        automaticallyImplyLeading: false,
        title: Text(widget.recipe.title, style: context.text.label),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Start over',
            // Nothing to undo, nothing to offer: a live control that would
            // pop a confirmation and then do nothing is just a trap.
            onPressed:
                _session.checkedCount == 0 &&
                    _session.checkedIngredientCount == 0 &&
                    _session.currentStep == 0 &&
                    (ref.watch(cookTimersProvider).value ?? const <CookTimer>[])
                        .isEmpty
                ? null
                : _confirmReset,
          ),
          IconButton(
            icon: Icon(
              // A "1" in a box against a numbered list: the two icons say
              // one-at-a-time and all-of-them without a word. An empty
              // rectangle said nothing at all.
              showAllSteps
                  ? Icons.looks_one_outlined
                  : Icons.format_list_numbered,
            ),
            tooltip: showAllSteps ? 'One step at a time' : 'All steps',
            // The only way between the two views. Rows used to double as a
            // way back into the card, which made a tap mean two things
            // depending on where it landed.
            onPressed: () =>
                ref.read(cookShowAllStepsProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Ingredients',
            onPressed: () => _showIngredients(context),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Finish cooking',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: step == null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ?restoreFeedback,
                      Text(
                        'This recipe has no steps to cook along with.',
                        style: context.text.body,
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  for (final CookTimer timer in ringing)
                    _RingingBanner(
                      timer: timer,
                      now: now,
                      onDismiss: () => _dismissTimer(timer),
                    ),
                  if (showAllSteps) _Progress(session: _session),
                  Expanded(
                    child: showAllSteps
                        ? _StepList(
                            session: _session,
                            recipe: widget.recipe,
                            sections: _sectionsById,
                            timerByStep: timerByStep,
                            foods: foods,
                            restoreFeedback: restoreFeedback,
                            // Anywhere on the row ticks the step off. Nothing
                            // in the list navigates: the toggle above is the
                            // only way between the two views, so a tap here
                            // always means the same thing.
                            onCheck: (RecipeStep s) =>
                                _update(_session.toggle(s, advance: false)),
                            onStartTimer: _startTimer,
                          )
                        : _StepCard(
                            progress: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                ?restoreFeedback,
                                _Progress(session: _session, focused: true),
                              ],
                            ),
                            step: step,
                            section: _sectionsById[step.sectionId],
                            recipe: widget.recipe,
                            foods: foods,
                            isChecked: _session.isChecked(step),
                            onAdvance: () => _update(_session.next()),
                            onCheck: () => _update(_session.toggle(step)),
                            runningTimer: timerByStep[step.id],
                            now: now,
                            onStartTimer: step.hasTimer
                                ? () => _startTimer(step)
                                : null,
                          ),
                  ),
                  if (timers.isNotEmpty)
                    _TimerTray(
                      timers: timers,
                      now: now,
                      onPause: _togglePause,
                      onDismiss: _dismissTimer,
                    ),
                  // Back and Next mean nothing when every step is on screen.
                  if (!showAllSteps)
                    _Controls(
                      session: _session,
                      onBack: () => _update(_session.previous()),
                      onNext: () => _update(_session.next()),
                    ),
                ],
              ),
      ),
    );
  }

  void _showIngredients(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => ValueListenableBuilder<_CookProgressRead>(
      valueListenable: _progressRead,
      builder: (BuildContext context, _CookProgressRead state, Widget? child) =>
          ValueListenableBuilder<CookSession>(
            valueListenable: _sessionChanges,
            builder:
                (
                  BuildContext context,
                  CookSession session,
                  Widget? child,
                ) => _IngredientSheet(
                  // From the snapshot, not the library — mid-cook is the wrong
                  // moment to find out the list has changed underneath you.
                  session: session,
                  onToggle: (RecipeIngredient ingredient) =>
                      _update(_session.toggleIngredient(ingredient)),
                  onReset: _resetIngredients,
                  restoreFeedback: _restoreFeedback,
                  foods: <String, Food>{
                    for (final Food food
                        in _session.recipe.allIngredients.any(
                              (i) => i.foodId != null,
                            )
                            ? ref.read(foodLibraryProvider).value ??
                                  const <Food>[]
                            : const <Food>[])
                      food.id: food,
                  },
                ),
          ),
    ),
  );

  /// A short name for the timer and its notification.
  ///
  /// Truncated rather than split on punctuation: splitting turned "Cover and
  /// cook for approx. 3 hr." into "Cover and cook for approx", which is both
  /// ugly and missing the part that matters.
  static String _shortLabel(String text) {
    final String tidy = text.trim();
    return tidy.length <= 40 ? tidy : '${tidy.substring(0, 39)}…';
  }
}

/// A duration named the way a cook would say it — a braise is "3 hr", never
/// "180 min".
String _duration(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  final int seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
  if (minutes == 0) return '${seconds}s';
  if (seconds == 0) return '$minutes min';
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _Progress extends StatelessWidget {
  const _Progress({required this.session, this.focused = false});

  final CookSession session;

  /// True for the single active step view; false for the compact
  /// "All steps" list, which must keep its original centred look.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String label = session.checkedCount > 0
        ? 'Step ${session.currentStep + 1} of ${session.stepCount}'
              '  ·  ${session.checkedCount} done'
        : 'Step ${session.currentStep + 1} of ${session.stepCount}';

    if (focused) {
      return Text(
        label,
        textAlign: TextAlign.left,
        style: context.text.metadata.copyWith(
          color: colors.textMuted,
          fontSize: 17,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.lg,
        HearthSpacing.md,
        HearthSpacing.lg,
        0,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: context.text.metadata.copyWith(color: colors.textMuted),
      ),
    );
  }
}

/// Every step at once (spec §5.2).
///
/// The card is for cooking; this is for scanning — what is coming, what is
/// left, and getting straight to a step rather than tapping through to it.
class _StepList extends StatelessWidget {
  const _StepList({
    required this.session,
    required this.sections,
    required this.recipe,
    required this.timerByStep,
    required this.onCheck,
    required this.onStartTimer,
    this.foods,
    this.restoreFeedback,
  });

  final CookSession session;

  /// See [StepAmounts.recipe].
  final Recipe recipe;

  /// The recipe's sections by id, so a step can say how much of its own
  /// section's ingredients it uses.
  final Map<String, RecipeSection> sections;

  final Map<String, CookTimer> timerByStep;
  final ValueChanged<RecipeStep> onCheck;
  final ValueChanged<RecipeStep> onStartTimer;

  /// The household's food library, keyed by id — one snapshot from the
  /// screen, so the matched-food display preference (spec R1–R8) is resolved
  /// without a per-row lookup.
  final Map<String, Food>? foods;
  final Widget? restoreFeedback;

  @override
  Widget build(BuildContext context) {
    final List<RecipeStep> steps = session.steps;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.lg,
        HearthSpacing.md,
        HearthSpacing.lg,
        HearthSpacing.lg,
      ),
      itemCount: steps.length + (restoreFeedback == null ? 0 : 1),
      itemBuilder: (BuildContext context, int index) {
        if (restoreFeedback != null && index == 0) return restoreFeedback!;
        final int stepIndex = index - (restoreFeedback == null ? 0 : 1);
        final RecipeStep step = steps[stepIndex];
        return _StepListRow(
          step: step,
          section: sections[step.sectionId],
          recipe: recipe,
          isChecked: session.isChecked(step),
          isCurrent: stepIndex == session.currentStep,
          isTimerRunning: timerByStep.containsKey(step.id),
          onCheck: () => onCheck(step),
          onStartTimer: step.hasTimer ? () => onStartTimer(step) : null,
          foods: foods,
        );
      },
    );
  }
}

class _StepListRow extends StatelessWidget {
  const _StepListRow({
    required this.step,
    required this.section,
    required this.recipe,
    required this.isChecked,
    required this.isCurrent,
    required this.isTimerRunning,
    required this.onCheck,
    this.onStartTimer,
    this.foods,
  });

  final RecipeStep step;
  final RecipeSection? section;

  /// Carried so a step can still find an ingredient an import filed under a
  /// different heading — see [StepAmounts.recipe].
  final Recipe recipe;
  final bool isChecked;
  final bool isCurrent;

  /// This step already has a timer going, so it is not offered another.
  final bool isTimerRunning;

  final VoidCallback onCheck;
  final VoidCallback? onStartTimer;

  /// The household's food library, keyed by id — see [_StepList.foods].
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        // A checkbox, not a button: the whole row does one thing, and that is
        // what it should announce itself as.
        checked: isChecked,
        selected: isCurrent,
        label:
            'Step ${step.stepNumber}. ${step.text}.'
            '${isCurrent ? ' Current step.' : ''}',
        onTap: onCheck,
        excludeSemantics: true,
        child: Material(
          color: isCurrent ? colors.surfaceSunken : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onCheck,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  // The step you are on carries a heavier edge as well as a
                  // fill, so it is not marked by colour alone (spec §6.3).
                  color: isCurrent ? colors.outlineStrong : colors.outline,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Shows the state; it is not its own target. The row is one
                  // control, and a button inside it would swallow taps that
                  // landed on the icon and pass the rest through.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HearthSpacing.sm,
                      vertical: HearthSpacing.sm,
                    ),
                    child: Icon(
                      isChecked
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isChecked ? colors.accent : colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.xs),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: HearthSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${step.stepNumber}.  ${step.text}',
                            style: context.text.ingredient.copyWith(
                              fontSize: 17,
                              height: 1.35,
                              color: isChecked
                                  ? colors.textMuted
                                  : colors.textPrimary,
                            ),
                          ),
                          if (section case final RecipeSection s)
                            StepAmounts(
                              step: step,
                              section: s,
                              recipe: recipe,
                              foods: foods,
                            ),
                          if (onStartTimer != null &&
                              !isTimerRunning) ...<Widget>[
                            const SizedBox(height: HearthSpacing.sm),
                            _TimerChip(
                              label:
                                  'Start '
                                  '${_duration(Duration(seconds: step.timerSeconds!))} '
                                  'timer',
                              onPressed: onStartTimer!,
                            ),
                          ] else if (isTimerRunning) ...<Widget>[
                            const SizedBox(height: HearthSpacing.sm),
                            Text(
                              'Timer running',
                              style: context.text.metadata.copyWith(
                                color: context.colors.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: label,
        onTap: onPressed,
        excludeSemantics: true,
        child: Material(
          color: colors.background,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: HearthTouch.minTarget,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.timer_outlined, size: 18, color: colors.accent),
                  const SizedBox(width: HearthSpacing.sm),
                  Flexible(child: Text(label, style: context.text.label)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.progress,
    required this.step,
    required this.section,
    required this.recipe,
    required this.isChecked,
    required this.onAdvance,
    required this.onCheck,
    required this.now,
    this.runningTimer,
    this.onStartTimer,
    this.foods,
  });

  final Widget progress;
  final RecipeStep step;
  final RecipeSection? section;

  /// See [StepAmounts.recipe].
  final Recipe recipe;
  final bool isChecked;
  final VoidCallback onAdvance;
  final VoidCallback onCheck;
  final DateTime now;

  /// The timer already running for this step, if any.
  final CookTimer? runningTimer;

  final VoidCallback? onStartTimer;

  /// The household's food library, keyed by id — see [_StepList.foods].
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    // Deterministic presentation split only; storage and the original
    // full text are untouched. `cookInstructionBlocks` is authored and
    // imported separately.
    final List<String> blocks = cookInstructionBlocks(step.text);
    final Color textColor = isChecked ? colors.textMuted : colors.textPrimary;

    final List<Widget> paragraphs = <Widget>[
      for (int i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0 : 18),
          child: Text(
            blocks[i],
            textAlign: TextAlign.left,
            // Kitchen-first legibility: read at arm's length across a
            // counter (spec §6.1). All paragraphs share one size,
            // weight and colour; the split is visual only.
            style: context.text.body.copyWith(
              fontSize: 24,
              height: 1.4,
              color: textColor,
            ),
          ),
        ),
    ];

    final Widget content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Scroll the label too, leaving room for controls at large type.
            progress,
            const SizedBox(height: HearthSpacing.lg),
            // The visual paragraphs and the tap-to-advance action
            // collapse into one semantics node carrying the original,
            // unsplit instruction text and label: exposing each
            // paragraph `Text` a second time would announce the step
            // multiple times.
            Semantics(
              button: true,
              label: 'Step ${step.stepNumber}. ${step.text}. Tap to go on.',
              onTap: onAdvance,
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: paragraphs,
              ),
            ),
            // Ingredients remain separately reachable by assistive technology.
            if (section case final RecipeSection s)
              StepAmounts(
                step: step,
                section: s,
                recipe: recipe,
                forCooking: true,
                foods: foods,
              ),
          ],
        ),
      ),
    );
    final List<Widget> actions = <Widget>[
      if (onStartTimer != null) ...<Widget>[
        const SizedBox(height: HearthSpacing.md),
        if (runningTimer == null)
          _BigButton(
            label:
                'Start ${_duration(Duration(seconds: step.timerSeconds!))} timer',
            icon: Icons.timer_outlined,
            filled: false,
            onPressed: onStartTimer!,
          )
        else
          _RunningTimerLabel(timer: runningTimer!, now: now),
      ],
      const SizedBox(height: HearthSpacing.md),
      _BigButton(
        label: isChecked ? 'Done' : 'Mark done',
        icon: isChecked ? Icons.check_circle : Icons.check_circle_outline,
        filled: !isChecked,
        onPressed: onCheck,
      ),
    ];
    return GestureDetector(
      onTap: onAdvance,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // On a short screen or at large type, keep actions in the same
          // scroll area so they cannot squeeze the ingredients out of view.
          final bool scrollActions =
              constraints.maxHeight < 400 ||
              MediaQuery.textScalerOf(context).scale(18) > 27;
          if (scrollActions) {
            return SingleChildScrollView(
              key: ValueKey<String>('cook-scroll-${step.id}'),
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Column(children: <Widget>[content, ...actions]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  // Top-anchored at every height, not vertically centred:
                  // short content should sit at the top of the reading
                  // column rather than floating mid-screen.
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      key: ValueKey<String>('cook-scroll-${step.id}'),
                      child: content,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A control sized for messy hands — well past the 44pt minimum (spec §6.3).
class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return ConstrainedBox(
      // minHeight, not a fixed height: at large text scale the label may
      // need a second line, and a fixed height was clipping/overflowing
      // the row (169px right overflow at textScale 3).
      constraints: const BoxConstraints(minHeight: HearthTouch.kitchenTarget),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: filled ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: filled ? colors.accent : colors.outline,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.md,
                vertical: HearthSpacing.sm,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: filled ? colors.onAccent : colors.accent),
                  const SizedBox(width: HearthSpacing.sm),
                  // Flexible + wrap so the label wraps to a second line at
                  // large text scale instead of overflowing past the
                  // button's right edge.
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: context.text.label.copyWith(
                        fontSize: 18,
                        color: filled ? colors.onAccent : colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.session,
    required this.onBack,
    required this.onNext,
  });

  final CookSession session;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      HearthSpacing.lg,
      0,
      HearthSpacing.lg,
      HearthSpacing.lg,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: _NavButton(
            label: 'Back',
            icon: Icons.arrow_back,
            onPressed: session.isFirstStep ? null : onBack,
          ),
        ),
        const SizedBox(width: HearthSpacing.md),
        Expanded(
          child: _NavButton(
            label: 'Next',
            icon: Icons.arrow_forward,
            onPressed: session.isLastStep ? null : onNext,
          ),
        ),
      ],
    ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.icon, this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // minHeight, not a fixed height, matching _BigButton — the label may
    // need to wrap to a second line inside the Expanded half-width slot at
    // large text scale.
    constraints: const BoxConstraints(minHeight: HearthTouch.kitchenTarget),
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.md,
          vertical: HearthSpacing.sm,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: HearthSpacing.sm,
        children: <Widget>[
          Icon(icon),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.text.label.copyWith(fontSize: 17),
          ),
        ],
      ),
    ),
  );
}

class _RingingBanner extends StatelessWidget {
  const _RingingBanner({
    required this.timer,
    required this.now,
    required this.onDismiss,
  });

  final CookTimer timer;
  final DateTime now;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Duration over = timer.overdueBy(now);

    return Semantics(
      liveRegion: true,
      label: '${timer.label} timer is up',
      child: Container(
        width: double.infinity,
        color: colors.accent,
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(Icons.notifications_active, color: colors.onAccent),
            const SizedBox(width: HearthSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${timer.label} — time is up',
                    style: context.text.label.copyWith(color: colors.onAccent),
                  ),
                  // How long ago it went off, so a cook who missed the alert
                  // knows whether it was thirty seconds or ten minutes.
                  if (over.inSeconds >= 30)
                    Text(
                      '${countdown(over)} ago',
                      style: context.text.metadata.copyWith(
                        color: colors.onAccent,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(foregroundColor: colors.onAccent),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every running timer at once — sauce, pasta, and oven (spec §5.2).
class _TimerTray extends StatelessWidget {
  const _TimerTray({
    required this.timers,
    required this.now,
    required this.onPause,
    required this.onDismiss,
  });

  final List<CookTimer> timers;
  final DateTime now;
  final ValueChanged<CookTimer> onPause;
  final ValueChanged<CookTimer> onDismiss;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.lg,
          vertical: HearthSpacing.sm,
        ),
        children: <Widget>[
          for (final CookTimer timer in timers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
              child: Row(
                children: <Widget>[
                  Icon(
                    // Paused carries its own icon, not just a colour or a
                    // frozen number (spec §6.3).
                    timer.isPaused
                        ? Icons.pause_circle_outline
                        : Icons.timer_outlined,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      timer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.metadata,
                    ),
                  ),
                  Text(
                    countdown(timer.remainingAt(now)),
                    style: context.text.ingredient.copyWith(fontSize: 18),
                  ),
                  IconButton(
                    icon: Icon(timer.isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: timer.isPaused ? 'Resume timer' : 'Pause timer',
                    // Pausing something already finished does nothing; the
                    // only thing left to do with it is stop it.
                    onPressed: !timer.isPaused && timer.isDoneAt(now)
                        ? null
                        : () => onPause(timer),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Stop timer',
                    onPressed: () => onDismiss(timer),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Recovery stays in the content's scroll area so large text cannot squeeze
/// the directions or ingredient rows off a small screen.
class _CookRestoreFeedback extends StatelessWidget {
  const _CookRestoreFeedback({this.onRetry, this.resetPending = false});

  final VoidCallback? onRetry;
  final bool resetPending;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.lg),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(HearthSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surfaceSunken,
          border: Border.all(color: context.colors.outline),
          borderRadius: BorderRadius.circular(HearthRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              resetPending
                  ? 'Start over couldn’t be saved. Your changes aren’t saved yet.'
                  : 'Saved progress couldn’t load. Your changes aren’t saved yet.',
              style: context.text.body,
            ),
            const SizedBox(height: HearthSpacing.sm),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(HearthTouch.kitchenTarget),
                padding: const EdgeInsets.all(HearthSpacing.md),
              ),
              child: Text(
                onRetry == null
                    ? 'Retrying…'
                    : resetPending
                    ? 'Retry Start over'
                    : 'Retry saved progress',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The ingredients, on demand and pinned over the step (spec §5.2).
class _IngredientSheet extends StatelessWidget {
  const _IngredientSheet({
    required this.session,
    required this.onToggle,
    required this.onReset,
    this.foods,
    this.restoreFeedback,
  });

  final CookSession session;
  final ValueChanged<RecipeIngredient> onToggle;
  final VoidCallback onReset;
  final Widget? restoreFeedback;

  /// The household's food library, keyed by id — see [_StepList.foods].
  final Map<String, Food>? foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Recipe recipe = session.recipe;
    final List<RecipeIngredient> ingredients = recipe.allIngredients;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        child: SafeArea(
          // The heading and actions scroll with the list. Fixed chrome alone
          // can fill a small phone at 3x text, leaving no space for a row.
          child: SingleChildScrollView(
            key: const ValueKey<String>('cook-ingredient-checklist'),
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Ingredients', style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.sm),
                ?restoreFeedback,
                if (ingredients.isEmpty)
                  Text(
                    'This recipe has no ingredients listed.',
                    style: context.text.body,
                  )
                else ...<Widget>[
                  Text(
                    'Tap ingredients as you prepare or add them.',
                    style: context.text.body,
                  ),
                  const SizedBox(height: HearthSpacing.xs),
                  Text(
                    'For this cook, on this device.',
                    style: context.text.metadata,
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  Text(
                    '${session.checkedIngredientCount} of '
                    '${ingredients.length} checked',
                    style: context.text.label,
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                  for (final RecipeSection section in recipe.orderedSections)
                    if (section.ingredients.isNotEmpty) ...<Widget>[
                      if (recipe.isGrouped)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: HearthSpacing.sm,
                          ),
                          child: Text(
                            section.name,
                            style: context.text.sectionHeader,
                          ),
                        ),
                      for (final RecipeIngredient ingredient in ingredients)
                        if (ingredient.sectionId == section.id)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: HearthSpacing.sm,
                            ),
                            child: _IngredientCheckRow(
                              ingredient: ingredient,
                              food: foods?[ingredient.foodId],
                              checked: session.isIngredientChecked(ingredient),
                              onToggle: () => onToggle(ingredient),
                            ),
                          ),
                    ],
                  const SizedBox(height: HearthSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: session.checkedIngredientCount == 0
                        ? null
                        : onReset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset ingredients'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        HearthTouch.kitchenTarget,
                      ),
                      padding: const EdgeInsets.all(HearthSpacing.md),
                    ),
                  ),
                ],
                const SizedBox(height: HearthSpacing.md),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      HearthTouch.kitchenTarget,
                    ),
                    padding: const EdgeInsets.all(HearthSpacing.md),
                  ),
                  child: const Text('Back to cooking'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IngredientCheckRow extends StatelessWidget {
  const _IngredientCheckRow({
    required this.ingredient,
    required this.checked,
    required this.onToggle,
    this.food,
  });

  final RecipeIngredient ingredient;
  final Food? food;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String? quantity = ingredient.quantity == null
        ? null
        : FoodQuantityFormat.format(
            ingredient.quantity!,
            rawSources: <String>[ingredient.rawText ?? ''],
            food: food,
          );
    final String details = <String>[
      if (ingredient.prepNote?.isNotEmpty ?? false) ingredient.prepNote!,
      if (ingredient.isOptional) 'optional',
    ].join(' · ');
    final TextStyle ingredientStyle = context.text.ingredient.copyWith(
      fontSize: 22,
      height: 1.4,
      color: checked ? colors.textSecondary : colors.textPrimary,
    );

    return Semantics(
      key: ValueKey<String>('cook-ingredient-${ingredient.id}'),
      checked: checked,
      label: <String>[
        ?quantity,
        ingredient.name,
        if (details.isNotEmpty) details,
      ].join(' '),
      hint: checked
          ? 'Tap to mark not yet prepared or added.'
          : 'Tap to mark prepared or added.',
      onTap: onToggle,
      excludeSemantics: true,
      child: Material(
        color: checked ? colors.surfaceSunken : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onToggle,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: HearthTouch.kitchenTarget,
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  checked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: checked ? colors.accent : colors.textSecondary,
                  size: 28,
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // A wrapping quantity/name pair keeps both readable at
                      // kitchen sizes without reserving a fixed amount column.
                      Wrap(
                        spacing: HearthSpacing.sm,
                        children: <Widget>[
                          if (quantity != null)
                            Text(quantity, style: ingredientStyle),
                          Text(ingredient.name, style: ingredientStyle),
                        ],
                      ),
                      if (details.isNotEmpty)
                        Text(details, style: context.text.metadata),
                      if (checked)
                        Padding(
                          padding: const EdgeInsets.only(top: HearthSpacing.xs),
                          child: Text(
                            'Prepared / added',
                            style: context.text.label.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The countdown for a step that already has a timer going.
///
/// Deliberately not a button. The control that would start a second timer on
/// the same pot is replaced rather than disabled, because a disabled button
/// still reads as "this is the thing to press".
class _RunningTimerLabel extends StatelessWidget {
  const _RunningTimerLabel({required this.timer, required this.now});

  final CookTimer timer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool done = !timer.isPaused && timer.isDoneAt(now);

    return Semantics(
      liveRegion: true,
      label: done
          ? 'Timer is up'
          : 'Timer running, ${spokenDuration(timer.remainingAt(now))} left',
      excludeSemantics: true,
      child: ConstrainedBox(
        // minHeight, not a fixed height: the countdown text can outgrow a
        // fixed-height tray at large text scale and overflow past the
        // right edge (the reported 169px overflow at textScale 3).
        constraints: const BoxConstraints(minHeight: HearthTouch.kitchenTarget),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: HearthSpacing.md,
            vertical: HearthSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                done ? Icons.notifications_active : Icons.timer_outlined,
                color: colors.accent,
              ),
              const SizedBox(width: HearthSpacing.sm),
              // Flexible + wrap: lets the countdown wrap to a second line
              // at large text scale rather than clip past the tray edge.
              Flexible(
                child: Text(
                  done
                      ? 'Time is up'
                      : '${countdown(timer.remainingAt(now))} left',
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: context.text.label.copyWith(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
