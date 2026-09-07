import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/macro_rings.dart';
import '../../app/widgets/minor_nutrient_bars.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/week.dart';
import 'day_picker_sheet.dart';
import 'entry_resolver.dart';
import 'log_sheet.dart';
import 'macro_targets_sheet.dart';

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

    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

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

        return ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            HearthSpacing.lg,
            gutter,
            gutter * 3,
          ),
          children: <Widget>[
            _DayHeader(date: date),
            const SizedBox(height: HearthSpacing.lg),
            _RemainingCard(entries: resolved, targets: targets),
            const SizedBox(height: HearthSpacing.xl),
            for (final MealSlot slot in MealSlot.values) ...<Widget>[
              _SlotSection(
                slot: slot,
                entries: EntryResolver.inSlot(resolved, slot),
                date: date,
              ),
              const SizedBox(height: HearthSpacing.lg),
            ],
          ],
        );
      },
    );
  }
}

class _DayHeader extends ConsumerWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get _label {
    final DateTime today = dayKey(DateTime.now());
    final int delta = date.difference(today).inDays;
    if (delta == 0) return 'Today';
    if (delta == -1) return 'Yesterday';
    if (delta == 1) return 'Tomorrow';
    return _weekdays[date.weekday - 1];
  }

  String get _subtitle =>
      '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_label, style: context.text.recipeTitle),
              Text(
                _subtitle,
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () =>
              ref.read(selectedDateProvider.notifier).shiftDays(-1),
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          onPressed: () => ref.read(selectedDateProvider.notifier).today(),
          tooltip: 'Go to today',
          icon: const Icon(Icons.today_outlined),
        ),
        IconButton(
          onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(1),
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          onPressed: () => _copyDay(context, ref, date),
          tooltip: 'Copy this day to other days',
          icon: const Icon(Icons.copy_all_outlined),
        ),
      ],
    );
  }

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
  const _RemainingCard({required this.entries, required this.targets});

  final List<ResolvedEntry> entries;
  final MacroTargets? targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final Macros planned = EntryResolver.stillPlanned(entries);

    if (targets == null) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('No targets set for this week', style: context.text.body),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Set them once and every day this week measures against them.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.md),
            FilledButton(
              onPressed: () => showMacroTargetsSheet(context),
              child: const Text('Set weekly targets'),
            ),
          ],
        ),
      );
    }

    final DayProgress progress = DayProgress.fromParts(
      parts: EntryResolver.eatenParts(entries),
      coverage: EntryResolver.eatenCoverage(entries),
      targets: targets!,
    );

    final bool expanded = ref.watch(daySummaryExpandedProvider).value ?? false;

    return _Card(
      onTap: () => showMacroTargetsSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The rings lead with what has been eaten, so the card is no
              // longer "what is left" and does not say so. What is left is
              // under each ring, and only when it is worth saying.
              Expanded(child: Text('Today', style: context.text.sectionHeader)),
              if (!planned.isZero)
                Text(
                  '${planned.kcal.round()} kcal still planned',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: HearthSpacing.md),
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
            _CompactSummary(progress: progress),
          const SizedBox(height: HearthSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref
                  .read(daySummaryExpandedProvider.notifier)
                  .set(expanded: !expanded),
              child: Text(expanded ? 'Less' : 'Details'),
            ),
          ),
        ],
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
  const _CompactSummary({required this.progress});

  final DayProgress progress;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final MacroProgress kcal = progress.forKind(MacroKind.calories);
    // The ring's own judgement, not a fresh one. Mapping "met" onto "under"
    // made a day landing exactly on its target read "0 left" with a down
    // arrow here while the ring beside it said "on target" — the same day,
    // contradicted by two views of itself.
    final TargetIndicator calories = switch (kcal.tone) {
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
          label:
              '${kcal.consumed.round()} of ${kcal.target.round()} calories. '
              '${calories.semanticLabel}',
          excludeSemantics: true,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${kcal.consumed.round()} of ${kcal.target.round()} kcal',
                  style: context.text.body,
                ),
              ),
              // Never colour alone: the word travels with the arrow (§6.3).
              Icon(
                calories.icon,
                size: 16,
                color: kcal.isOver ? colors.overAccent : colors.textMuted,
              ),
              const SizedBox(width: HearthSpacing.xxs),
              Text(
                calories.shortLabel,
                style: context.text.metadata.copyWith(
                  color: kcal.isOver ? colors.overAccent : colors.textMuted,
                ),
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
      text: '$label ${macro.consumed.round()}/${macro.target.round()}$unit',
      // Spoken in words. A slash is punctuation and an unspaced unit is not a
      // word — the rings say "Protein: 20 of 150 g" and this has to say the
      // same thing, or the compact view is a downgrade for anyone listening
      // to it rather than looking at it (spec §6.3).
      spoken:
          '$label, ${macro.consumed.round()} of ${macro.target.round()} $unit.',
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
        text: '${kind.label} —/$target',
        // The word, not the dash: most screen readers pass over punctuation
        // at default verbosity, so "Fibre, of 28 g" would be both
        // ungrammatical and silent about the thing that matters.
        spoken:
            '${kind.label}, not stated, of ${nutrient.target.round()} '
            '${kind.unit}.'
            '${nutrient.countedParts == 0 ? ' Nothing logged yet.' : ''}',
      );
    }

    final String amount = nutrient.consumed!.round().toString();
    final bool floor = nutrient.coverage != MinorCoverage.complete;
    return _Readout(
      // "≥" rather than a bare number: at a glance it is the difference
      // between "you have had 14 g of fibre" and "you have had at least 14 g,
      // and something you ate never said".
      text: '${kind.label} ${floor ? '≥' : ''}$amount/$target',
      spoken:
          '${kind.label}, ${floor ? 'at least ' : ''}$amount of '
          '${nutrient.target.round()} ${kind.unit}.'
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
  });

  final MealSlot slot;
  final List<ResolvedEntry> entries;
  final DateTime date;

  static const Map<MealSlot, String> _titles = <MealSlot, String>{
    MealSlot.breakfast: 'Breakfast',
    MealSlot.lunch: 'Lunch',
    MealSlot.dinner: 'Dinner',
    MealSlot.snack: 'Snacks',
  };

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
              child: Text(_titles[slot]!, style: context.text.sectionHeader),
            ),
            if (!slotTotal.isZero)
              Text(
                '${slotTotal.kcal.round()} kcal',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            const SizedBox(width: HearthSpacing.sm),
            IconButton(
              onPressed: () => showLogSheet(context, date: date, slot: slot),
              tooltip: 'Add to ${_titles[slot]!.toLowerCase()}',
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
            _EntryRow(entry: entry, date: date),
      ],
    );
  }
}

