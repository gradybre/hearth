import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/cook_timers.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/cooking/cook_session.dart';

/// The same timer actions in cook-along and the app-wide timer sheet.
class CookTimerCard extends ConsumerWidget {
  const CookTimerCard({
    required this.timer,
    required this.now,
    this.prioritizeTime = false,
    this.finishedNoticeProvided = false,
    super.key,
  });

  final CookTimer timer;
  final DateTime now;

  /// Cook keeps a short tray to leave room for the recipe. Its countdown and
  /// state must appear before a label that can span many lines at large text.
  final bool prioritizeTime;

  /// Cook's fixed notice provides finished state and a named announcement.
  /// Those cards lead with elapsed time; its semantics retain their identity.
  final bool finishedNoticeProvided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final CookTimersNotifier control = ref.read(cookTimersProvider.notifier);
    final bool done = !timer.isPaused && timer.isDoneAt(now);
    final bool finishedIsSummarized = done && finishedNoticeProvided;
    final ButtonStyle actionStyle = TextButton.styleFrom(
      minimumSize: const Size(
        HearthTouch.androidTarget,
        HearthTouch.androidTarget,
      ),
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    return Container(
      key: ValueKey<String>('timer-card-${timer.id}'),
      margin: const EdgeInsets.only(bottom: HearthSpacing.sm),
      padding: const EdgeInsets.all(HearthSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: done ? colors.outlineStrong : colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!prioritizeTime) ...<Widget>[
            Text(timer.label, style: context.text.ingredient),
            const SizedBox(height: HearthSpacing.xs),
          ],
          Wrap(
            spacing: HearthSpacing.sm,
            runSpacing: HearthSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (!finishedIsSummarized) ...<Widget>[
                Icon(
                  done
                      ? Icons.notifications_active
                      : timer.isPaused
                      ? Icons.pause_circle_outline
                      : Icons.timer_outlined,
                  color: done ? colors.accent : colors.textSecondary,
                ),
                Semantics(
                  container: true,
                  liveRegion: done,
                  label: done ? '${timer.label} timer is up' : null,
                  excludeSemantics: done,
                  child: Text(
                    done
                        ? 'Time is up'
                        : timer.isPaused
                        ? 'Paused'
                        : 'Running',
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
              Semantics(
                container: finishedIsSummarized,
                child: Text(
                  done
                      ? '${countdown(timer.overdueBy(now))} ago'
                      : countdown(timer.remainingAt(now)),
                  semanticsLabel: done
                      ? '${finishedIsSummarized ? '${timer.label} timer is up. ' : ''}'
                            '${spokenDuration(timer.overdueBy(now))} ago'
                      : '${spokenDuration(timer.remainingAt(now))} left',
                  style: context.text.ingredient,
                ),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.xs),
          if (prioritizeTime) ...<Widget>[
            Text(timer.label, style: context.text.ingredient),
            const SizedBox(height: HearthSpacing.xs),
          ],
          Wrap(
            spacing: HearthSpacing.xs,
            runSpacing: HearthSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              IconButton(
                key: ValueKey<String>('timer-pause-${timer.id}'),
                tooltip: timer.isPaused ? 'Resume timer' : 'Pause timer',
                constraints: const BoxConstraints(
                  minWidth: HearthTouch.androidTarget,
                  minHeight: HearthTouch.androidTarget,
                ),
                icon: Icon(timer.isPaused ? Icons.play_arrow : Icons.pause),
                onPressed: done
                    ? null
                    : () => _applyTimerAction(messenger, control, () async {
                        await control.togglePause(timer);
                        return true;
                      }),
              ),
              IconButton(
                key: ValueKey<String>('timer-stop-${timer.id}'),
                tooltip: 'Stop timer',
                constraints: const BoxConstraints(
                  minWidth: HearthTouch.androidTarget,
                  minHeight: HearthTouch.androidTarget,
                ),
                icon: const Icon(Icons.close),
                onPressed: () => _applyTimerAction(
                  messenger,
                  control,
                  () async {
                    await control.dismiss(timer.id);
                    return true;
                  },
                  alertMessage: 'Timer stopped. Alert cancellation failed.',
                ),
              ),
              for (final int minutes in <int>[1, 5])
                TextButton(
                  key: ValueKey<String>('timer-add-$minutes-${timer.id}'),
                  style: actionStyle,
                  onPressed: () => _applyTimerAction(
                    messenger,
                    control,
                    () => control.addTime(timer.id, Duration(minutes: minutes)),
                  ),
                  child: Text(
                    '+$minutes min',
                    semanticsLabel:
                        'Add $minutes ${minutes == 1 ? 'minute' : 'minutes'} to ${timer.label}',
                  ),
                ),
              TextButton(
                key: ValueKey<String>('timer-set-${timer.id}'),
                style: actionStyle,
                onPressed: () async {
                  final Duration? remaining = await showSetTimerTimeSheet(
                    context,
                    timer: timer,
                  );
                  if (remaining == null || !messenger.mounted) return;
                  await _applyTimerAction(
                    messenger,
                    control,
                    () => control.setTimeLeft(timer.id, remaining),
                  );
                },
                child: Text(
                  'Set time left',
                  semanticsLabel: 'Set time left for ${timer.label}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _applyTimerAction(
  ScaffoldMessengerState messenger,
  CookTimersNotifier control,
  Future<bool> Function() action, {
  String alertMessage = 'Timer saved. Alert update failed.',
}) async {
  try {
    final bool exists = await action();
    if (!exists && messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This timer has already been stopped.')),
      );
    }
  } on CookTimerAlertFailure catch (error) {
    _offerAlertRetry(messenger, control, error.timerId, alertMessage);
  } catch (_) {
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('The timer could not be saved. Please try again.'),
      ),
    );
  }
}

void _offerAlertRetry(
  ScaffoldMessengerState messenger,
  CookTimersNotifier control,
  String id,
  String message,
) {
  if (!messenger.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Retry alert',
        onPressed: () async {
          try {
            await control.retryAlert(id);
          } catch (_) {
            _offerAlertRetry(messenger, control, id, message);
          }
        },
      ),
    ),
  );
}

/// Reviews minutes and seconds without changing anything until saved.
Future<Duration?> showSetTimerTimeSheet(
  BuildContext context, {
  required CookTimer timer,
}) => showModalBottomSheet<Duration>(
  context: context,
  backgroundColor: context.colors.surface,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => _SetTimerTimeSheet(timer: timer),
);

class _SetTimerTimeSheet extends StatefulWidget {
  const _SetTimerTimeSheet({required this.timer});

  final CookTimer timer;

  @override
  State<_SetTimerTimeSheet> createState() => _SetTimerTimeSheetState();
}

class _SetTimerTimeSheetState extends State<_SetTimerTimeSheet> {
  late final int _initialSeconds =
      (widget.timer.remainingAt(DateTime.now()).inMilliseconds / 1000).ceil();
  late final TextEditingController _minutes = TextEditingController(
    text: (_initialSeconds ~/ 60).toString(),
  );
  late final TextEditingController _seconds = TextEditingController(
    text: (_initialSeconds % 60).toString(),
  );
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _save() {
    final String minuteText = _minutes.text.trim();
    final String secondText = _seconds.text.trim();
    final int? minutes = int.tryParse(minuteText.isEmpty ? '0' : minuteText);
    final int? seconds = int.tryParse(secondText.isEmpty ? '0' : secondText);
    String? error;
    if (minutes == null || seconds == null || minutes < 0 || seconds < 0) {
      error = 'Enter whole minutes and seconds, without a minus sign.';
    } else if (seconds > 59) {
      error = 'Seconds must be between 0 and 59.';
    } else if (minutes == 0 && seconds == 0) {
      error = 'Enter a time greater than zero.';
    } else if (minutes > 8640000000000 ~/ 60) {
      error = 'That time is too large. Choose a shorter time.';
    }
    if (error == null) {
      final Duration remaining = Duration(minutes: minutes!, seconds: seconds!);
      try {
        DateTime.now().add(remaining);
      } on ArgumentError {
        error = 'That time is too large. Choose a shorter time.';
      }
      if (error == null) {
        Navigator.of(context).pop(remaining);
        return;
      }
    }
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Set time left', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            Text(widget.timer.label, style: context.text.body),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'Running timers keep running. Paused timers stay paused. '
              'A finished timer starts again.',
              style: context.text.metadata.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: HearthSpacing.lg),
            TextField(
              controller: _minutes,
              decoration: const InputDecoration(labelText: 'Minutes'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: HearthSpacing.md),
            TextField(
              controller: _seconds,
              decoration: const InputDecoration(labelText: 'Seconds'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            if (_error case final String error) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: context.text.body.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: HearthSpacing.lg),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _save,
              child: const Text('Save time'),
            ),
            const SizedBox(height: HearthSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Hours are broken out once there are any; 179:57 is hard to read at a stove.
String countdown(Duration d) {
  final int hours = d.inHours;
  final String minutes = d.inMinutes.remainder(60).toString();
  final String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$seconds';
  return '$hours:${minutes.padLeft(2, '0')}:$seconds';
}

/// Spoken without a row of colons.
String spokenDuration(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '$hours hours' : '$hours hours $minutes minutes';
  }
  if (minutes > 0) return '$minutes minutes';
  return '${d.inSeconds} seconds';
}
