import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/macro_rings.dart';
import '../../app/widgets/minor_nutrient_bars.dart';
import '../../app/widgets/reading_column.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/log_state_change.dart';
import '../../domain/planning/logged_portion.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/portion_unit.dart';
import '../../domain/planning/target_schedule.dart';
import '../../domain/planning/week.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../foods/food_detail_screen.dart';
import '../recipes/cook_along_screen.dart';
import 'day_picker_sheet.dart';
import 'entry_resolver.dart';
import 'log_sheet.dart';
import 'log_state_feedback.dart';
import 'logged_details_sheet.dart';
import 'macro_targets_sheet.dart';
import 'plan_date_header.dart';

/// The day view: plan and track in one place (spec §5.6).
///
/// This is the screen the success bar is judged on, so the shape follows the
/// daily loop rather than the data model: what's left today at the top, then
/// the four slots, then one tap to confirm anything already planned.
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime date = ref.watch(selectedDateProvider);
    final AsyncValue<List<MealPlanEntry>> entries = ref.watch(
      dayEntriesProvider,
    );
    final ResolvedTargets? loadedTargets = ref
        .watch(dayTargetResolutionProvider)
        .value;
    final ResolvedTargets? targetResolution =
        loadedTargets?.userId == ref.watch(currentUserIdProvider) &&
            loadedTargets?.weekStart == startOfWeek(date)
        ? loadedTargets
        : null;
    final MacroTargets? targets = targetResolution?.targets;
    final Map<String, Recipe> recipes = <String, Recipe>{
      for (final Recipe r
          in ref.watch(recipeLibraryProvider).value ?? const <Recipe>[])
        if (!r.isDeleted) r.id: r,
    };
    final Map<String, Food> foods = <String, Food>{
      for (final Food f
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        if (!f.isDeleted) f.id: f,
    };

    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;
    final bool compact =
        MediaQuery.sizeOf(context).width < 372 ||
        MediaQuery.textScalerOf(context).scale(16) > 20;

    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace s) =>
          Center(child: Text('The day could not be read.\n$e')),
      data: (List<MealPlanEntry> raw) {
        final List<ResolvedEntry> resolved = EntryResolver.resolveAll(
          raw,
          recipes: recipes,
          foods: foods,
        );

        // Bounded like the other section screens (review §6.2.7). Plan is the
        // one #61 missed, and it shows worst on the week — a row of a day's
        // figures laid across a metre of desk is not a row anybody reads
        // across. Both halves of the Day/Week toggle, so switching does not
        // change the width of the page under it.
        return ReadingColumn(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              compact ? HearthSpacing.sm : HearthSpacing.lg,
              gutter,
              gutter * 3,
            ),
            children: <Widget>[
              _DayHeader(date: date),
              SizedBox(height: compact ? HearthSpacing.sm : HearthSpacing.lg),
              _RemainingCard(
                entries: resolved,
                targets: targets,
                targetResolution: targetResolution,
              ),
              const SizedBox(height: HearthSpacing.xl),
              for (final MealSlot slot in MealSlot.values) ...<Widget>[
                _SlotSection(
                  slot: slot,
                  entries: EntryResolver.inSlot(resolved, slot),
                  date: date,
                  recipes: recipes,
                  foods: foods,
                ),
                const SizedBox(height: HearthSpacing.lg),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DayHeader extends ConsumerWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlanDateHeader.day(
    date: date,
    onPrevious: () => ref.read(selectedDateProvider.notifier).shiftDays(-1),
    onToday: () => ref.read(selectedDateProvider.notifier).today(),
    onNext: () => ref.read(selectedDateProvider.notifier).shiftDays(1),
    onCopy: () => _copyDay(context, ref, date),
  );

  /// Copies this day onto any number of others (spec §5.6).
  ///
  /// Single day, several days, and a repeating pattern are all the same
  /// gesture here: choose the days you mean.
  static Future<void> _copyDay(
    BuildContext context,
    WidgetRef ref,
    DateTime from,
  ) async {
    final List<DateTime>? targets = await showDayPicker(
      context,
      title: 'Copy this day to',
      actionLabel: 'Copy',
      excluding: from,
    );
    if (targets == null || targets.isEmpty) return;

    final int copied = await ref
        .read(planRepositoryProvider)
        .copyDay(from: from, to: targets);
    ref.invalidate(dayEntriesProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied == 0
              ? 'Nothing on this day to copy.'
              : 'Copied $copied ${copied == 1 ? 'item' : 'items'} to '
                    '${targets.length} ${targets.length == 1 ? 'day' : 'days'}.',
        ),
      ),
    );
  }
}

