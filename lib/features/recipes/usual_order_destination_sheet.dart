import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import '../plan/logging_intent.dart';

/// A library order has no diary destination. Ask visibly, starting on the
/// local opening day, rather than inheriting a diary date from another visit.
Future<LoggingIntent?> showUsualOrderDestination(BuildContext context) {
  final DateTime opened = dayKey(DateTime.now());
  DateTime selected = opened;
  MealSlot slot = MealSlot.dinner;
  return showModalBottomSheet<LoggingIntent>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter refresh) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(HearthSpacing.lg),
          children: <Widget>[
            Text('Which day and meal?', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.md),
            Text(
              '${weekdayName(selected)} ${monthName(selected)} '
              '${selected.day}, ${selected.year}',
              key: const Key('usual-destination-date'),
              style: context.text.ingredient,
            ),
            Wrap(
              spacing: HearthSpacing.sm,
              children: <Widget>[
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () =>
                      refresh(() => selected = addDays(selected, -1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () => refresh(() => selected = opened),
                  child: const Text('Today'),
                ),
                IconButton(
                  tooltip: 'Next day',
                  onPressed: () =>
                      refresh(() => selected = addDays(selected, 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Wrap(
              spacing: HearthSpacing.sm,
              runSpacing: HearthSpacing.sm,
              children: <Widget>[
                for (final MealSlot option in MealSlot.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: slot == option,
                    onSelected: (bool selected) {
                      if (selected) refresh(() => slot = option);
                    },
                  ),
              ],
            ),
            const SizedBox(height: HearthSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                LoggingIntent.forMeal(
                  date: selected,
                  slot: slot,
                  today: opened,
                ),
              ),
              child: const Text('Review portion', textAlign: TextAlign.center),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
