import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/ink_card.dart';
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
import '../../domain/planning/nutrient_contributors.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/portion_unit.dart';
import '../../domain/planning/target_schedule.dart';
import '../../domain/planning/week.dart';
import '../../domain/recipes/macro_calculator.dart';
import 'day_picker_sheet.dart';
import 'entry_resolver.dart';
import 'log_sheet.dart';
import 'log_slot_sheet.dart';
import 'log_state_feedback.dart';
import 'logged_details_sheet.dart';
import 'macro_targets_sheet.dart';
import 'meal_source_actions.dart';
import 'nutrient_contributors_flow.dart';
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
                date: date,
                rawEntries: raw,
                entries: resolved,
                targets: targets,
                targetResolution: targetResolution,
              ),
              const SizedBox(height: HearthSpacing.lg),
              // The primary action, directly under the figure it changes.
              // Logging used to be a 24pt `+` at the end of a meal's heading
              // — four of them, each the smallest control on the screen, on
              // the screen the success bar is measured on. The `+`s are
              // still there for somebody who has already scrolled to the
              // meal they mean; this is the way in for somebody who has just
              // eaten.
              _LogFoodButton(date: date),
              const SizedBox(height: HearthSpacing.xl),
              // No "Meals" heading above these, although the templates draw
              // one. It is 36 points on the one screen where the fold is the
              // binding constraint: U01's promise is that you can see what
              // you ate for breakfast without scrolling past a summary of
              // it, and with the heading and the button both above it, you
              // could not. The four slot headings already name the group.
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

/// The day's primary action (spec §5.6, and the November 2026 templates).
///
/// Full width and filled, because logging is what this screen is for and
/// "every extra tap is a tax you pay three times a day" (§5.6). It asks
/// which meal before it opens the log sheet — see [showLogSlotSheet] for
/// why that is asked rather than guessed.
class _LogFoodButton extends StatelessWidget {
  const _LogFoodButton({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      // Sized for a kitchen rather than to the 48pt floor: this is pressed
      // with the hand that just put the pan down (spec §5.6, §6.3).
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(HearthTouch.kitchenTarget),
      ),
      onPressed: () => showLogSlotSheet(context, date: date),
      icon: const Icon(Icons.add),
      label: Text('Log food', style: context.text.label),
    ),
  );
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
class _RemainingCard extends ConsumerStatefulWidget {
  const _RemainingCard({
    required this.date,
    required this.rawEntries,
    required this.entries,
    required this.targets,
    required this.targetResolution,
  });

  final DateTime date;
  final List<MealPlanEntry> rawEntries;
  final List<ResolvedEntry> entries;
  final MacroTargets? targets;
  final ResolvedTargets? targetResolution;

  @override
  ConsumerState<_RemainingCard> createState() => _RemainingCardState();
}

class _RemainingCardState extends ConsumerState<_RemainingCard> {
  NutrientContributorsEntryGuard? _entryGuard;