/// Remaining for the day (spec §5.6).
///
/// Calories lead and the three macros follow. Over/under is carried by an icon
/// and a word as well as colour — never colour alone (spec §6.3).
class _RemainingCard extends ConsumerWidget {
  const _RemainingCard({
    required this.entries,
    required this.targets,
    required this.targetResolution,
  });

  final List<ResolvedEntry> entries;
  final MacroTargets? targets;
  final ResolvedTargets? targetResolution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final Macros planned = EntryResolver.stillPlanned(entries);

    final DayProgress progress = DayProgress.fromParts(
      parts: EntryResolver.eatenParts(entries),
      coverage: EntryResolver.eatenCoverage(entries),
      targets: targets,
    );

    final bool expanded = ref.watch(daySummaryExpandedProvider).value ?? false;
    final bool compact =
        MediaQuery.sizeOf(context).width < 372 ||
        MediaQuery.textScalerOf(context).scale(16) > 20;
    final Widget plannedLabel = Text(
      '${planned.kcal.round()} kcal still planned',
      style: context.text.metadata.copyWith(color: colors.textMuted),
    );

    return _Card(
      onTap: targets == null ? null : () => showMacroTargetsSheet(context),
      child: Semantics(
        label: compact ? 'Daily totals' : null,
        container: compact,
        explicitChildNodes: compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!compact) ...<Widget>[
              Wrap(
                spacing: HearthSpacing.md,
                runSpacing: HearthSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text('Daily totals', style: context.text.sectionHeader),
                  if (!planned.isZero) plannedLabel,
                ],
              ),
            ],
            if (progress.countedParts == 0) ...<Widget>[
              const SizedBox(height: HearthSpacing.xs),
              Text(
                'Nothing logged yet',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
            if (!compact || progress.countedParts == 0)
              SizedBox(height: compact ? HearthSpacing.xs : HearthSpacing.md),
            if (expanded) ...<Widget>[
              MacroRings(progress: progress),
              // Below the rings and quieter than them: these have targets now,
              // but calories are still meant to be the loudest thing here and a
              // ring would put the three on a level with the four (spec §5.6).
              //
              // Shown whether or not anything has stated a value; the bars say
              // so themselves. Hiding them was the first design and it made the
              // feature invisible — most foods in an established library
              // predate these columns, so "nothing has said" is the ordinary
              // answer, and an absent row reads as a feature that was never
              // built.
              const SizedBox(height: HearthSpacing.lg),
              MinorNutrientBars(progress: progress),
            ] else
              _CompactSummary(progress: progress, reflowCalories: compact),
            if (compact && !planned.isZero) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              plannedLabel,
            ],
            const SizedBox(height: HearthSpacing.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: HearthSpacing.sm,
              children: <Widget>[
                TargetSourceAction(
                  resolution: targetResolution,
                  hasTargets: targets != null,
                ),
                TextButton(
                  onPressed: () => ref
                      .read(daySummaryExpandedProvider.notifier)
                      .set(expanded: !expanded),
                  child: Text(expanded ? 'Less' : 'Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The day in four lines, for the top of a screen whose subject is the meals
/// below it (spec §5.6).
///
/// Same numbers, same words, same three minor nutrients — including the ones
/// nothing has stated, which read as a dash. What it drops is the drawing:
/// the rings are the better picture of a day and the worse first screen,
/// because at ordinary text they push the first meal below the fold.
class _CompactSummary extends StatelessWidget {
  const _CompactSummary({required this.progress, required this.reflowCalories});

  final DayProgress progress;
  final bool reflowCalories;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final MacroProgress kcal = progress.forKind(MacroKind.calories);
    // The ring's own judgement, not a fresh one. Mapping "met" onto "under"
    // made a day landing exactly on its target read "0 left" with a down
    // arrow here while the ring beside it said "on target" — the same day,
    // contradicted by two views of itself.
    final TargetIndicator? calories = !kcal.hasTarget
        ? null
        : switch (kcal.tone) {
            MacroTone.over => TargetIndicator.forState(
              TargetState.over,
              amount: kcal.remaining.abs().round().toString(),
            ),
            MacroTone.good when kcal.state == MacroProgressState.met =>
              TargetIndicator.forState(TargetState.met),
            // Neutral is the untouched day: still "left", and the honest amount.
            MacroTone.good || MacroTone.neutral => TargetIndicator.forState(
              TargetState.under,
              amount: kcal.remaining.round().toString(),
            ),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Calories loudest, as everywhere else.
        Semantics(
          label: kcal.hasTarget
              ? '${kcal.consumed.round()} of ${kcal.target.round()} calories. ${calories!.semanticLabel}'
              : '${kcal.consumed.round()} calories consumed.',
          excludeSemantics: true,
          child: Wrap(
            spacing: HearthSpacing.md,
            runSpacing: HearthSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              // Keep the consumed amount and its unit together before the
              // target wraps onto another line at enlarged text.
              Text(
                kcal.hasTarget && !reflowCalories
                    ? '${kcal.consumed.round()} of ${kcal.target.round()} kcal'
                    : '${kcal.consumed.round()} kcal',
                style: context.text.body,
              ),
              if (kcal.hasTarget && reflowCalories)
                Text(
                  'of ${kcal.target.round()} kcal',
                  style: context.text.body,
                ),
              if (calories != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      calories.icon,
                      size: 16,
                      color: kcal.isOver ? colors.overAccent : colors.textMuted,
                    ),
                    const SizedBox(width: HearthSpacing.xxs),
                    Text(
                      calories.shortLabel,
                      style: context.text.metadata.copyWith(
                        color: kcal.isOver
                            ? colors.overAccent
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        _CompactRow(
          readouts: <_Readout>[
            for (final MacroKind kind in <MacroKind>[
              MacroKind.protein,
              MacroKind.carbs,
              MacroKind.fat,
            ])
              _macro(progress.forKind(kind)),
          ],
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: HearthSpacing.xxs),
        _CompactRow(
          readouts: <_Readout>[
            for (final MinorNutrient nutrient in MinorNutrient.values)
              _minor(progress.minor(nutrient)),
          ],
          style: context.text.metadata.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  static _Readout _macro(MacroProgress macro) {
    final String label = MacroRings.labelFor(macro.kind);
    final String unit = MacroRings.unitFor(macro.kind);
    return _Readout(
      text: macro.hasTarget
          ? '$label ${macro.consumed.round()}/${macro.target.round()}$unit'
          : '$label ${macro.consumed.round()}$unit',
      // Spoken in words. A slash is punctuation and an unspaced unit is not a
      // word — the rings say "Protein: 20 of 150 g" and this has to say the
      // same thing, or the compact view is a downgrade for anyone listening
      // to it rather than looking at it (spec §6.3).
      spoken: macro.hasTarget
          ? '$label, ${macro.consumed.round()} of ${macro.target.round()} $unit.'
          : '$label, ${macro.consumed.round()} $unit consumed.',
    );
  }

  /// A dash, never a zero, and a floor marked as one (spec §5.6).
  ///
  /// "0" would claim the day had none of it, when the truth is that nothing
  /// eaten was ever asked. And a total that does not account for everything
  /// eaten is a floor rather than a figure — printed bare it reads exactly
  /// like a complete one, which is the whole defect this column exists to
  /// avoid. The compact view marks it and says so out loud.
  static _Readout _minor(MinorProgress nutrient) {
    final MinorNutrient kind = nutrient.nutrient;
    final String target = '${nutrient.target.round()}${kind.unit}';

    if (!nutrient.isKnown) {
      return _Readout(
        text: nutrient.hasTarget
            ? '${kind.label} —/$target'
            : '${kind.label} —',
        // The word, not the dash: most screen readers pass over punctuation
        // at default verbosity, so "Fibre, of 28 g" would be both
        // ungrammatical and silent about the thing that matters.
        spoken:
            '${kind.label}, not stated${nutrient.hasTarget ? ', of ${nutrient.target.round()} ${kind.unit}' : ''}.'
            '${nutrient.countedParts == 0 ? ' Nothing logged yet.' : ''}',
      );
    }

    final String amount = nutrient.consumed!.round().toString();
    final bool floor = nutrient.coverage != MinorCoverage.complete;
    return _Readout(
      // "≥" rather than a bare number: at a glance it is the difference
      // between "you have had 14 g of fibre" and "you have had at least 14 g,
      // and something you ate never said".
      text:
          '${kind.label} ${floor ? '≥' : ''}$amount${nutrient.hasTarget ? '/$target' : kind.unit}',
      spoken:
          '${kind.label}, ${floor ? 'at least ' : ''}$amount${nutrient.hasTarget ? ' of ${nutrient.target.round()}' : ''} ${kind.unit}.'
          '${floor ? ' Not a full count.' : ''}',
    );
  }
}

/// One short readout: what it looks like, and what it says.
class _Readout {
  const _Readout({required this.text, required this.spoken});

  final String text;
  final String spoken;
}

/// Several short readouts on one line, wrapping rather than overflowing.
class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.readouts, required this.style});

  final List<_Readout> readouts;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HearthSpacing.md,
    runSpacing: HearthSpacing.xxs,
    children: <Widget>[
      for (final _Readout readout in readouts)
        Semantics(
          label: readout.spoken,
          excludeSemantics: true,
          child: Text(readout.text, style: style),
        ),
    ],
  );
}

class _SlotSection extends ConsumerWidget {
  const _SlotSection({
    required this.slot,
    required this.entries,
    required this.date,
    required this.recipes,
    required this.foods,
  });

  final MealSlot slot;
  final List<ResolvedEntry> entries;
  final DateTime date;
  final Map<String, Recipe> recipes;
  final Map<String, Food> foods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final Macros slotTotal = Macros.sum(
      entries.map((ResolvedEntry e) => e.contribution),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(slot.label, style: context.text.sectionHeader),
            ),
            if (!slotTotal.isZero)
              Text(
                '${slotTotal.kcal.round()} kcal',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            const SizedBox(width: HearthSpacing.sm),
            IconButton(
              onPressed: () => showLogSheet(context, date: date, slot: slot),
              tooltip: 'Add to ${slot.label.toLowerCase()}',
              icon: Icon(Icons.add, color: colors.accent),
            ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
            child: Text(
              'Nothing yet',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          )
        else
          for (final ResolvedEntry entry in entries)
            _EntryRow(
              entry: entry,
              date: date,
              recipe: recipes[entry.entry.refId],
              food: foods[entry.entry.refId],
            ),
      ],
    );
  }
}

/// Opening a meal and recording eating are separate actions (UX-051).
///
/// The leading check keeps logging one tap. The body opens the current
/// source, while Cook starts the full saved recipe, never the personal
/// portion on this row. Swipe and the visible options keep their own jobs.
class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    required this.date,
    required this.recipe,
    required this.food,
  });

  final ResolvedEntry entry;
  final DateTime date;
  final Recipe? recipe;
  final Food? food;

  bool get _sourceAvailable => switch (entry.entry.refType) {
    PlanRefType.recipe => recipe != null && !recipe!.isDeleted,
    PlanRefType.food => food != null && !food!.isDeleted,
  };

  /// A missing serving makes nutrition uncostable, not the food unavailable.
  /// Logged names still belong to the snapshot, even when its source changed.
  String get _label {
    final String? frozen = entry.entry.macroSnapshot?.label;
    if (entry.entry.isLogged && frozen != null && frozen.isNotEmpty) {
      return frozen;
    }
    return switch (entry.entry.refType) {
      PlanRefType.recipe => recipe?.title ?? entry.label,
      PlanRefType.food => food?.name ?? entry.label,
    };
  }

  String get _sourceKind => switch (entry.entry.refType) {
    PlanRefType.recipe =>
      recipe?.isEatenOut ?? false ? 'Restaurant meal' : 'Recipe',
    PlanRefType.food => 'Food',
  };

  void _openSource(BuildContext context) {
    switch (entry.entry.refType) {
      case PlanRefType.recipe:
        context.push('/recipe/${entry.entry.refId}');
      case PlanRefType.food:
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => FoodDetailScreen(
              foodId: entry.entry.refId,
              servingOptionId: entry.entry.servingOptionId,
            ),
          ),
        );
    }
  }

  void _cook(BuildContext context, WidgetRef ref) {
    // Read again at the tap so a removed or reclassified source cannot enter
    // cook-along through a stale row. The recipe itself is the cook snapshot.
    Recipe? saved;
    for (final Recipe current
        in ref.read(recipeLibraryProvider).value ?? const <Recipe>[]) {
      if (current.id == entry.entry.refId && !current.isDeleted) {
        saved = current;
        break;
      }
    }
    if (saved == null) {
      _say(context, 'This recipe is no longer in your library.');
      return;
    }
    if (saved.isEatenOut) {
      _say(context, 'Restaurant meals do not have a cook-along.');
      return;
    }
    if (saved.allSteps.isEmpty) {
      _say(context, 'This recipe has no directions to cook along with yet.');
      return;
    }
    final Recipe snapshot = saved;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CookAlongScreen(recipe: snapshot),
      ),
    );
  }