/// One thing on the plate, and the three things you can do with it.
///
/// The gestures are the whole point of the day view: confirming a meal is the
/// thing you do most, so it is the plainest gesture there is.
///
///  * **Tap** logs it, or takes the log back. One tap either way — a meal
///    confirmed by mistake should cost exactly what confirming it cost.
///  * **Swipe** removes it, with the undo every other list in the app offers.
///  * **Long press** opens the rest: the portion, and a second way to remove.
///
/// Editing the portion used to be what a tap did, which put the commonest
/// action behind a sheet and a second tap.
class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.date});

  final ResolvedEntry entry;
  final DateTime date;

  /// Confirms this entry as eaten, or puts it back to planned.
  ///
  /// Logging recomputes from the library rather than trusting anything stored
  /// on the row: repeating a meal should record what that food is now, and
  /// the snapshot is taken at this moment (§4).
  Future<void> _toggleLogged(WidgetRef ref) async {
    final PlanRepository plans = ref.read(planRepositoryProvider);
    if (entry.entry.isLogged) {
      await plans.unlogEntry(entry.entry.id);
    } else {
      await plans.logEntry(
        entry.entry.id,
        liveMacros: entry.perServing,
        // Beside the macros, from the same resolve. Reading coverage back off
        // `perServing` answers "complete" for a partial recipe, because a
        // total is non-null the moment *any* ingredient states the nutrient —
        // and this is the commonest gesture in the app to freeze that on
        // (spec §5.6).
        liveCoverage: entry.liveCoverage,
        label: entry.label,
      );
    }
    ref.invalidate(dayEntriesProvider);
    ref.invalidate(recentLogsProvider);
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
              child: Text(entry.label, style: context.text.sectionHeader),
            ),
            ListTile(
              leading: Icon(Icons.tune, color: context.colors.textSecondary),
              title: Text('Edit portion', style: context.text.body),
              onTap: () => Navigator.of(context).pop(_EntryAction.editPortion),
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
      case _EntryAction.editPortion:
        await showLogSheet(
          context,
          date: date,
          slot: entry.entry.slot,
          existing: entry,
        );
      case _EntryAction.remove:
        await _remove(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool logged = entry.entry.isLogged;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: SwipeToDelete(
        name: entry.label,
        onDelete: () => _remove(ref),
        onRestore: () => _restore(ref),
        // The row's own semantics cover the part that logs; the button beside
        // it has its own. It sits outside them deliberately — the row
        // excludes its descendants, so a button placed inside would be
        // invisible to a screen reader, which is the opposite of the point.
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        '${entry.label}. ${_detail(entry, logged)}. '
                        '${logged ? 'Tap to unlog' : 'Tap to log'}.',
                    onTap: () => _toggleLogged(ref),
                    // Kept as a shortcut, not as the only way in (U06).
                    onLongPress: () => _showOptions(context, ref),
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => _toggleLogged(ref),
                      onLongPress: () => _showOptions(context, ref),
                      // Rounded on the left, where the card is, and square on
                      // the right, where the button begins. A full radius
                      // here clipped the ink to this box's own corners, so
                      // pressing the row drew two rounded edges in the middle
                      // of it and nothing under the calories or the button.
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(HearthRadius.md),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(HearthSpacing.md),
                        child: Row(
                          children: <Widget>[
                            // Logged versus planned is carried by an icon and a word,
                            // not by colour alone (spec §6.3).
                            Icon(
                              logged
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: logged ? colors.accent : colors.textMuted,
                            ),
                            const SizedBox(width: HearthSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(entry.label, style: text.ingredient),
                                  const SizedBox(height: HearthSpacing.xxs),
                                  Text(
                                    _detail(entry, logged),
                                    style: text.metadata.copyWith(
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${entry.contribution.kcal.round()}',
                              style: text.ingredient.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Visible, because a long press is not an affordance: nothing
                // on the row said the portion could be changed, so the way to
                // change it was something you either knew or did not (U06).
                Padding(
                  padding: const EdgeInsets.only(right: HearthSpacing.xs),
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    // The tooltip alone, as every other icon button here
                    // does. It is not merely a hover hint: iOS appends it to
                    // the accessibility label and Android sets it as the
                    // tooltip text, so both read it — and setting a matching
                    // `semanticLabel` as well had VoiceOver say the name
                    // twice.
                    tooltip: 'Edit ${entry.label}',
                    // Material's default is 40, which is under the floor a
                    // thumb needs (§6.3). Stated rather than inherited.
                    constraints: const BoxConstraints(
                      minWidth: HearthTouch.minTarget,
                      minHeight: HearthTouch.minTarget,
                    ),
                    onPressed: () => _showOptions(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _detail(ResolvedEntry entry, bool logged) {
    final String portion = _portion(entry.entry.servings);
    if (entry.isUncostable) return 'planned · no longer in your library';
    if (logged) return 'logged · $portion · tap to undo';
    return 'planned · $portion · tap to log';
  }

  static String _portion(double servings) {
    final String amount = servings == servings.roundToDouble()
        ? servings.round().toString()
        : servings.toString();
    return servings == 1 ? '1 serving' : '$amount servings';
  }
}

/// What a long press offers.
enum _EntryAction { editPortion, remove }

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