  @override
  void dispose() {
    _entryGuard?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // These watches refresh the action when a lifetime changes. The guard's
    // subscriptions also invalidate the old callback before that next frame.
    ref.watch(currentUserIdProvider);
    ref.watch(currentHouseholdIdProvider);
    ref.watch(planRepositoryProvider);
    _entryGuard?.close();
    final NutrientContributorsEntryGuard guard = _entryGuard =
        NutrientContributorsEntryGuard(
          ProviderScope.containerOf(context, listen: false),
        );
    // Capture this widget, not the State's later widget or replacement guard.
    final _RemainingCard rendered = widget;
    final List<ResolvedEntry> entries = rendered.entries;
    final MacroTargets? targets = rendered.targets;
    // Ink, not `context.colors`, because everything this method builds is
    // drawn inside the [InkCard] below — and `context` here is *above* the
    // theme that card installs. Reading the ambient palette would hand
    // paper-cream tokens to text on a cocoa ground, which is not a subtle
    // failure: the §6.3 contrast sweep caught "Nothing logged yet" at
    // #6b5849 on #332a22, 2.09:1. Widgets built further down (the hero, the
    // compact summary, the rings) sit below the swap and read it correctly.
    final HearthColors colors = HearthColors.ink();
    final Macros planned = EntryResolver.stillPlanned(entries);

    final DayProgress progress = DayProgress.fromParts(
      parts: EntryResolver.eatenParts(entries),
      coverage: EntryResolver.eatenCoverage(entries),
      missingSnapshotCount: EntryResolver.missingSnapshotCount(entries),
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

    Future<void> showContributors(SupportedNutrient nutrient) => guard.open(
      context,
      date: rendered.date,
      nutrient: nutrient,
      entries: rendered.rawEntries,
    );

    return InkCard(
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
              const SizedBox(height: HearthSpacing.sm),
            ],
            // The headline, above everything including the "nothing logged"
            // and "incomplete" notes below it. Calories are what the screen
            // is opened to find out, and in the templates they are the one
            // thing readable from across a kitchen.
            //
            // **Collapsed only, and that is not a compromise.** Expanded is
            // §5.6's approved rings, and the calories ring is one of them —
            // so a headline above it would be the same figure twice, by two
            // controls, both answering to `macro-total-calories`. Collapsed
            // is also the default and the state the templates draw, so the
            // hero is what the day screen opens on.
            if (!expanded)
              _DayHero(
                progress: progress,
                compact: compact,
                onSelect: showContributors,
              ),
            if (progress.countedParts == 0) ...<Widget>[
              const SizedBox(height: HearthSpacing.xs),
              Text(
                'Nothing logged yet',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
            if (progress.missingSnapshotCount > 0) ...<Widget>[
              const SizedBox(height: HearthSpacing.xs),
              Text(
                progress.availability == SavedNutritionAvailability.unavailable
                    ? 'Saved nutrition unavailable'
                    : 'Known subtotal · incomplete',
                style: context.text.body,
              ),
              Text(
                '${progress.missingSnapshotCount} logged '
                '${progress.missingSnapshotCount == 1 ? 'meal has' : 'meals have'} '
                'no saved nutrition. Target comparisons are unavailable.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
            if (!compact || progress.countedParts == 0)
              SizedBox(height: compact ? HearthSpacing.xs : HearthSpacing.md),
            if (expanded) ...<Widget>[
              // All four rings, calories included, although the headline
              // above has already said the calories. The rings are §5.6's
              // approved expanded presentation and dropping one of them is
              // a decision about that presentation rather than about this
              // card's ground — Brendan's call, not a side effect.
              MacroRings(
                progress: progress,
                onSelect: (MacroKind kind) =>
                    showContributors(_supportedMacro(kind)),
              ),
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
              MinorNutrientBars(
                progress: progress,
                onSelect: (MinorNutrient kind) =>
                    showContributors(_supportedMinor(kind)),
              ),
            ] else
              _CompactSummary(progress: progress, onSelect: showContributors),
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
                  resolution: rendered.targetResolution,
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

/// The one figure the day screen is opened to find out (spec §5.6, and the
/// November 2026 templates).
///
/// Calories, as a sentence rather than a column: "1600 kcal left" in the
/// serif headline, a bar under it, and the totals it was worked out from
/// below that. It is the loudest thing on the loudest card because logging
/// speed is what Hearth is judged on, and the question people open this
/// screen with is how much is left.
///
/// **The word is the signal and the colour is the decoration** (spec §6.3).
/// "left", "over" and "on target" are in the headline itself, the arrow or
/// check repeats them, and the bar's colour is the third thing to say it
/// rather than the first.
///
/// It takes the calorie readout's judgement from [MacroProgress.tone] rather
/// than forming its own. Mapping "met" onto "under" is how a day landing
/// exactly on target came to read "0 left" with a down arrow beside a ring
/// that said "on target" — one day, contradicted by two views of itself.
class _DayHero extends StatelessWidget {
  const _DayHero({
    required this.progress,
    required this.compact,
    required this.onSelect,
  });

  final DayProgress progress;

  /// The card's own narrow-or-enlarged rule, not a second one.
  ///
  /// Past it the headline is not shrunk, it is **abandoned**: the card goes
  /// back to the one-line readout §5.6 approved, and the bar goes away with
  /// it. A 34pt headline is 102pt at three times the text, and the gentler
  /// fix of dropping it to the section-header role still left 60pt of
  /// "1400 kcal left" above a bar above the figures — which put the day's
  /// actual numbers off the bottom of a 320x568 phone. The integration
  /// sweep says so in as many words: a nutrition fact has to be above the
  /// initial fold.
  ///
  /// So the template's hero is the design for ordinary text, and this is
  /// what the same card does when the room runs out. Neither caps anything:
  /// both reflow, and both scale with the setting (spec §6.3).
  final bool compact;

  final ValueChanged<SupportedNutrient> onSelect;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final MacroProgress kcal = progress.forKind(MacroKind.calories);
    final int eaten = kcal.consumed.round();

    final TargetIndicator? indicator = !kcal.canCompare
        ? null
        : switch (kcal.tone) {
            MacroTone.over => TargetIndicator.forState(
              TargetState.over,
              amount: kcal.remaining!.abs().round().toString(),
            ),
            MacroTone.good when kcal.state == MacroProgressState.met =>
              TargetIndicator.forState(TargetState.met),
            MacroTone.good || MacroTone.neutral => TargetIndicator.forState(
              TargetState.under,
              amount: kcal.remaining!.round().toString(),
            ),
          };

    final String spoken = !kcal.hasKnownIntake
        ? 'Calories, saved nutrition unavailable.'
        : kcal.availability == SavedNutritionAvailability.partial
        ? '$eaten calories known subtotal. Incomplete saved nutrition.'
        : kcal.canCompare
        ? '$eaten of ${kcal.target.round()} calories. '
              '${indicator!.semanticLabel}'
        : '$eaten calories consumed.';

    if (compact) {
      // The readout as it was before the headline existed, word for word:
      // the amount and its unit together, the target wrapping to its own
      // line, and the state as an icon and a word under them.
      return _TotalAction(
        nutrient: SupportedNutrient.calories,
        onSelect: onSelect,
        label: spoken,
        child: Wrap(
          spacing: HearthSpacing.md,
          runSpacing: HearthSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              !kcal.hasKnownIntake
                  ? 'Calories —'
                  : kcal.availability == SavedNutritionAvailability.partial
                  ? '$eaten kcal known'
                  : '$eaten kcal',
              style: context.text.body.copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
            if (kcal.canCompare)
              Text('of ${kcal.target.round()} kcal', style: context.text.body),
            if (indicator != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    indicator.icon,
                    size: 16,
                    color: kcal.isOver ? colors.overAccent : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.xxs),
                  Text(
                    indicator.shortLabel,
                    style: context.text.metadata.copyWith(
                      color: kcal.isOver ? colors.overAccent : colors.textMuted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    // The headline, and whether there is anything to put under it. Only a day
    // with a target has a state to report; the other three cases are the
    // total itself, and a bar with nothing to fill against would be a
    // drawing of a number we do not have.
    final String headline;
    final String? totals;
    if (!kcal.hasKnownIntake) {
      headline = 'Calories —';
      totals = null;
    } else if (kcal.availability == SavedNutritionAvailability.partial) {
      headline = '$eaten kcal known';
      totals = null;
    } else if (indicator == null) {
      headline = '$eaten kcal';
      totals = null;
    } else {
      headline = switch (kcal.tone) {
        MacroTone.over => '${kcal.remaining!.abs().round()} kcal over',
        MacroTone.good when kcal.state == MacroProgressState.met => 'On target',
        // Neutral is the untouched day: still "left", and the honest amount.
        MacroTone.good ||
        MacroTone.neutral => '${kcal.remaining!.round()} kcal left',
      };
      // Unchanged wording, and deliberately: this is the line that used to be
      // the whole readout, and it is still the pair of numbers the headline
      // was worked out from.
      totals = '$eaten of ${kcal.target.round()} kcal';
    }

    final Color tone = kcal.isOver ? colors.overAccent : colors.accent;

    return Semantics(
      key: const ValueKey<String>('macro-total-calories'),
      label: spoken,
      hint: 'Show logged meals contributing to this total',
      button: true,
      onTap: () => onSelect(SupportedNutrient.calories),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onSelect(SupportedNutrient.calories),
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HearthTouch.androidTarget,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Wrap rather than Row: at three times the text "1600 kcal
              // left" is wider than a 320pt phone on its own, and the arrow
              // beside it has to drop to the next line rather than squeeze
              // the words it is repeating.
              Wrap(
                spacing: HearthSpacing.sm,
                runSpacing: HearthSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(headline, style: context.text.heroReadout),
                  if (indicator != null)
                    Icon(indicator.icon, size: 20, color: tone),
                ],
              ),
              if (totals != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(HearthRadius.sm),
                  child: LinearProgressIndicator(
                    value: kcal.barFill,
                    minHeight: 10,
                    backgroundColor: colors.progressTrack,
                    valueColor: AlwaysStoppedAnimation<Color>(tone),
                    // The headline above already says the number and the
                    // state; a bar repeating it is the same fact a third
                    // time, in a voice that cannot say "left".
                    semanticsLabel: null,
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  totals,
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The rest of the day in two lines, under the calorie headline
/// (spec §5.6).
///
/// Same numbers, same words, same three minor nutrients — including the ones
/// nothing has stated, which read as a dash. What it drops is the drawing:
/// the rings are the better picture of a day and the worse first screen,
/// because at ordinary text they push the first meal below the fold.
///
/// Calories are not here. They are [_DayHero], above this and above the
/// rings both, so that the figure the screen is read for is in one place
/// whichever view is open.
class _CompactSummary extends StatelessWidget {
  const _CompactSummary({required this.progress, required this.onSelect});

  final DayProgress progress;
  final ValueChanged<SupportedNutrient> onSelect;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _CompactRow(
          onSelect: onSelect,
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
          onSelect: onSelect,
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
    if (macro.availability != SavedNutritionAvailability.complete) {
      return _Readout(
        nutrient: _supportedMacro(macro.kind),
        text: macro.hasKnownIntake
            ? '$label ${macro.consumed.round()}$unit known'
            : '$label —',
        spoken: macro.hasKnownIntake
            ? '$label, ${macro.consumed.round()} $unit known subtotal. Incomplete saved nutrition.'
            : '$label, saved nutrition unavailable.',
      );
    }
    return _Readout(
      nutrient: _supportedMacro(macro.kind),
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

    if (nutrient.availability == SavedNutritionAvailability.unavailable) {
      return _Readout(
        nutrient: _supportedMinor(kind),
        text: '${kind.label} —',
        spoken: '${kind.label}, saved nutrition unavailable.',
      );
    }

    if (!nutrient.isKnown) {
      return _Readout(
        nutrient: _supportedMinor(kind),
        text: nutrient.canCompare
            ? '${kind.label} —/$target'
            : '${kind.label} —',
        // The word, not the dash: most screen readers pass over punctuation
        // at default verbosity, so "Fiber, of 28 g" would be both
        // ungrammatical and silent about the thing that matters.
        spoken:
            '${kind.label}, not stated${nutrient.canCompare ? ', of ${nutrient.target.round()} ${kind.unit}' : ''}.'
            '${nutrient.countedParts == 0 ? ' Nothing logged yet.' : ''}',
      );
    }

    final String amount = nutrient.consumed!.round().toString();
    final bool floor = nutrient.coverage != MinorCoverage.complete;
    return _Readout(
      nutrient: _supportedMinor(kind),
      // "≥" rather than a bare number: at a glance it is the difference
      // between "you have had 14 g of fiber" and "you have had at least 14 g,
      // and something you ate never said".
      text:
          '${kind.label} ${floor ? '≥' : ''}$amount${nutrient.canCompare ? '/$target' : kind.unit}',
      spoken:
          '${kind.label}, ${floor ? 'at least ' : ''}$amount${nutrient.canCompare ? ' of ${nutrient.target.round()}' : ''} ${kind.unit}.'
          '${floor ? ' Not a full count.' : ''}',
    );
  }
}

/// One short readout: what it looks like, and what it says.
class _Readout {
  const _Readout({
    required this.nutrient,
    required this.text,
    required this.spoken,
  });

  final SupportedNutrient nutrient;
  final String text;
  final String spoken;
}

/// Several short readouts on one line, wrapping rather than overflowing.
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.readouts,
    required this.style,
    required this.onSelect,
  });

  final List<_Readout> readouts;
  final TextStyle style;
  final ValueChanged<SupportedNutrient> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HearthSpacing.md,
    runSpacing: HearthSpacing.xxs,
    children: <Widget>[
      for (final _Readout readout in readouts)
        _TotalAction(
          nutrient: readout.nutrient,
          onSelect: onSelect,
          label: readout.spoken,
          child: Text(
            readout.text,
            style: style.copyWith(decoration: TextDecoration.underline),
          ),
        ),
    ],
  );
}

/// Compact totals keep their existing reading order, with independent full-size
/// touch targets. The summary's explicit target action remains a separate path.
class _TotalAction extends StatelessWidget {
  const _TotalAction({
    required this.nutrient,
    required this.onSelect,
    required this.label,
    required this.child,
  });

  final SupportedNutrient nutrient;
  final ValueChanged<SupportedNutrient> onSelect;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey<String>(
      '${nutrient.minor == null ? 'macro' : 'minor'}-total-${nutrient.name}',
    ),
    label: label,
    hint: 'Show logged meals contributing to this total',
    button: true,
    onTap: () => onSelect(nutrient),
    excludeSemantics: true,
    child: InkWell(
      onTap: () => onSelect(nutrient),
      excludeFromSemantics: true,
      borderRadius: BorderRadius.circular(HearthRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: HearthTouch.androidTarget,
          minHeight: HearthTouch.androidTarget,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    ),
  );
}

SupportedNutrient _supportedMacro(MacroKind kind) => switch (kind) {
  MacroKind.calories => SupportedNutrient.calories,
  MacroKind.protein => SupportedNutrient.protein,
  MacroKind.carbs => SupportedNutrient.carbs,
  MacroKind.fat => SupportedNutrient.fat,
};

SupportedNutrient _supportedMinor(MinorNutrient kind) => switch (kind) {
  MinorNutrient.fiber => SupportedNutrient.fiber,
  MinorNutrient.sodium => SupportedNutrient.sodium,
  MinorNutrient.cholesterol => SupportedNutrient.cholesterol,
};

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
    final int missing = EntryResolver.missingSnapshotCount(entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(slot.label, style: context.text.sectionHeader),
            ),
            if (!slotTotal.isZero && missing == 0)
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
        if (missing > 0)
          Text(
            entries.length == missing
                ? 'Saved nutrition unavailable'
                : '${slotTotal.kcal.round()} kcal known · incomplete',
            style: context.text.metadata.copyWith(color: colors.textMuted),
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
    openMealSource(context, entry.entry);
  }

  void _cook(BuildContext context, WidgetRef ref) {
    cookMealSource(context, ref, entry.entry);
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
    final String calories = entry.isSavedNutritionMissing
        ? 'Saved nutrition unavailable'
        : entry.isUncostable
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
