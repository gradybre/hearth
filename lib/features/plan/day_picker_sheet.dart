import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';

/// Where one meal is going: a day and a meal slot (review N02).
@immutable
class MealDestination {
  const MealDestination({required this.date, required this.slot});

  final DateTime date;
  final MealSlot slot;
}

/// Picks several days at once.
///
/// Shared by copy-day and meal-prep assignment because they ask the same
/// question — "which days?" — and answering it twice in two different shapes
/// would be the app's problem leaking into the user's.
Future<List<DateTime>?> showDayPicker(
  BuildContext context, {
  required String title,
  required String actionLabel,
  DateTime? excluding,
}) async => await _show(
  context,
  title: title,
  actionLabel: actionLabel,
  excluding: excluding,
) as List<DateTime>?;

/// Asks for a single day *and* a slot, for moving or repeating one meal.
///
/// The same sheet as [showDayPicker] rather than one beside it: the list of
/// days, the height cap and the footer are the same problem solved once, and
/// two copies of a day list would drift the moment either grew a month view.
/// What changes is that one day is chosen instead of several, and that the
/// slot is part of the answer — "the wrong day" and "the wrong meal" are the
/// same correction, and asking for them on two screens would be two.
Future<MealDestination?> showMealDestination(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required MealSlot slot,
}) async =>
    await _show(context, title: title, actionLabel: actionLabel, slot: slot)
        as MealDestination?;

Future<Object?> _show(
  BuildContext context, {
  required String title,
  required String actionLabel,
  DateTime? excluding,
  MealSlot? slot,
}) => showModalBottomSheet<Object>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => _DayPickerSheet(
    title: title,
    actionLabel: actionLabel,
    excluding: excluding,
    slot: slot,
  ),
);

class _DayPickerSheet extends ConsumerStatefulWidget {
  const _DayPickerSheet({
    required this.title,
    required this.actionLabel,
    this.excluding,
    this.slot,
  });

  final String title;
  final String actionLabel;

  /// A day that cannot be chosen — the source day, when copying.
  final DateTime? excluding;

  /// The slot to open on, when one meal is being moved or repeated. Null for
  /// the several-days assignment, which has no slot of its own to change.
  final MealSlot? slot;

  /// One day, or several. Set by asking for a slot: a meal is in one place.
  bool get single => slot != null;

  @override
  ConsumerState<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends ConsumerState<_DayPickerSheet> {
  final Set<DateTime> _selected = <DateTime>{};
  late MealSlot _slot = widget.slot ?? MealSlot.breakfast;

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final DateTime anchor = ref.watch(selectedDateProvider);
    // Offers this week and the next: meal prep and copy-day are both about
    // the near future, and a full calendar would be a heavier control than
    // the job needs.
    final List<DateTime> days = <DateTime>[
      ...weekOf(anchor),
      ...weekOf(addDays(anchor, 7)),
    ];

    return ConstrainedBox(
      // Without a cap the sheet grows past the top of the screen and its
      // header ends up behind the status bar — two weeks of days is more than
      // fits. Leaving a margin also keeps the dismiss-by-tapping-above
      // gesture available.
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
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: context.text.sectionHeader,
                      ),
                    ),
                    if (!widget.single)
                      Text(
                        _selected.isEmpty
                            ? 'none chosen'
                            : '${_selected.length} chosen',
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.lg,
                  ),
                  children: <Widget>[
                    for (final DateTime day in days)
                      if (widget.excluding == null ||
                          !isSameDay(day, widget.excluding!))
                        _DayCheck(
                          day: day,
                          label: _label(day),
                          selected: _selected.contains(day),
                          single: widget.single,
                          onChanged: (bool value) => setState(() {
                            // One meal is in one place, so choosing a day
                            // here replaces the choice rather than adding to
                            // it — and a chosen day cannot be un-chosen into
                            // no answer at all.
                            if (widget.single) {
                              if (value) {
                                _selected
                                  ..clear()
                                  ..add(day);
                              }
                              return;
                            }
                            if (value) {
                              _selected.add(day);
                            } else {
                              _selected.remove(day);
                            }
                          }),
                        ),
                  ],
                ),
              ),
              if (widget.single)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.lg,
                    vertical: HearthSpacing.sm,
                  ),
                  child: Wrap(
                    spacing: HearthSpacing.sm,
                    runSpacing: HearthSpacing.sm,
                    children: <Widget>[
                      for (final MealSlot slot in MealSlot.values)
                        ChoiceChip(
                          label: Text(slot.label),
                          selected: slot == _slot,
                          onSelected: (bool picked) {
                            if (picked) setState(() => _slot = slot);
                          },
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: HearthSpacing.sm),
                    FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                              widget.single
                                  ? MealDestination(
                                      date: _selected.single,
                                      slot: _slot,
                                    )
                                  : (_selected.toList()..sort(
                                      (DateTime a, DateTime b) =>
                                          a.compareTo(b),
                                    )),
                            ),
                      child: Text(widget.actionLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(DateTime day) {
    final DateTime today = dayKey(DateTime.now());
    // Calendar days, not elapsed hours — see `calendarDaysBetween`. This
    // sheet picks the days a meal is copied onto, so "today" naming the
    // wrong one is the same defect as F05 with more consequences.
    final int delta = calendarDaysBetween(today, day);
    final String weekday = _weekdays[day.weekday - 1];
    if (delta == 0) return '$weekday ${shortDate(day)} · today';
    if (delta == 1) return '$weekday ${shortDate(day)} · tomorrow';
    return '$weekday ${shortDate(day)}';
  }
}

class _DayCheck extends StatelessWidget {
  const _DayCheck({
    required this.day,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.single = false,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  /// One of these, or any number. It changes the icon, because a checkbox
  /// promises you can tick a second one.
  final bool single;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        checked: selected,
        label: label,
        onTap: () => onChanged(!selected),
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.surfaceSunken : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: () => onChanged(!selected),
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: selected ? colors.outlineStrong : colors.outline,
                ),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                children: <Widget>[
                  // Selection is carried by an icon as well as the fill, so it
                  // does not rest on colour alone (spec §6.3).
                  Icon(
                    single
                        ? (selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked)
                        : (selected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank),
                    size: 20,
                    color: selected ? colors.accent : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(child: Text(label, style: context.text.ingredient)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
