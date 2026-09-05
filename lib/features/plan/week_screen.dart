import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/macro_rings.dart';
import '../../app/widgets/minor_nutrient_bars.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import '../../domain/planning/week_template.dart';
import 'entry_resolver.dart';
import 'week_strip.dart';
import 'week_template_sheet.dart';

/// The weekly summary: per-day totals for the four tracked macros (spec §5.6).
///
/// This is the step-back view. Tapping a day drops into its detail, which is
/// where anything actually gets logged.
class WeekScreen extends ConsumerWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

        final Map<DateTime, int> counts = <DateTime, int>{
          for (final DateTime day in days)
            day: (byDay[day] ?? const <MealPlanEntry>[]).length,
        };
        final Macros selectedEaten = eaten[selected] ?? Macros.zero;

        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 3),
          children: <Widget>[
            _WeekHeader(days: days),
            const SizedBox(height: HearthSpacing.lg),
            // The week in one row. Selecting stays here rather than dropping
            // into the day: the point of a strip is to be able to look across
            // the week without leaving it.
            WeekStrip(
              days: days,
              selected: selected,
              eaten: eaten,
              entryCounts: counts,
              targets: targets,
              onSelect: (DateTime day) =>
                  ref.read(selectedDateProvider.notifier).select(day),
            ),
            const SizedBox(height: HearthSpacing.lg),
            _SelectedDay(
              day: selected,
              eaten: selectedEaten,
              targets: targets,
              entryCount: counts[selected] ?? 0,
              onOpen: () =>
                  ref.read(planViewProvider.notifier).show(PlanView.day),
            ),
            const SizedBox(height: HearthSpacing.lg),
            _WeekTotals(eaten: eaten.values, targets: targets),
          ],
        );
      },
    );
  }
}

/// The day the strip is pointing at, and the way into logging it.
///
/// The rings are the same widget the day view uses, so the same four numbers
/// cannot come to read two different ways on two screens.
class _SelectedDay extends StatelessWidget {
  const _SelectedDay({
    required this.day,
    required this.eaten,
    required this.targets,
    required this.entryCount,
    required this.onOpen,
  });

  final DateTime day;
  final Macros eaten;
  final MacroTargets? targets;
  final int entryCount;
  final VoidCallback onOpen;

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String get _title => isSameDay(day, DateTime.now())
      ? 'Today'
      : '${_weekdays[day.weekday - 1]} ${shortDate(day)}';

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(_title, style: context.text.sectionHeader)),
              Text(
                entryCount == 0
                    ? 'nothing logged'
                    : '$entryCount ${entryCount == 1 ? 'item' : 'items'}',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.md),
          if (targets == null)
            Text(
              'No targets set for this week.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            )
          else ...<Widget>[
            // Computed once for both, rather than once each: two calls with
            // the same inputs can drift the moment either gains an argument,
            // and rings and bars disagreeing about one day would be a bug
            // nobody could see.
            if (DayProgress.from(consumed: eaten, targets: targets!)
                case final DayProgress day) ...<Widget>[
              MacroRings(progress: day),
              // The same three, on the day the week has selected. A trend is
              // where these actually mean something, and the week is the only
              // screen that shows one (spec §5.6).
              //
              // Shown whether or not anything has stated a value. The bars say
              // so themselves — hiding them here made the feature invisible on
              // exactly the days it most needed explaining.
              const SizedBox(height: HearthSpacing.lg),
              MinorNutrientBars(progress: day),
            ],
          ],
          const SizedBox(height: HearthSpacing.lg),
          SizedBox(
            width: double.infinity,
            // Height left to Material, which pads its own tap target to 48.
            // HearthTouch.minTarget is 44 — the iOS figure, and the one this
            // app is written to — but Android's guideline asks for 48 and the
            // §6.3 sweep checks both.
            child: FilledButton(
              onPressed: onOpen,
              // The strip no longer navigates, so the way in has to be said
              // out loud rather than left as a thing you discover.
              child: const Text('Open this day'),
            ),
          ),
        ],
      ),
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
      // The structural twin of the copy-day button in the day header: the
      // same question — "put these meals on those days" — one level up.
      IconButton(
        onPressed: () => _save(context, ref),
        tooltip: 'Save this week to use again',
        icon: const Icon(Icons.bookmark_add_outlined),
      ),
      IconButton(
        onPressed: () => _apply(context, ref),
        tooltip: 'Use a saved week',
        icon: const Icon(Icons.bookmarks_outlined),
      ),
    ],
  );

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final String? name = await showSaveTemplateSheet(context);
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final WeekTemplate? saved = await ref
        .read(planRepositoryProvider)
        .saveWeekAsTemplate(anchor: ref.read(selectedDateProvider), name: name);
    ref.invalidate(weekTemplatesProvider);
    if (!context.mounted) return;

    // Cleared first: these two actions sit next to each other, and a stale
    // "Saved" message queued in front of a fresh "Added" one means waiting
    // four seconds to find out what just happened.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                // Saving an empty week is something you would only do by
                // accident, so it says so rather than making a template of
                // nothing.
                ? 'Nothing is planned this week yet.'
                : 'Saved "${saved.name}" — ${saved.entries.length} '
                      '${saved.entries.length == 1 ? 'meal' : 'meals'}.',
          ),
        ),
      );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final WeekTemplate? template = await showApplyTemplateSheet(context);
    if (template == null || !context.mounted) return;

    final int added = await ref
        .read(planRepositoryProvider)
        .applyTemplate(
          template: template,
          anchor: ref.read(selectedDateProvider),
        );
    if (!context.mounted) return;

    ref.invalidate(dayEntriesProvider);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // Says how many it added rather than "done": applying is additive, so
          // the count is how you tell it landed on a week that already had
          // things on it.
          content: Text(
            'Added $added ${added == 1 ? 'meal' : 'meals'} '
            'from "${template.name}".',
          ),
        ),
      );
  }
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
