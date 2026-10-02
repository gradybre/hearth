import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import 'log_sheet.dart';
import 'meal_source_actions.dart';

/// A person's week of meals. Dinner leads; the other slots open in place.
/// These cards never change a meal's logged state or its saved portion.
class WeekMealsView extends StatelessWidget {
  const WeekMealsView({
    required this.days,
    required this.entries,
    required this.recipes,
    required this.foods,
    super.key,
  });

  final List<DateTime> days;
  final Map<DateTime, List<MealPlanEntry>> entries;
  final Map<String, Recipe> recipes;
  final Map<String, Food> foods;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final DateTime date in days)
        _MealDay(
          key: ValueKey<String>('week-meals-day-${_dateKey(date)}'),
          date: date,
          entries: entries[date] ?? const <MealPlanEntry>[],
          recipes: recipes,
          foods: foods,
        ),
    ],
  );
}

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _fullDate(DateTime date) =>
    '${weekdayName(date)}, ${monthName(date)} ${date.day}, ${date.year}';

class _MealDay extends ConsumerStatefulWidget {
  const _MealDay({
    required this.date,
    required this.entries,
    required this.recipes,
    required this.foods,
    super.key,
  });

  final DateTime date;
  final List<MealPlanEntry> entries;
  final Map<String, Recipe> recipes;
  final Map<String, Food> foods;

  @override
  ConsumerState<_MealDay> createState() => _MealDayState();
}

class _MealDayState extends ConsumerState<_MealDay> {
  bool _otherMeals = false;

  List<MealPlanEntry> _in(MealSlot slot) => widget.entries
      .where((MealPlanEntry entry) => entry.slot == slot)
      .toList();

  void _openDay() {
    ref.read(selectedDateProvider.notifier).select(widget.date);
    ref.read(planViewProvider.notifier).show(PlanView.day);
  }

  Widget _add(MealSlot slot) => TextButton.icon(
    key: ValueKey<String>('week-add-${_dateKey(widget.date)}-${slot.name}'),
    style: TextButton.styleFrom(
      minimumSize: const Size(
        HearthTouch.androidTarget,
        HearthTouch.androidTarget,
      ),
      alignment: Alignment.centerLeft,
    ),
    onPressed: () => showLogSheet(context, date: widget.date, slot: slot),
    icon: const Icon(Icons.add, size: 20),
    label: Text(
      'Add ${slot.label.toLowerCase()}',
      semanticsLabel:
          'Add ${slot.label.toLowerCase()} on ${_fullDate(widget.date)}',
    ),
  );