  /// Confirms this entry as eaten, or puts it back to planned.
  ///
  /// Logging recomputes from the library rather than trusting anything stored
  /// on the row: repeating a meal should record what that food is now, and
  /// the snapshot is taken at this moment (§4).
  Future<LogStateChange?> _toggleLogged(LogStateFeedback feedback) async {
    // A row callback can outlive the frame that supplied its label and
    // nutrition. Resolve from the current library before creating history.
    final Map<String, Recipe> recipes = <String, Recipe>{
      for (final Recipe current
          in feedback.container.read(recipeLibraryProvider).value ??
              const <Recipe>[])
        if (!current.isDeleted) current.id: current,
    };
    final Map<String, Food> foods = <String, Food>{
      for (final Food current
          in feedback.container.read(foodLibraryProvider).value ??
              const <Food>[])
        if (!current.isDeleted) current.id: current,
    };
    final ResolvedEntry current = EntryResolver.resolve(
      entry.entry,
      recipes: recipes,
      foods: foods,
    );
    final bool available = switch (entry.entry.refType) {
      PlanRefType.recipe => recipes.containsKey(entry.entry.refId),
      PlanRefType.food => foods.containsKey(entry.entry.refId),
    };
    if (!entry.entry.isLogged && (current.isUncostable || !available)) {
      throw LogStateUnavailable(
        available
            ? 'This planned serving is no longer available. Open the food '
                  'to see its current servings.'
            : 'This ${entry.entry.refType.name} is no longer in your library '
                  'and cannot be logged.',
      );
    }
    final PlanRepository plans = feedback.repository;
    if (entry.entry.isLogged) {
      return plans.changeLogState(
        expected: entry.entry,
        logged: false,
        scope: feedback.scope,
      );
    } else {
      final Food? currentFood = entry.entry.refType == PlanRefType.food
          ? foods[entry.entry.refId]
          : null;
      final Recipe? currentRecipe = entry.entry.refType == PlanRefType.recipe
          ? recipes[entry.entry.refId]
          : null;
      final ServingOption? serving = currentFood == null
          ? null
          : EntryResolver.servingForEntry(
              currentFood,
              entry.entry.servingOptionId,
            );
      // Plan-only entries retain a serving count, not the raw input from
      // their earlier review. Record what this tap can establish now.
      final LoggedPortion? portion = LoggedPortion.tryCapture(
        amount: entry.entry.servings,
        unit: serving == null ? null : PortionUnit.serving(serving),
        servings: entry.entry.servings,
        standard: serving,
      );
      final bool approximate = currentRecipe != null
          ? MacroCalculator.forRecipe(
              currentRecipe,
              foods: foods,
            ).usesApproximatePackageNutrition
          : entry.entry.servingOptionId != null &&
                currentFood?.activePackageServing?.id ==
                    entry.entry.servingOptionId &&
                (currentFood?.packageNutrition?.isApproximate ?? false);
      return plans.changeLogState(
        expected: entry.entry,
        logged: true,
        scope: feedback.scope,
        liveMacros: current.perServing,
        // Beside the macros, from the same resolve. Reading coverage back off
        // `perServing` answers "complete" for a partial recipe, because a
        // total is non-null the moment *any* ingredient states the nutrient —
        // and this is the commonest gesture in the app to freeze that on
        // (spec §5.6).
        liveCoverage: current.liveCoverage,
        label: current.label,
        loggedPortion: portion,
        usesApproximatePackage: approximate,
      );
    }
  }

