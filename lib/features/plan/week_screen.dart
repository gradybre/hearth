import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import 'entry_resolver.dart';

/// The weekly summary: per-day totals for the four tracked macros (spec §5.6).
///
/// This is the step-back view. Tapping a day drops into its detail, which is
/// where anything actually gets logged.
class WeekScreen extends ConsumerWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final DateTime selected = ref.watch(selectedDateProvider);
    final List<DateTime> days = weekOf(selected);
    final MacroTargets? targets = ref.watch(dayTargetsProvider).value;

    final Map<String, Recipe> recipes = <String, Recipe>{
      for (final Recipe r
          in ref.watch(recipeLibraryProvider).value ?? const <Recipe>[])
        r.id: r,
    };
    final Map<String, Food> foods = <String, Food>{
      for (final Food f
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        f.id: f,
    };

    final AsyncValue<Map<DateTime, List<MealPlanEntry>>> week = ref.watch(
      weekEntriesProvider,
    );
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return week.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace s) =>
          Center(child: Text('The week could not be read.\n$e')),
      data: (Map<DateTime, List<MealPlanEntry>> byDay) {
        final Map<DateTime, Macros> eaten = <DateTime, Macros>{
          for (final DateTime day in days)
            day: EntryResolver.eaten(
              EntryResolver.resolveAll(
                byDay[day] ?? const <MealPlanEntry>[],
                recipes: recipes,
                foods: foods,
              ),
            ),
        };

        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 3),
          children: <Widget>[
            _WeekHeader(days: days),
            const SizedBox(height: HearthSpacing.lg),
            _WeekTotals(eaten: eaten.values, targets: targets),
            const SizedBox(height: HearthSpacing.xl),
            for (final DateTime day in days)
              _DayRow(
                day: day,
                eaten: eaten[day] ?? Macros.zero,
                targets: targets,
                isSelected: day == selected,
                entryCount: (byDay[day] ?? const <MealPlanEntry>[]).length,
                onTap: () {
                  ref.read(selectedDateProvider.notifier).select(day);
                  ref.read(planViewProvider.notifier).show(PlanView.day);
                },
              ),
            const SizedBox(height: HearthSpacing.lg),
            Center(
              child: Text(
                'Tap a day to log into it.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeekHeader extends ConsumerWidget {
  const _WeekHeader({required this.days});

  final List<DateTime> days;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get _range {
    final DateTime from = days.first;
    final DateTime to = days.last;
    if (from.month == to.month) {
      return '${from.day}–${to.day} ${_months[from.month - 1]}';
    }
    return '${from.day} ${_months[from.month - 1]} – '
        '${to.day} ${_months[to.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('This week', style: context.text.recipeTitle),
            Text(
              _range,
              style: context.text.metadata.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(-7),
        tooltip: 'Previous week',
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).today(),
        tooltip: 'Go to this week',
        icon: const Icon(Icons.today_outlined),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(7),
        tooltip: 'Next week',
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

/// The week's average against target.
///
/// An average rather than a sum: targets are daily, so a total of seven days
/// against one day's target would be meaningless, and "you ate 15,000
/// calories" tells you nothing without dividing it back down yourself.
class _WeekTotals extends StatelessWidget {
  const _WeekTotals({required this.eaten, required this.targets});

  final Iterable<Macros> eaten;
  final MacroTargets? targets;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final List<Macros> loggedDays = eaten
        .where((Macros m) => !m.isZero)
        .toList(growable: false);

    if (loggedDays.isEmpty) {
      return _Card(
        child: Text(
          'Nothing logged this week yet.',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
      );
    }

    final Macros total = Macros.sum(loggedDays);
    final Macros average = total.scaledBy(1 / loggedDays.length);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Daily average', style: context.text.sectionHeader),
              ),
              Text(
                loggedDays.length == 1
                    ? 'over 1 logged day'
                    : 'over ${loggedDays.length} logged days',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.md),
          _MacroRow(macros: average, targets: targets),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.macros, this.targets});

  final Macros macros;
  final MacroTargets? targets;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final int columns = A11y.macroColumns(context);

    final List<(String, double, double?)> values = <(String, double, double?)>[
      ('kcal', macros.kcal, targets?.kcal),
      ('protein', macros.proteinG, targets?.proteinG),
      ('carbs', macros.carbG, targets?.carbG),
      ('fat', macros.fatG, targets?.fatG),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = HearthSpacing.md;
        final double itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final (String label, double value, double? target) in values)
              SizedBox(
                width: itemWidth,
                child: Semantics(
                  label: target == null
                      ? '$label ${value.round()}'
                      : '$label ${value.round()} of ${target.round()}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        value.round().toString(),
                        style: context.text.ingredient.copyWith(fontSize: 22),
                      ),
                      Text(
                        target == null ? label : '$label of ${target.round()}',
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.eaten,
    required this.targets,
    required this.isSelected,
    required this.entryCount,
    required this.onTap,
  });

  final DateTime day;
  final Macros eaten;
  final MacroTargets? targets;
  final bool isSelected;
  final int entryCount;
  final VoidCallback onTap;

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool isToday = isSameDay(day, DateTime.now());
    final bool logged = !eaten.isZero;

    final MacroProgress? calories = targets == null
        ? null
        : DayProgress.from(consumed: eaten, targets: targets!).calories;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        button: true,
        selected: isSelected,
        label:
            '${_weekdays[day.weekday - 1]} ${day.day}. '
            '${logged ? '${eaten.kcal.round()} calories logged' : 'nothing logged'}'
            '${isToday ? '. Today.' : ''}',
        excludeSemantics: true,
        child: Material(
          color: isSelected ? colors.surfaceSunken : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: isSelected ? colors.outlineStrong : colors.outline,
                ),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _weekdays[day.weekday - 1],
                          style: text.ingredient.copyWith(
                            // Today is marked by weight and a label, not by
                            // colour alone (spec §6.3).
                            fontWeight: isToday
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          isToday ? 'today' : '${day.day}',
                          style: text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          logged
                              ? '${eaten.kcal.round()} kcal'
                              : 'nothing logged',
                          style: text.ingredient.copyWith(
                            color: logged
                                ? colors.textPrimary
                                : colors.textMuted,
                          ),
                        ),
                        if (logged) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            'P ${eaten.proteinG.round()}  '
                            'C ${eaten.carbG.round()}  '
                            'F ${eaten.fatG.round()}',
                            style: text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                        if (calories != null) ...<Widget>[
                          const SizedBox(height: HearthSpacing.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              HearthRadius.sm,
                            ),
                            child: LinearProgressIndicator(
                              value: calories.barFill,
                              minHeight: 5,
                              backgroundColor: colors.progressTrack,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                calories.isOver
                                    ? colors.overAccent
                                    : colors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (entryCount > 0) ...<Widget>[
                    const SizedBox(width: HearthSpacing.sm),
                    Text(
                      '$entryCount',
                      style: text.metadata.copyWith(color: colors.textMuted),
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
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: child,
      ),
    );
  }
}
