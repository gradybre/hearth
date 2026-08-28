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
    final HearthColors colors = context.colors;
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

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: entries.when(
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
              padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 3),
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
        ),
      ),
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
      ],
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
    final int columns = A11y.macroColumns(context);

    return _Card(
      onTap: () => showMacroTargetsSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Left today', style: context.text.sectionHeader),
              ),
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
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double spacing = HearthSpacing.md;
              final double itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  for (final MacroProgress macro in progress.all)
                    SizedBox(
                      width: itemWidth,
                      child: _MacroTile(macro: macro),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({required this.macro});

  final MacroProgress macro;

  static const Map<MacroKind, String> _labels = <MacroKind, String>{
    MacroKind.calories: 'kcal',
    MacroKind.protein: 'protein',
    MacroKind.carbs: 'carbs',
    MacroKind.fat: 'fat',
  };

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    final TargetState state = switch (macro.state) {
      MacroProgressState.under => TargetState.under,
      MacroProgressState.met => TargetState.met,
      MacroProgressState.over => TargetState.over,
    };
    final String amount = '${macro.remaining.abs().round()}';
    final TargetIndicator indicator = TargetIndicator.forState(
      state,
      amount: amount,
    );
    final Color barColor = macro.isOver ? colors.overAccent : colors.accent;

    return Semantics(
      label: '${_labels[macro.kind]}: ${indicator.semanticLabel}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(amount, style: text.macroReadout),
          const SizedBox(height: HearthSpacing.xxs),
          Row(
            children: <Widget>[
              Icon(indicator.icon, size: 14, color: colors.textMuted),
              const SizedBox(width: HearthSpacing.xxs),
              Flexible(
                child: Text(
                  '${_labels[macro.kind]} ${macro.isOver ? 'over' : 'left'}',
                  style: text.metadata.copyWith(color: colors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(HearthRadius.sm),
            child: LinearProgressIndicator(
              value: macro.barFill,
              minHeight: 6,
              backgroundColor: colors.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
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

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.date});

  final ResolvedEntry entry;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool logged = entry.entry.isLogged;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => showLogSheet(
            context,
            date: date,
            slot: entry.entry.slot,
            existing: entry,
          ),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                // Logged versus planned is carried by an icon and a word, not
                // by colour alone (spec §6.3).
                Icon(
                  logged ? Icons.check_circle : Icons.radio_button_unchecked,
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
                        style: text.metadata.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${entry.contribution.kcal.round()}',
                  style: text.ingredient.copyWith(color: colors.textSecondary),
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
    if (logged) return 'logged · $portion';
    return 'planned · $portion · tap to log';
  }

  static String _portion(double servings) {
    final String amount = servings == servings.roundToDouble()
        ? servings.round().toString()
        : servings.toString();
    return servings == 1 ? '1 serving' : '$amount servings';
  }
}

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
