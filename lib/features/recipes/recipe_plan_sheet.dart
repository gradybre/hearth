import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';

/// A reviewed personal portion and its destination. The caller saves it.
@immutable
class RecipePlanSelection {
  const RecipePlanSelection({
    required this.date,
    required this.slot,
    required this.servings,
  });

  final DateTime date;
  final MealSlot slot;
  final double servings;
}

/// Reviews a recipe for the user's plan without changing the shared recipe
/// or recording it as eaten. Cancelling returns no selection.
///
/// Today is captured when the sheet opens. A sheet left open across midnight
/// still adds to the date that was reviewed, even if its relative label changes.
Future<RecipePlanSelection?> showRecipePlanSheet(
  BuildContext context, {
  required Recipe recipe,
  DateTime Function()? clock,
}) {
  final DateTime Function() now = clock ?? DateTime.now;
  final DateTime today = dayKey(now().toLocal());
  return showModalBottomSheet<RecipePlanSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) =>
        _RecipePlanSheet(recipe: recipe, today: today, clock: now),
  );
}

class _RecipePlanSheet extends StatefulWidget {
  const _RecipePlanSheet({
    required this.recipe,
    required this.today,
    required this.clock,
  });

  final Recipe recipe;
  final DateTime today;
  final DateTime Function() clock;

  @override
  State<_RecipePlanSheet> createState() => _RecipePlanSheetState();
}

class _RecipePlanSheetState extends State<_RecipePlanSheet> {
  final TextEditingController _portion = TextEditingController(text: '1');
  final FocusNode _portionFocus = FocusNode();
  late DateTime _date = widget.today;
  MealSlot _slot = MealSlot.dinner;
  bool _invalidPortion = false;