  Future<void> _remove(WidgetRef ref) async {
    await ref.read(planRepositoryProvider).removeEntry(entry.entry.id);
    ref.invalidate(dayEntriesProvider);
  }

  /// Puts back what a swipe took away — the same row, not a copy of it.
  ///
  /// The delete is real rather than a flag, but the entry keeps its identity
  /// through it: the same id, portion, slot, frozen numbers, and the moment it
  /// was actually eaten. Undo has to give back what was there, and a fresh
  /// planned copy is not that.
  Future<void> _restore(WidgetRef ref) async {
    // `restore`, not `add`. A logged entry's snapshot is already multiplied by
    // the portion, and `add` takes a per-serving figure and scales it — so
    // this route put back two servings of a 100 kcal meal as 400 kcal, and
    // half a serving as 25 (spec §4).
    await ref.read(planRepositoryProvider).restore(entry.entry);
    ref.invalidate(dayEntriesProvider);
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final _EntryAction? choice = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: context.colors.surface,
      // Scrollable, and constrained to most of the screen rather than all of
      // it. At three times the text on a small phone this sheet is 545 points
      // taller than the screen, and both of the things it exists to offer are
      // off the bottom — so a long-pressed meal cannot be edited or removed
      // at all (spec §6.3).
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Text(_label, style: context.text.sectionHeader),
            ),
            if (entry.entry.isLogged)
              ListTile(
                leading: Icon(
                  Icons.receipt_long_outlined,
                  color: context.colors.textSecondary,
                ),
                title: Text('View logged details', style: context.text.body),
                onTap: () =>
                    Navigator.of(context).pop(_EntryAction.loggedDetails),
              ),
            ListTile(
              leading: Icon(Icons.tune, color: context.colors.textSecondary),
              title: Text('Edit portion', style: context.text.body),
              onTap: () => Navigator.of(context).pop(_EntryAction.editPortion),
            ),
            // Correcting the day a meal is filed under used to mean deleting
            // it and logging it again — which freezes today's definition of
            // the food over what was actually eaten (review N02).
            ListTile(
              leading: Icon(
                Icons.swap_horiz,
                color: context.colors.textSecondary,
              ),
              title: Text(
                'Move to another day or meal…',
                style: context.text.body,
              ),
              subtitle: entry.entry.isLogged
                  ? Text(
                      'Keeps what it was worth when you ate it',
                      style: context.text.metadata.copyWith(
                        color: context.colors.textMuted,
                      ),
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(_EntryAction.move),
            ),
            // Named for what it does. "Copy" would leave open whether the
            // second one has been eaten, and it has not: a snapshot freezes
            // when a meal is logged and at no other time, so this plans one.
            ListTile(
              leading: Icon(
                Icons.event_repeat,
                color: context.colors.textSecondary,
              ),
              title: Text('Plan this again…', style: context.text.body),
              subtitle: Text(
                "Uses the food's nutrition as it stands then",
                style: context.text.metadata.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              onTap: () => Navigator.of(context).pop(_EntryAction.planAgain),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.colors.error),
              title: Text('Remove from this day', style: context.text.body),
              onTap: () => Navigator.of(context).pop(_EntryAction.remove),
            ),
            const SizedBox(height: HearthSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _EntryAction.loggedDetails:
        await _showLoggedDetails(context);
      case _EntryAction.editPortion:
        await showLogSheet(
          context,
          date: date,
          slot: entry.entry.slot,
          existing: entry,
        );
      case _EntryAction.move:
        await _move(context, ref);
      case _EntryAction.planAgain:
        await _planAgain(context, ref);
      case _EntryAction.remove:
        await _remove(ref);
    }
  }

