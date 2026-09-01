import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/macro_rings.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
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
    final Macros eaten = EntryResolver.eaten(entries);
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

    final DayProgress progress = DayProgress.from(
      consumed: eaten,
      targets: targets!,
    );

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
          MacroRings(progress: progress),
        ],
      ),
    );
  }
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

  /// Puts back what a swipe took away.
  ///
  /// A new row rather than the same one — the delete is real, not a flag —
  /// but with the portion and, for a logged meal, the frozen numbers it had.
  /// Undo has to give back what was there, not a fresh planned copy of it.
  Future<void> _restore(WidgetRef ref) async {
    await ref
        .read(planRepositoryProvider)
        .add(
          date: date,
          slot: entry.entry.slot,
          refType: entry.entry.refType,
          refId: entry.entry.refId,
          servings: entry.entry.servings,
          loggedMacros: entry.entry.isLogged
              ? entry.entry.macroSnapshot?.macros
              : null,
          label: entry.entry.isLogged ? entry.label : null,
        );
    ref.invalidate(dayEntriesProvider);
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final _EntryAction? choice = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: context.colors.surface,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
        child: Semantics(
          button: true,
          label:
              '${entry.label}. ${_detail(entry, logged)}. '
              '${logged ? 'Tap to unlog' : 'Tap to log'}.',
          onTap: () => _toggleLogged(ref),
          onLongPress: () => _showOptions(context, ref),
          excludeSemantics: true,
          child: Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: InkWell(
              onTap: () => _toggleLogged(ref),
              onLongPress: () => _showOptions(context, ref),
              borderRadius: BorderRadius.circular(HearthRadius.md),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  border: Border.all(color: colors.outline),
                ),
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