  @override
  void dispose() {
    _portion.dispose();
    _portionFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    _portionFocus.unfocus();
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) => _RecipePlanDateDialog(
        initialText: MaterialLocalizations.of(context).formatCompactDate(_date),
        today: dayKey(widget.clock().toLocal()),
      ),
    );
    if (picked != null && mounted) setState(() => _date = dayKey(picked));
  }

  String get _recipeSummary {
    if (widget.recipe.isEatenOut) {
      return 'Choose your own portion of this restaurant meal.';
    }
    final double servings = widget.recipe.servings;
    if (!servings.isFinite || servings <= 0) {
      return 'The shared recipe has no valid yield yet. '
          'Your portion below is just for you.';
    }
    return 'The shared recipe makes ${QuantityFormat.count(servings)} '
        '${servings == 1 ? 'serving' : 'servings'}. '
        'Your portion below is just for you.';
  }

  void _add() {
    // Read the field before changing focus. A touch on Add does not send
    // keyboard Done, and the portion under the cursor is the reviewed one.
    final double? servings = parseAmount(_portion.text);
    if (servings == null || !servings.isFinite || servings <= 0) {
      setState(() => _invalidPortion = true);
      return;
    }
    Navigator.of(context)
        .pop(RecipePlanSelection(date: _date, slot: _slot, servings: servings));
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String dated =
        '${weekdayName(_date)} ${shortDate(_date)}/${_date.year}';
    final String? relative = relativeDay(
      _date,
      today: widget.clock().toLocal(),
    );
    final String dateLabel = relative == null ? dated : '$relative · $dated';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HearthRadius.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          // Header, fields and actions scroll together. At large text on a
          // short phone, fixed chrome alone could consume the whole sheet.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('My plan', style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.sm),
                Text(widget.recipe.title, style: context.text.recipeTitle),
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  _recipeSummary,
                  style: context.text.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HearthSpacing.xl),
                Text('Date', style: context.text.label),
                const SizedBox(height: HearthSpacing.xs),
                OutlinedButton(
                  key: const ValueKey<String>('recipe-plan-date'),
                  onPressed: _pickDate,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      HearthTouch.androidTarget,
                    ),
                    padding: const EdgeInsets.all(HearthSpacing.md),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.calendar_today_outlined, size: 20),
                      const SizedBox(width: HearthSpacing.sm),
                      Expanded(child: Text(dateLabel)),
                    ],
                  ),
                ),
                const SizedBox(height: HearthSpacing.lg),
                Text('Meal', style: context.text.label),
                const SizedBox(height: HearthSpacing.xs),
                Wrap(
                  spacing: HearthSpacing.sm,
                  runSpacing: HearthSpacing.xs,
                  children: <Widget>[
                    for (final MealSlot slot in MealSlot.values)
                      ChoiceChip(
                        label: Text(slot.label),
                        selected: _slot == slot,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (bool selected) {
                          if (selected) setState(() => _slot = slot);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: HearthSpacing.lg),
                Text('Your portion (servings)', style: context.text.label),
                const SizedBox(height: HearthSpacing.sm),
                Semantics(
                  label: 'Your portion in servings',
                  child: TextField(
                    controller: _portion,
                    focusNode: _portionFocus,
                    style: context.text.body,
                    // A full keyboard can type both decimals and fractions.
                    // Validate the whole input rather than dropping invalid
                    // characters and accidentally turning -1 into 1.
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _portionFocus.unfocus(),
                    onChanged: (_) {
                      if (_invalidPortion) {
                        setState(() => _invalidPortion = false);
                      }
                    },
                    decoration: InputDecoration(
                      error: _invalidPortion
                          ? Text(
                              'Enter a serving amount greater than zero.',
                              style: context.text.body.copyWith(
                                color: colors.error,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  'Fractions work here, like 1/2 or 1 1/2.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: HearthSpacing.xl),
                FilledButton(
                  onPressed: _add,
                  child: const Text(
                    'Add to my plan',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// All of the date review scrolls, including its actions. The stock calendar
/// overflows on a 320-point phone at 3x text and caps its header's scaling.
class _RecipePlanDateDialog extends StatefulWidget {
  const _RecipePlanDateDialog({required this.initialText, required this.today});

  final String initialText;
  final DateTime today;

  @override
  State<_RecipePlanDateDialog> createState() => _RecipePlanDateDialogState();
}

class _RecipePlanDateDialogState extends State<_RecipePlanDateDialog> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialText,
  );
  bool _invalid = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _choose(DateTime date) {
    _input.text = MaterialLocalizations.of(context).formatCompactDate(date);
    setState(() => _invalid = false);
  }

  void _useDate() {
    final String input = _input.text.trim();
    // A compact date has a four-digit year. Very large years can overflow
    // DateTime inside the platform parser and return a different calendar
    // year, so reject them before parsing rather than accepting that change.
    final DateTime? date = RegExp(r'\d{5,}').hasMatch(input)
        ? null
        : MaterialLocalizations.of(context).parseCompactDate(input);
    if (date == null || date.year < 1 || date.year > 9999) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(date);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return Dialog(
      constraints: const BoxConstraints(maxWidth: 560),
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.all(HearthSpacing.lg),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Plan date', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.lg),
            Text('Date', style: context.text.label),
            const SizedBox(height: HearthSpacing.sm),
            Semantics(
              label: 'Date for my plan',
              child: TextField(
                key: const ValueKey<String>('recipe-plan-date-input'),
                controller: _input,
                keyboardType: TextInputType.datetime,
                textInputAction: TextInputAction.done,
                style: context.text.body,
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
                decoration: InputDecoration(
                  error: _invalid
                      ? Text(
                          'Enter a valid date using ${localizations.dateHelpText}.',
                          style: context.text.body.copyWith(
                            color: colors.error,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              localizations.dateHelpText,
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.sm),
            Wrap(
              spacing: HearthSpacing.sm,
              children: <Widget>[
                TextButton(
                  onPressed: () => _choose(widget.today),
                  child: const Text('Today'),
                ),
                TextButton(
                  onPressed: () => _choose(addDays(widget.today, 1)),
                  child: const Text('Tomorrow'),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.lg),
            FilledButton(onPressed: _useDate, child: const Text('Use date')),
            const SizedBox(height: HearthSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