  Widget _meals(MealSlot slot) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (_in(slot).isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: HearthSpacing.sm),
          child: Text(
            slot == MealSlot.dinner ? 'No dinner yet' : 'Nothing added',
            style: context.text.metadata.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ),
      for (final MealPlanEntry entry in _in(slot))
        _Meal(
          entry: entry,
          recipe: widget.recipes[entry.refId],
          food: widget.foods[entry.refId],
        ),
      _add(slot),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final DateTime today = dayKey(DateTime.now());
    final String date =
        '${shortWeekdayName(widget.date)} · '
        '${monthName(widget.date).substring(0, 3)} ${widget.date.day}'
        '${widget.date.year == today.year ? '' : ', ${widget.date.year}'}'
        '${isSameDay(widget.date, today) ? ' · Today' : ''}';
    final int count = widget.entries
        .where((MealPlanEntry e) => e.slot != MealSlot.dinner)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.colors.outline),
          borderRadius: BorderRadius.circular(HearthRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextButton(
                key: ValueKey<String>('week-open-day-${_dateKey(widget.date)}'),
                onPressed: _openDay,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(
                    HearthTouch.androidTarget,
                    HearthTouch.androidTarget,
                  ),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  date,
                  style: context.text.label,
                  semanticsLabel:
                      'Open ${_fullDate(widget.date)}${isSameDay(widget.date, today) ? ', today' : ''}',
                ),
              ),
              _meals(MealSlot.dinner),
              const Divider(),
              TextButton(
                key: ValueKey<String>(
                  'week-other-meals-${_dateKey(widget.date)}',
                ),
                onPressed: () => setState(() => _otherMeals = !_otherMeals),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(
                    HearthTouch.androidTarget,
                    HearthTouch.androidTarget,
                  ),
                ),
                child: Semantics(
                  expanded: _otherMeals,
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text('Other meals ($count)')),
                      const SizedBox(width: HearthSpacing.sm),
                      Icon(_otherMeals ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
              ),
              if (!_otherMeals)
                Wrap(
                  spacing: HearthSpacing.md,
                  runSpacing: HearthSpacing.xs,
                  children: <Widget>[
                    for (final MealSlot slot in const <MealSlot>[
                      MealSlot.breakfast,
                      MealSlot.lunch,
                      MealSlot.snack,
                    ])
                      Text(
                        '${slot.label} ${_in(slot).length}',
                        style: context.text.metadata.copyWith(
                          color: context.colors.textMuted,
                        ),
                      ),
                  ],
                ),
              if (_otherMeals)
                for (final MealSlot slot in const <MealSlot>[
                  MealSlot.breakfast,
                  MealSlot.lunch,
                  MealSlot.snack,
                ]) ...<Widget>[
                  const SizedBox(height: HearthSpacing.sm),
                  Text(slot.label, style: context.text.label),
                  _meals(slot),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meal extends ConsumerWidget {
  const _Meal({required this.entry, this.recipe, this.food});

  final MealPlanEntry entry;
  final Recipe? recipe;
  final Food? food;

  bool get _available => entry.refType == PlanRefType.recipe
      ? recipe != null && !recipe!.isDeleted
      : food != null && !food!.isDeleted;

  String get _label {
    final String? saved = entry.macroSnapshot?.label;
    if (entry.isLogged && saved != null && saved.isNotEmpty) return saved;
    return entry.refType == PlanRefType.recipe
        ? recipe?.title ?? 'Unavailable recipe'
        : food?.name ?? 'Unavailable food';
  }

  String get _kind => entry.refType == PlanRefType.food
      ? 'Food'
      : recipe?.isEatenOut == true
      ? 'Restaurant meal'
      : 'Recipe';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool cook =
        !entry.isLogged &&
        entry.refType == PlanRefType.recipe &&
        _available &&
        !recipe!.isEatenOut &&
        recipe!.allSteps.isNotEmpty;
    final bool missingServing =
        entry.refType == PlanRefType.food &&
        _available &&
        entry.servingOptionId != null &&
        !food!.servingOptions.any(
          (ServingOption serving) => serving.id == entry.servingOptionId,
        );
    final bool missingSnapshot = entry.isLogged && entry.macroSnapshot == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: _available,
            label:
                '${_available ? 'Open ${_kind.toLowerCase()} ' : ''}$_label. ${entry.slot.label}. ${entry.isLogged ? 'Logged' : 'Planned'}.'
                '${missingSnapshot ? ' Saved nutrition unavailable.' : ''}',
            hint: _available ? 'Shows current library details' : null,
            onTap: _available ? () => openMealSource(context, entry) : null,
            child: ExcludeSemantics(
              child: InkWell(
                key: ValueKey<String>('week-meal-open-${entry.id}'),
                onTap: _available ? () => openMealSource(context, entry) : null,
                borderRadius: BorderRadius.circular(HearthRadius.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: HearthTouch.androidTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: HearthSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(_label, style: context.text.ingredient),
                        const SizedBox(height: HearthSpacing.xs),
                        Text(
                          '${entry.slot == MealSlot.dinner ? 'Dinner · ' : ''}'
                          '${entry.isLogged ? 'Logged' : 'Planned'} · $_kind',
                          style: context.text.metadata.copyWith(
                            color: context.colors.textMuted,
                          ),
                        ),
                        if (missingSnapshot)
                          Text(
                            'Saved nutrition unavailable',
                            style: context.text.metadata.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_available)
            Text(
              '${entry.refType == PlanRefType.recipe ? 'Recipe' : 'Food'} no longer available in the library.',
              style: context.text.metadata.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          if (missingServing)
            Text(
              'The selected serving is no longer available. Open for current food details.',
              style: context.text.metadata.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          if (cook)
            Wrap(
              spacing: HearthSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                TextButton.icon(
                  key: ValueKey<String>('week-meal-cook-${entry.id}'),
                  onPressed: () => cookMealSource(context, ref, entry),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      HearthTouch.androidTarget,
                      HearthTouch.androidTarget,
                    ),
                  ),
                  icon: const Icon(Icons.soup_kitchen_outlined, size: 20),
                  label: Text(
                    'Cook',
                    semanticsLabel: 'Cook $_label, full recipe',
                  ),
                ),
                Text(
                  'Full recipe · ${writeAmount(recipe!.servings)} '
                  '${recipe!.servings == 1 ? 'serving' : 'servings'}',
                  style: context.text.metadata.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
