import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/planning/logged_portion.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';

enum LoggedDetailsAction { editPortion, viewCurrent }

/// A history receipt reads only the snapshot. Choosing another action closes
/// it first, so the caller can open the editor or today's source separately.
Future<LoggedDetailsAction?> showLoggedDetailsSheet(
  BuildContext context, {
  required MealPlanEntry entry,
  required bool sourceAvailable,
}) => showModalBottomSheet<LoggedDetailsAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) =>
      LoggedDetailsSheet(entry: entry, sourceAvailable: sourceAvailable),
);

/// The authored numeric amount is retained without the input field's display
/// rounding. Literal spelling and trailing zeros are not part of the record.
String loggedPortionLabel(MacroSnapshot snapshot) {
  final LoggedPortion? portion = snapshot.usableLoggedPortion;
  if (portion == null) {
    final double servings = snapshot.servings;
    if (!servings.isFinite || servings <= 0) {
      return 'Saved portion not available';
    }
    return '${_exactAmount(servings)} ${servings == 1 ? 'serving' : 'servings'}';
  }
  final String amount = portion.enteredUnit.isRaw
      ? _number(portion.enteredAmount)
      : _exactAmount(portion.enteredAmount);
  return '$amount ${portion.enteredUnit.isRaw ? '' : '× '}${portion.enteredUnit.label}';
}

String _exactAmount(double value) {
  final String fraction = writeAmount(value);
  // writeAmount tolerates nearby kitchen fractions for an editable field.
  // History may use that spelling only when it retains this parsed number.
  return parseAmount(fraction) == value ? fraction : _number(value);
}

