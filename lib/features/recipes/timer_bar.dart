import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/cook_timers.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/cooking/cook_session.dart';

/// Running cook timers, shown from anywhere in the app (spec §5.2).
///
/// A timer you cannot see from the planner is a timer you have to remember,
/// and remembering is the job the timer was for. This sits above the tabs, so
/// stepping out of the recipe to check tomorrow's plan does not mean losing
/// sight of the pot.
class CookTimerBar extends ConsumerStatefulWidget {
  const CookTimerBar({super.key});

  @override
  ConsumerState<CookTimerBar> createState() => _CookTimerBarState();
}

class _CookTimerBarState extends ConsumerState<CookTimerBar>
    with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the lock screen or the app switcher: the ticker was
    // suspended while away, so repaint at once rather than showing a stale
    // countdown for up to a second. The value itself is wall-clock and was
    // never wrong — only the pixels were.
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<CookTimer> timers =
        ref.watch(cookTimersProvider).value ?? const <CookTimer>[];
    if (timers.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    final DateTime now = DateTime.now();
    final List<CookTimer> ringing = <CookTimer>[
      for (final CookTimer timer in timers)
        if (!timer.isPaused && timer.isDoneAt(now)) timer,
    ];
    final bool anyRinging = ringing.isNotEmpty;
    final CookTimer soonest = _soonest(timers, now);

    return Material(
      color: anyRinging ? colors.accent : colors.surfaceSunken,
      child: InkWell(
        onTap: () => showCookTimersSheet(context),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Semantics(
            button: true,
            liveRegion: anyRinging,
            label: anyRinging
                ? '${ringing.first.label} timer is up. '
                      'Open timers.'
                : '${timers.length} ${timers.length == 1 ? 'timer' : 'timers'} '
                      'running, next in ${spokenDuration(soonest.remainingAt(now))}. '
                      'Open timers.',
            excludeSemantics: true,
            onTap: () => showCookTimersSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.lg,
                vertical: HearthSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    // The state carries an icon as well as the fill, so it is
                    // not colour alone (spec §6.3).
                    anyRinging
                        ? Icons.notifications_active
                        : Icons.timer_outlined,
                    size: 20,
                    color: anyRinging ? colors.onAccent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      anyRinging
                          ? '${ringing.first.label} — time is up'
                          : soonest.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.metadata.copyWith(
                        color: anyRinging
                            ? colors.onAccent
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Text(
                    anyRinging ? 'now' : countdown(soonest.remainingAt(now)),
                    style: context.text.ingredient.copyWith(
                      fontSize: 16,
                      color: anyRinging ? colors.onAccent : colors.textPrimary,
                    ),
                  ),
                  if (timers.length > 1) ...<Widget>[
                    const SizedBox(width: HearthSpacing.sm),
                    Text(
                      '+${timers.length - 1}',
                      style: context.text.metadata.copyWith(
                        color: anyRinging ? colors.onAccent : colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one that needs attention first: anything ringing, else the least time
  /// left. Paused timers sort last — they are not waiting on anything.
  static CookTimer _soonest(List<CookTimer> timers, DateTime now) {
    final List<CookTimer> sorted = <CookTimer>[...timers]
      ..sort((CookTimer a, CookTimer b) {
        if (a.isPaused != b.isPaused) return a.isPaused ? 1 : -1;
        return a.remainingAt(now).compareTo(b.remainingAt(now));
      });
    return sorted.first;
  }
}

/// Every running timer, with the controls to pause or stop each.
Future<void> showCookTimersSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _CookTimersSheet(),
    );

class _CookTimersSheet extends ConsumerStatefulWidget {
  const _CookTimersSheet();

  @override
  ConsumerState<_CookTimersSheet> createState() => _CookTimersSheetState();
}

class _CookTimersSheetState extends ConsumerState<_CookTimersSheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final DateTime now = DateTime.now();
    final List<CookTimer> timers =
        ref.watch(cookTimersProvider).value ?? const <CookTimer>[];
    final CookTimersNotifier control = ref.read(cookTimersProvider.notifier);

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
                child: Text('Timers', style: context.text.sectionHeader),
              ),
              if (timers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.lg,
                  ),
                  child: Text(
                    'Nothing on.',
                    style: context.text.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: HearthSpacing.lg,
                    ),
                    children: <Widget>[
                      for (final CookTimer timer in timers)
                        _TimerRow(
                          timer: timer,
                          now: now,
                          onPause: () => control.togglePause(timer),
                          onStop: () => control.dismiss(timer.id),
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
                    child: const Text('Done'),
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

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.timer,
    required this.now,
    required this.onPause,
    required this.onStop,
  });

  final CookTimer timer;
  final DateTime now;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool done = !timer.isPaused && timer.isDoneAt(now);

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          border: Border.all(
            color: done ? colors.outlineStrong : colors.outline,
          ),
        ),
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(
              done
                  ? Icons.notifications_active
                  : timer.isPaused
                  ? Icons.pause_circle_outline
                  : Icons.timer_outlined,
              size: 20,
              color: done ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: HearthSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    timer.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.ingredient,
                  ),
                  if (timer.isPaused)
                    Text(
                      'Paused',
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    )
                  else if (done)
                    Text(
                      '${countdown(timer.overdueBy(now))} ago',
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              done ? 'Done' : countdown(timer.remainingAt(now)),
              style: context.text.ingredient.copyWith(fontSize: 18),
            ),
            IconButton(
              icon: Icon(timer.isPaused ? Icons.play_arrow : Icons.pause),
              tooltip: timer.isPaused ? 'Resume timer' : 'Pause timer',
              onPressed: done ? null : onPause,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Stop timer',
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

/// A countdown. Hours are broken out once there are any: "179:57" is not a
/// number anyone can read as most of three hours.
String countdown(Duration d) {
  final int hours = d.inHours;
  final String minutes = d.inMinutes.remainder(60).toString();
  final String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$seconds';
  return '$hours:${minutes.padLeft(2, '0')}:$seconds';
}

/// The same duration for a screen reader, which should not be read "two colon
/// fifty-nine colon fifty-seven".
String spokenDuration(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '$hours hours' : '$hours hours $minutes minutes';
  }
  if (minutes > 0) return '$minutes minutes';
  return '${d.inSeconds} seconds';
}