  Future<void> _showLoggedDetails(BuildContext context) async {
    final LoggedDetailsAction? action = await showLoggedDetailsSheet(
      context,
      entry: entry.entry,
      sourceAvailable: _sourceAvailable,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case LoggedDetailsAction.editPortion:
        await showLogSheet(
          context,
          date: date,
          slot: entry.entry.slot,
          existing: entry,
        );
      case LoggedDetailsAction.viewCurrent:
        _openSource(context);
    }
  }

  /// Files this meal under another day or slot, as the same record.
  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final MealDestination? to = await showMealDestination(
      context,
      title: 'Move $_label',
      actionLabel: 'Move it',
      slot: entry.entry.slot,
    );
    if (to == null) return;
    await ref
        .read(planRepositoryProvider)
        .move(entry.entry, date: to.date, slot: to.slot);
    ref.invalidate(dayEntriesProvider);
    if (!context.mounted) return;
    _say(context, 'Moved to ${_whenAndWhere(to)}.');
  }

  /// Plans the same food or recipe, at the same portion, for another day.
  Future<void> _planAgain(BuildContext context, WidgetRef ref) async {
    final MealDestination? to = await showMealDestination(
      context,
      title: 'Plan $_label again',
      actionLabel: 'Plan it',
      slot: entry.entry.slot,
    );
    if (to == null) return;
    await ref
        .read(planRepositoryProvider)
        .copyAsPlanned(entry.entry, date: to.date, slot: to.slot);
    ref.invalidate(dayEntriesProvider);
    if (!context.mounted) return;
    _say(context, 'Planned for ${_whenAndWhere(to)}.');
  }

  /// Says what happened, because it happened somewhere else.
  ///
  /// Both of these put their result on a *different* day, so the screen the
  /// user is looking at is either unchanged — the copy — or has quietly lost
  /// a row, with no statement of where it went. `_copyDay` already answers
  /// the same question the same way.
  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  String _whenAndWhere(MealDestination to) =>
      '${to.slot.label.toLowerCase()} on ${shortDate(to.date)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool logged = entry.entry.isLogged;
    final LogStateFeedback feedback = LogStateFeedback(
      context,
      entryId: entry.entry.id,
    );
    final bool reflow = A11y.scaleOf(context) > A11y.reflowThreshold;
    final bool showCook =
        !logged &&
        entry.entry.refType == PlanRefType.recipe &&
        _sourceAvailable &&
        !recipe!.isEatenOut;
    final String calories = entry.isUncostable
        ? 'Nutrition unavailable'
        : '${entry.contribution.kcal.round()} kcal';

    Widget options() => IconButton(
      icon: const Icon(Icons.more_vert, size: 20),
      // Keep the established tooltip, with its own semantics outside Open.
      tooltip: 'Edit $_label',
      constraints: const BoxConstraints(
        minWidth: HearthTouch.minTarget,
        minHeight: HearthTouch.minTarget,
      ),
      onPressed: () => _showOptions(context, ref),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: SwipeToDelete(
        name: _label,
        onDelete: () => _remove(ref),
        onRestore: () => _restore(ref),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: HearthSpacing.xs),
                      child: IconButton(
                        key: ValueKey<String>('meal-log-${entry.entry.id}'),
                        tooltip: '${logged ? 'Unlog' : 'Log'} $_label',
                        constraints: const BoxConstraints(
                          minWidth: HearthTouch.kitchenTarget,
                          minHeight: HearthTouch.kitchenTarget,
                        ),
                        icon: Icon(
                          logged
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: logged ? colors.accent : colors.textMuted,
                        ),
                        onPressed: () =>
                            feedback.run(() => _toggleLogged(feedback)),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        key: ValueKey<String>('meal-open-${entry.entry.id}'),
                        container: true,
                        button: true,
                        label:
                            'Open ${_sourceKind.toLowerCase()} $_label. '
                            '$_detail. $calories.',
                        hint: 'Shows current library details',
                        onTap: () => _openSource(context),
                        onLongPress: () => _showOptions(context, ref),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => _openSource(context),
                          onLongPress: () => _showOptions(context, ref),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: HearthTouch.kitchenTarget,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: HearthSpacing.xs,
                                vertical: HearthSpacing.md,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(_label, style: text.ingredient),
                                  const SizedBox(height: HearthSpacing.xxs),
                                  Wrap(
                                    spacing: HearthSpacing.sm,
                                    runSpacing: HearthSpacing.xxs,
                                    children: <Widget>[
                                      Text(
                                        _detail,
                                        style: text.metadata.copyWith(
                                          color: colors.textMuted,
                                        ),
                                      ),
                                      Text(
                                        calories,
                                        style: text.metadata.copyWith(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!reflow)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: HearthSpacing.xs,
                          right: HearthSpacing.xs,
                        ),
                        child: options(),
                      ),
                  ],
                ),
                // Cook is below the meal, so enlarged text never has to fit
                // four actions across one row. Options reflows here too.
                if (showCook || reflow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HearthSpacing.md,
                      0,
                      HearthSpacing.md,
                      HearthSpacing.xs,
                    ),
                    child: Wrap(
                      spacing: HearthSpacing.md,
                      runSpacing: HearthSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (showCook) ...<Widget>[
                          TextButton.icon(
                            key: ValueKey<String>(
                              'meal-cook-${entry.entry.id}',
                            ),
                            onPressed: () => _cook(context, ref),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                HearthTouch.minTarget,
                                HearthTouch.minTarget,
                              ),
                            ),
                            icon: const Icon(Icons.soup_kitchen_outlined),
                            label: Text(
                              'Cook',
                              semanticsLabel: 'Cook $_label, full recipe',
                            ),
                          ),
                          Text(
                            'Full recipe · ${_portion(recipe!.servings)}',
                            style: text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                        if (reflow) options(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _detail {
    final MacroSnapshot? snapshot = entry.entry.isLogged
        ? entry.entry.macroSnapshot
        : null;
    final String portion = snapshot == null
        ? _portion(entry.entry.servings)
        : loggedPortionLabel(snapshot);
    final String status = entry.entry.isLogged ? 'logged' : 'planned';
    final String detail = '$_sourceKind · $status · $portion';
    if (!_sourceAvailable) return '$detail · source no longer in your library';
    if (entry.isUncostable) return '$detail · serving no longer available';
    return detail;
  }

  static String _portion(double servings) {
    final String amount = servings == servings.roundToDouble()
        ? servings.round().toString()
        : servings.toString();
    return servings == 1 ? '1 serving' : '$amount servings';
  }
}

/// What a long press offers.
enum _EntryAction { loggedDetails, editPortion, move, planAgain, remove }

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(HearthRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HearthRadius.lg),
            border: Border.all(color: colors.outline),
          ),
          padding: const EdgeInsets.all(HearthSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}
