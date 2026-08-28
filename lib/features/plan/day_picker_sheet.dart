import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/week.dart';

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
}) => showModalBottomSheet<List<DateTime>>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => _DayPickerSheet(
    title: title,
    actionLabel: actionLabel,
    excluding: excluding,
  ),
);

class _DayPickerSheet extends ConsumerStatefulWidget {
  const _DayPickerSheet({
    required this.title,
    required this.actionLabel,
    this.excluding,
  });

  final String title;
  final String actionLabel;

  /// A day that cannot be chosen — the source day, when copying.
  final DateTime? excluding;

  @override
  ConsumerState<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends ConsumerState<_DayPickerSheet> {
  final Set<DateTime> _selected = <DateTime>{};

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
      ...weekOf(anchor.add(const Duration(days: 7))),
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
                          onChanged: (bool value) => setState(() {
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
                              _selected.toList()..sort(
                                (DateTime a, DateTime b) => a.compareTo(b),
                              ),
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
    final int delta = day.difference(today).inDays;
    final String weekday = _weekdays[day.weekday - 1];
    if (delta == 0) return '$weekday ${day.day} · today';
    if (delta == 1) return '$weekday ${day.day} · tomorrow';
    return '$weekday ${day.day}';
  }
}

class _DayCheck extends StatelessWidget {
  const _DayCheck({
    required this.day,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        checked: selected,
        label: label,
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
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
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