String _number(double value) {
  final String text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

class LoggedDetailsSheet extends StatelessWidget {
  const LoggedDetailsSheet({
    required this.entry,
    required this.sourceAvailable,
    super.key,
  });

  final MealPlanEntry entry;
  final bool sourceAvailable;

  @override
  Widget build(BuildContext context) {
    final MacroSnapshot? snapshot = entry.isLogged ? entry.macroSnapshot : null;
    final LoggedPortion? portion = snapshot?.usableLoggedPortion;
    final HearthColors colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController controller) =>
            Material(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(HearthRadius.xl),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        'Logged details',
                        style: context.text.sectionHeader,
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.md),
                    if (snapshot == null)
                      Text(
                        'Saved nutrition is unavailable for this meal.',
                        style: context.text.body,
                      )
                    else ...<Widget>[
                      Text(
                        snapshot.label.trim().isEmpty
                            ? 'Name not recorded'
                            : snapshot.label,
                        style: context.text.recipeTitle,
                      ),
                      const SizedBox(height: HearthSpacing.sm),
                      Text(
                        loggedPortionLabel(snapshot),
                        style: context.text.body,
                      ),
                      if (portion != null)
                        Text(
                          _equivalence(snapshot, portion),
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        )
                      else if (entry.refType == PlanRefType.food)
                        Text(
                          snapshot.loggedPortion != null ||
                                  snapshot.unreadFields['logged_portion'] !=
                                      null
                              ? 'The original amount is unavailable. These are the saved servings.'
                              : 'The original amount wasn’t recorded. These are the saved servings.',
                          style: context.text.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: HearthSpacing.md),
                      Text(
                        'Saved nutrition for this portion. Later changes to the library do not change this log.',
                        style: context.text.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (snapshot.usesApproximatePackageNutrition) ...<Widget>[
                        const SizedBox(height: HearthSpacing.sm),
                        Text(
                          'Uses approximate package servings',
                          style: context.text.body,
                        ),
                      ],
                      const SizedBox(height: HearthSpacing.lg),
                      _SavedNutrient(
                        label: 'Calories',
                        value: snapshot.macros.kcal,
                        unit: 'kcal',
                      ),
                      _SavedNutrient(
                        label: 'Protein',
                        value: snapshot.macros.proteinG,
                        unit: 'g',
                      ),
                      _SavedNutrient(
                        label: 'Carbohydrate',
                        value: snapshot.macros.carbG,
                        unit: 'g',
                      ),
                      _SavedNutrient(
                        label: 'Fat',
                        value: snapshot.macros.fatG,
                        unit: 'g',
                      ),
                      for (final MinorNutrient nutrient in MinorNutrient.values)
                        _SavedNutrient(
                          label: nutrient.label,
                          value: snapshot.macros.minor(nutrient),
                          unit: nutrient.unit,
                          coverage: snapshot.coverage.of(nutrient),
                        ),
                      const SizedBox(height: HearthSpacing.md),
                      Text(
                        _recordedAt(context, snapshot.capturedAt),
                        style: context.text.metadata,
                      ),
                      const SizedBox(height: HearthSpacing.lg),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context)
                                .pop(LoggedDetailsAction.editPortion),
                        child: const Text('Edit portion'),
                      ),
                      const SizedBox(height: HearthSpacing.sm),
                      if (sourceAvailable)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HearthSpacing.lg,
                              vertical: HearthSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                HearthRadius.md,
                              ),
                            ),
                          ),
                          onPressed: () =>
                              Navigator.of(context)
                                  .pop(LoggedDetailsAction.viewCurrent),
                          child: Text(
                            entry.refType == PlanRefType.food
                                ? 'View current food'
                                : 'View current recipe',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Text(
                          'The current library item is unavailable. Your saved log is still here.',
                          style: context.text.body,
                        ),
                    ],
                    const SizedBox(height: HearthSpacing.sm),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  String _equivalence(MacroSnapshot snapshot, LoggedPortion portion) {
    final double count = snapshot.servings;
    final String exact = _exactAmount(count);
    // The entered amount above is exact. Its secondary serving equivalent
    // can be a shorter readout, and says "about" whenever it is rounded.
    final double rounded = double.parse(count.toStringAsFixed(3));
    final String shown = exact.contains('/') || rounded == count || rounded == 0
        ? exact
        : _number(rounded);
    final bool approximate =
        snapshot.usesApproximatePackageNutrition || parseAmount(shown) != count;
    return 'Equivalent to ${approximate ? 'about ' : ''}$shown × '
        '${portion.nutritionServing.label} at log time.';
  }

  String _recordedAt(BuildContext context, DateTime capturedAt) {
    // The tolerant mapper uses the Unix epoch for absent/unreadable times.
    // It is not evidence that somebody recorded a meal in 1970.
    if (capturedAt.millisecondsSinceEpoch <= 0) {
      return 'Recorded time not available';
    }
    final DateTime local = capturedAt.toLocal();
    final MaterialLocalizations labels = MaterialLocalizations.of(context);
    return 'Recorded on ${labels.formatFullDate(local)} · '
        '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

class _SavedNutrient extends StatelessWidget {
  const _SavedNutrient({
    required this.label,
    required this.value,
    required this.unit,
    this.coverage,
  });

  final String label;
  final double? value;
  final String unit;
  final MinorCoverage? coverage;

  @override
  Widget build(BuildContext context) {
    final double? number = value;
    // Explicit unknown coverage cannot turn a legacy placeholder zero into
    // a historical claim that this nutrient was measured as zero.
    final bool known =
        number != null && number.isFinite && coverage != MinorCoverage.unknown;
    final String amount = known
        ? '${coverage == MinorCoverage.partial ? 'At least ' : ''}${_nutritionNumber(number)} $unit'
        : 'Unknown';
    final String? qualifier = switch (coverage) {
      MinorCoverage.partial => 'Partial nutrition recorded',
      MinorCoverage.unknown => 'No value was available',
      MinorCoverage.notRecorded => 'Coverage was not recorded',
      MinorCoverage.complete || null => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
      child: Semantics(
        label: '$label: $amount${qualifier == null ? '' : '. $qualifier'}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$label: $amount', style: context.text.body),
            if (qualifier != null)
              Text(
                qualifier,
                style: context.text.metadata.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _nutritionNumber(double value) {
    final int decimals = unit == 'g' ? 1 : 0;
    // A partial total is a floor. Rounding that floor upward would claim
    // more known nutrition than the snapshot actually contains.
    final double factor = decimals == 1 ? 10 : 1;
    final double display = coverage == MinorCoverage.partial
        ? (value * factor).floorToDouble() / factor
        : value;
    final String number = display.toStringAsFixed(decimals);
    return number.replaceFirst(RegExp(r'\.0$'), '');
  }
}
