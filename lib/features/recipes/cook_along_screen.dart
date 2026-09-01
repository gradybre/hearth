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
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';
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

class _CookAlongScreenState extends ConsumerState<CookAlongScreen> {
  late CookSession _session = CookSession(recipe: widget.recipe);

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
    _screen.keepAwake();
    _restore();
    // One second is enough to move a countdown; the remaining time itself is
    // wall-clock, so a missed tick costs nothing but a late repaint.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
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
    final StoredCookProgress? saved = await _sessions.read(
      widget.recipe.id,
      now: DateTime.now(),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _session = CookSession(
        recipe: widget.recipe,
        // Clamped: the recipe may have been edited since, and a step index
        // past the end would leave the screen with nothing to show.
        currentStep: saved.currentStep.clamp(
          0,
          _session.steps.isEmpty ? 0 : _session.steps.length - 1,
        ),
        // Ticks for steps that no longer exist are dropped for the same
        // reason — they would count towards "done" invisibly.
        checkedStepIds: <String>{
          for (final RecipeStep step in _session.steps)
            if (saved.checkedStepIds.contains(step.id)) step.id,
        },
      );
    });
  }

  /// Every change to where you are is written through immediately: the moment
  /// worth saving is the one just before the phone is put down.
  void _update(CookSession session) {
    setState(() => _session = session);
    _sessions.save(
      recipeId: widget.recipe.id,
      currentStep: session.currentStep,
      checkedStepIds: session.checkedStepIds,
      now: DateTime.now(),
    );
  }

  /// Back to the top, with nothing ticked and nothing cooking.
  Future<void> _reset() async {
    await _sessions.clear(widget.recipe.id);
    await ref.read(cookTimersProvider.notifier).dismissAll();
    if (!mounted) return;
    setState(() => _session = CookSession(recipe: widget.recipe));
  }

  Future<void> _confirmReset() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Start this recipe over?'),
            content: const Text(
              'Clears every tick and stops all running timers.',
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
    // Two different jobs: the card is for cooking, the list is for scanning
    // ahead and seeing what is left. Remembered across launches — a cook who
    // wants the whole list should not have to say so every time.
    final bool showAllSteps =
        ref.watch(cookShowAllStepsProvider).value ?? false;
    final RecipeStep? step = _session.step;
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
                child: Text(
                  'This recipe has no steps to cook along with.',
                  style: context.text.body,
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
                  _Progress(session: _session),
                  Expanded(
                    child: showAllSteps
                        ? _StepList(
                            session: _session,
                            recipe: widget.recipe,
                            sections: _sectionsById,
                            timerByStep: timerByStep,
                            // Anywhere on the row ticks the step off. Nothing
                            // in the list navigates: the toggle above is the
                            // only way between the two views, so a tap here
                            // always means the same thing.
                            onCheck: (RecipeStep s) =>
                                _update(_session.toggle(s, advance: false)),
                            onStartTimer: _startTimer,
                          )
                        : _StepCard(
                            step: step,
                            section: _sectionsById[step.sectionId],
                            recipe: widget.recipe,
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
    builder: (BuildContext context) => _IngredientSheet(
      // From the snapshot, not the library — mid-cook is the wrong moment to
      // find out the list has changed underneath you.
      recipe: _session.recipe,
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
  const _Progress({required this.session});

  final CookSession session;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // Centred, and on one line with the count: the step below it is centred,
    // and a lone label pinned to the left corner reads as though it belongs to
    // a different screen.
    final String label = session.checkedCount > 0
        ? 'Step ${session.currentStep + 1} of ${session.stepCount}'
              '  ·  ${session.checkedCount} done'
        : 'Step ${session.currentStep + 1} of ${session.stepCount}';

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
      itemCount: steps.length,
      itemBuilder: (BuildContext context, int index) => _StepListRow(
        step: steps[index],
        section: sections[steps[index].sectionId],
        recipe: recipe,
        isChecked: session.isChecked(steps[index]),
        isCurrent: index == session.currentStep,
        isTimerRunning: timerByStep.containsKey(steps[index].id),
        onCheck: () => onCheck(steps[index]),
        onStartTimer: steps[index].hasTimer
            ? () => onStartTimer(steps[index])
            : null,
      ),
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
                            StepAmounts(step: step, section: s, recipe: recipe),
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
                  Text(label, style: context.text.label),
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
    required this.step,
    required this.section,
    required this.recipe,
    required this.isChecked,
    required this.onAdvance,
    required this.onCheck,
    required this.now,
    this.runningTimer,
    this.onStartTimer,
  });

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

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      button: true,
      label: 'Step ${step.stepNumber}. ${step.text}. Tap to go on.',
      onTap: onAdvance,
      excludeSemantics: true,
      child: GestureDetector(
        // Tap anywhere to advance: with a hand covered in flour, aiming at a
        // button is the tax (spec §5.2).
        onTap: onAdvance,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                // The step sits in the middle of the space it has rather than
                // pinned to the top: one step in focus reads as the subject of
                // the screen, not as a caption above a lot of nothing.
                //
                // Center around the scroll view, not inside it — that way a
                // short step is centred and a long one still scrolls from the
                // top instead of being cropped at both ends.
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      // Caps the measure on a wide window. Centred text that
                      // runs the full width of a desktop screen is a chore to
                      // read back to the start of.
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            '${step.stepNumber}',
                            textAlign: TextAlign.center,
                            style: context.text.recipeTitle.copyWith(
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(height: HearthSpacing.md),
                          Text(
                            step.text,
                            textAlign: TextAlign.center,
                            // Kitchen-first legibility: read at arm's length
                            // across a counter (spec §6.1).
                            style: context.text.body.copyWith(
                              fontSize: 26,
                              height: 1.4,
                              color: isChecked
                                  ? colors.textMuted
                                  : colors.textPrimary,
                            ),
                          ),
                          // The amounts belong on this screen above all
                          // others: hands busy, and the ingredient list a
                          // whole screen away.
                          if (section case final RecipeSection s) ...<Widget>[
                            const SizedBox(height: HearthSpacing.md),
                            StepAmounts(step: step, section: s, recipe: recipe),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
                  // Shows the countdown rather than offering to start again.
                  // The control that would stack a second timer on the same
                  // pot simply is not there.
                  _RunningTimerLabel(timer: runningTimer!, now: now),
              ],
              const SizedBox(height: HearthSpacing.md),
              _BigButton(
                label: isChecked ? 'Done' : 'Mark done',
                icon: isChecked
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                filled: !isChecked,
                onPressed: onCheck,
              ),
            ],
          ),
        ),
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
    return SizedBox(
      width: double.infinity,
      height: HearthTouch.kitchenTarget,
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
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: filled ? colors.onAccent : colors.accent),
                const SizedBox(width: HearthSpacing.sm),
                Text(
                  label,
                  style: context.text.label.copyWith(
                    fontSize: 18,
                    color: filled ? colors.onAccent : colors.textPrimary,
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
  Widget build(BuildContext context) => SizedBox(
    height: HearthTouch.kitchenTarget,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: context.text.label.copyWith(fontSize: 17)),
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

/// The ingredients, on demand and pinned over the step (spec §5.2).
class _IngredientSheet extends StatelessWidget {
  const _IngredientSheet({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Text('Ingredients', style: context.text.sectionHeader),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.lg,
                  ),
                  children: <Widget>[
                    for (final RecipeIngredient ingredient
                        in recipe.allIngredients)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: HearthSpacing.sm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 110,
                              child: Text(
                                ingredient.quantity == null
                                    ? ''
                                    : QuantityFormat.formatAsAuthored(
                                        ingredient.quantity!,
                                      ),
                                style: context.text.ingredient.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                ingredient.name,
                                style: context.text.ingredient.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to cooking'),
                  ),
                ),
              ),
            ],
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
      child: Container(
        height: HearthTouch.kitchenTarget,
        alignment: Alignment.center,
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
            Text(
              done ? 'Time is up' : '${countdown(timer.remainingAt(now))} left',
              style: context.text.label.copyWith(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
