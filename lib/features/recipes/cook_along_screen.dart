import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/kitchen_devices.dart';
import '../../domain/cooking/cook_session.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';

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
  Timer? _tick;
  bool _askedPermission = false;

  // Read once in initState and held, not read from `ref` on the way out:
  // `ref` is unsafe once the widget is being unmounted, and dispose is exactly
  // where the screen has to be handed back. Eagerly, not `late` — a lazy field
  // would still be touched for the first time inside dispose.
  late final ScreenKeeper _screen;
  late final TimerAlerts _alerts;

  @override
  void initState() {
    super.initState();
    _screen = ref.read(screenKeeperProvider);
    _alerts = ref.read(timerAlertsProvider);
    _screen.keepAwake();
    // One second is enough to move a countdown; the remaining time itself is
    // wall-clock, so a missed tick costs nothing but a late repaint.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Both have to happen however the screen closes, including a back
    // gesture: a phone left awake in a pocket is a flat battery by evening,
    // and an alert for a timer nobody is watching is just noise.
    _screen.release();
    _alerts.cancelAll();
    super.dispose();
  }

  Future<void> _startTimer(RecipeStep step) async {
    final DateTime now = DateTime.now();
    final CookTimer timer = CookTimer(
      id: const Uuid().v4(),
      label: _shortLabel(step.text),
      duration: Duration(seconds: step.timerSeconds!),
      startedAt: now,
      stepNumber: step.stepNumber,
    );

    setState(() => _session = _session.addTimer(timer));

    final TimerAlerts alerts = _alerts;
    // Asked at the stove, when the first timer starts — a permission prompt
    // on first launch is noise the user cannot yet evaluate.
    if (!_askedPermission) {
      _askedPermission = true;
      await alerts.requestPermission();
    }
    await alerts.schedule(
      id: timer.id,
      title: timer.label,
      body: 'Your ${_duration(timer.duration)} timer is up.',
      at: timer.firesAt()!,
    );
  }

  Future<void> _dismissTimer(CookTimer timer) async {
    setState(() => _session = _session.removeTimer(timer.id));
    await _alerts.cancel(timer.id);
  }

  Future<void> _togglePause(CookTimer timer) async {
    final DateTime now = DateTime.now();
    final CookTimer updated = timer.isPaused
        ? timer.resumedAt(now)
        : timer.pausedAt(now);
    setState(() => _session = _session.replaceTimer(updated));

    final TimerAlerts alerts = _alerts;
    // The scheduled alert is rewritten, not left stale: a paused timer that
    // still goes off is worse than no timer at all.
    await alerts.cancel(timer.id);
    final DateTime? fires = updated.firesAt();
    if (fires != null) {
      await alerts.schedule(
        id: updated.id,
        title: updated.label,
        body: 'Your ${_duration(updated.duration)} timer is up.',
        at: fires,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final RecipeStep? step = _session.step;
    final DateTime now = DateTime.now();
    final List<CookTimer> ringing = _session.ringingAt(now);

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
                    child: _StepCard(
                      step: step,
                      isChecked: _session.isChecked(step),
                      onAdvance: () =>
                          setState(() => _session = _session.next()),
                      onCheck: () =>
                          setState(() => _session = _session.toggle(step)),
                      onStartTimer: step.hasTimer
                          ? () => _startTimer(step)
                          : null,
                    ),
                  ),
                  if (_session.timers.isNotEmpty)
                    _TimerTray(
                      timers: _session.timers,
                      now: now,
                      onPause: _togglePause,
                      onDismiss: _dismissTimer,
                    ),
                  _Controls(
                    session: _session,
                    onBack: () =>
                        setState(() => _session = _session.previous()),
                    onNext: () => setState(() => _session = _session.next()),
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

/// A countdown. Hours are broken out once there are any: "179:57" is not a
/// number anyone can read as most of three hours.
String _countdown(Duration d) {
  final int hours = d.inHours;
  final String minutes = d.inMinutes.remainder(60).toString();
  final String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$seconds';
  return '$hours:${minutes.padLeft(2, '0')}:$seconds';
}

class _Progress extends StatelessWidget {
  const _Progress({required this.session});

  final CookSession session;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HearthSpacing.lg,
        HearthSpacing.md,
        HearthSpacing.lg,
        0,
      ),
      child: Row(
        children: <Widget>[
          Text(
            'Step ${session.currentStep + 1} of ${session.stepCount}',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
          const Spacer(),
          if (session.checkedCount > 0)
            Text(
              '${session.checkedCount} done',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.isChecked,
    required this.onAdvance,
    required this.onCheck,
    this.onStartTimer,
  });

  final RecipeStep step;
  final bool isChecked;
  final VoidCallback onAdvance;
  final VoidCallback onCheck;
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
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${step.stepNumber}',
                        style: context.text.recipeTitle.copyWith(
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(height: HearthSpacing.md),
                      Text(
                        step.text,
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
                    ],
                  ),
                ),
              ),
              if (onStartTimer != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                _BigButton(
                  label:
                      'Start ${_duration(Duration(seconds: step.timerSeconds!))} timer',
                  icon: Icons.timer_outlined,
                  filled: false,
                  onPressed: onStartTimer!,
                ),
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
                      '${_countdown(over)} ago',
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
                    _countdown(timer.remainingAt(now)),
                    style: context.text.ingredient.copyWith(fontSize: 18),
                  ),
                  IconButton(
                    icon: Icon(timer.isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: timer.isPaused ? 'Resume timer' : 'Pause timer',
                    onPressed: () => onPause(timer),
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
