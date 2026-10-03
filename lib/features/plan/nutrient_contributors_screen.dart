import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_contributors.dart';
import 'logged_details_sheet.dart';

/// A captured day's saved nutrition. The caller owns current-source lookup,
/// account guards and navigation; rebuilding this screen cannot re-cost history.
class NutrientContributorsScreen extends StatelessWidget {
  const NutrientContributorsScreen({
    required this.contributors,
    required this.onOpenLoggedDetails,
    required this.onImproveFuture,
    required this.isSourceAvailable,
    super.key,
  });

  final DailyNutrientContributors contributors;
  final Future<void> Function(MealPlanEntry) onOpenLoggedDetails;
  final Future<void> Function(MealPlanEntry) onImproveFuture;
  final bool Function(MealPlanEntry) isSourceAvailable;

  @override
  Widget build(BuildContext context) {
    final SupportedNutrient nutrient = contributors.nutrient;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: HearthLayout.readingWidth,
            ),
            child: ListView(
              key: const ValueKey<String>('nutrient-contributors-scroll'),
              padding: const EdgeInsets.all(HearthSpacing.lg),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>('nutrient-contributors-back'),
                    onPressed: () async {
                      await Navigator.maybePop(context);
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                _Heading('${nutrient.label} contributors'),
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  MaterialLocalizations.of(context)
                      .formatFullDate(contributors.date),
                  style: context.text.body,
                ),
                const SizedBox(height: HearthSpacing.lg),
                _Total(contributors),
                if (contributors.knownContributors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.xl),
                  const _Heading('Logged meals'),
                  const SizedBox(height: HearthSpacing.md),
                  for (final NutrientContributor row
                      in contributors.knownContributors)
                    _ContributorCard(
                      contributor: row,
                      nutrient: nutrient,
                      missing: false,
                      percentage: contributors.percentageOf(row),
                      completeTotal: contributors.isComplete,
                      sourceAvailable: isSourceAvailable(row.entry),
                      onOpenLoggedDetails: onOpenLoggedDetails,
                      onImproveFuture: onImproveFuture,
                    ),
                ],
                if (contributors.missingInformation.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.xl),
                  const _Heading('Missing information'),
                  const SizedBox(height: HearthSpacing.sm),
                  Text(
                    'These gaps were saved with the log. Known amounts above are counted only once.',
                    style: context.text.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.md),
                  for (final NutrientContributor row
                      in contributors.missingInformation)
                    _ContributorCard(
                      contributor: row,
                      nutrient: nutrient,
                      missing: true,
                      percentage: null,
                      completeTotal: false,
                      sourceAvailable: isSourceAvailable(row.entry),
                      onOpenLoggedDetails: onOpenLoggedDetails,
                      onImproveFuture: onImproveFuture,
                    ),
                ],
                if (contributors.entries.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.md),
                  Text(
                    'Improve future logs opens the current food or recipe. Changes there do not recalculate this day.',
                    style: context.text.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: HearthSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: context.text.sectionHeader),
  );
}

class _Total extends StatelessWidget {
  const _Total(this.contributors);
  final DailyNutrientContributors contributors;

  @override
  Widget build(BuildContext context) {
    final SupportedNutrient nutrient = contributors.nutrient;
    final double? total = contributors.knownTotal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.outline),
        borderRadius: BorderRadius.circular(HearthRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (contributors.entries.isEmpty)
              Text('Nothing logged yet', style: context.text.body)
            else if (total == null)
              Text(
                contributors.knownContributors.isEmpty
                    ? 'No saved ${nutrient.label.toLowerCase()} values'
                    : 'The saved amounts cannot form a usable total.',
                style: context.text.body,
              )
            else ...<Widget>[
              Text(
                contributors.isComplete || contributors.hasUnrecordedCoverage
                    ? 'Saved total'
                    : 'Known total',
                style: context.text.label,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(_amount(total, nutrient), style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                contributors.hasUnrecordedCoverage
                    ? 'Some ${nutrient.label.toLowerCase()} coverage was not recorded. These saved values cannot establish a complete total.'
                    : contributors.isComplete
                    ? 'From the amounts saved when these meals were logged.'
                    : 'This is the known amount, with missing information listed below.',
                style: context.text.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              if (contributors.hasSignedContributions) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  'Includes a saved negative contribution. Percentages are not shown.',
                  style: context.text.body,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ContributorCard extends StatelessWidget {
  const _ContributorCard({
    required this.contributor,
    required this.nutrient,
    required this.missing,
    required this.percentage,
    required this.completeTotal,
    required this.sourceAvailable,
    required this.onOpenLoggedDetails,
    required this.onImproveFuture,
  });

  final NutrientContributor contributor;
  final SupportedNutrient nutrient;
  final bool missing;
  final double? percentage;
  final bool completeTotal;
  final bool sourceAvailable;
  final Future<void> Function(MealPlanEntry) onOpenLoggedDetails;
  final Future<void> Function(MealPlanEntry) onImproveFuture;

  @override
  Widget build(BuildContext context) {
    final MealPlanEntry entry = contributor.entry;
    final MacroSnapshot? snapshot = entry.macroSnapshot;
    final String name = snapshot == null
        ? 'Logged ${entry.refType.name}'
        : snapshot.label.trim().isEmpty
        ? 'Name not recorded'
        : snapshot.label;
    final String section = missing ? 'missing' : 'known';
    // A partial/legacy meal already has its improvement action in the gap
    // section. Its saved amount above remains a single, readable contribution.
    final bool showImprovement = missing || contributor.gap == null;
    final BorderRadius radius = BorderRadius.circular(HearthRadius.md);
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: context.colors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: 'View logged details for $name',
              button: true,
              child: InkWell(
                key: ValueKey<String>('contributor-$section-open-${entry.id}'),
                borderRadius: radius,
                onTap: () async {
                  await onOpenLoggedDetails(entry);
                },
                child: Padding(
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name, style: context.text.sectionHeader),
                      const SizedBox(height: HearthSpacing.sm),
                      Text(entry.slot.label, style: context.text.metadata),
                      if (snapshot != null)
                        Text(
                          loggedPortionLabel(snapshot),
                          style: context.text.body,
                        ),
                      const SizedBox(height: HearthSpacing.md),
                      if (missing)
                        Text(
                          _gapExplanation(contributor.gap!),
                          style: context.text.body,
                        )
                      else ...<Widget>[
                        Text(
                          _amount(contributor.amount!, nutrient),
                          style: context.text.sectionHeader,
                        ),
                        if (contributor.gap == NutrientInformationGap.partial)
                          Text(
                            'Partial ${nutrient.label.toLowerCase()} information',
                            style: context.text.body,
                          ),
                        if (contributor.gap ==
                            NutrientInformationGap.coverageNotRecorded)
                          Text(
                            '${nutrient.label} coverage not recorded',
                            style: context.text.body,
                          ),
                        if (percentage != null)
                          Text(
                            '${_percentage(percentage!)}% of ${completeTotal ? 'total' : 'known total'}',
                            style: context.text.body.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                      ],
                      if (snapshot?.usesApproximatePackageNutrition ==
                          true) ...<Widget>[
                        const SizedBox(height: HearthSpacing.sm),
                        Text(
                          'Uses approximate package servings',
                          style: context.text.body,
                        ),
                      ],
                      const SizedBox(height: HearthSpacing.md),
                      Text(
                        'View logged details',
                        style: context.text.label.copyWith(
                          color: context.colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showImprovement)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HearthSpacing.lg,
                  0,
                  HearthSpacing.lg,
                  HearthSpacing.lg,
                ),
                child: sourceAvailable
                    ? Semantics(
                        label: 'For $name',
                        child: OutlinedButton(
                          key: ValueKey<String>(
                            'contributor-$section-improve-${entry.id}',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HearthSpacing.lg,
                              vertical: HearthSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: radius),
                          ),
                          onPressed: () async {
                            await onImproveFuture(entry);
                          },
                          child: const Text(
                            'Improve future logs',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Text(
                        'The current ${entry.refType.name} is unavailable. This saved log is unchanged.',
                        style: context.text.body.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  String _gapExplanation(NutrientInformationGap gap) {
    final String lower = nutrient.label.toLowerCase();
    return switch (gap) {
      NutrientInformationGap.snapshotUnavailable =>
        'Saved nutrition is unavailable for this meal.',
      NutrientInformationGap.valueUnavailable =>
        'No $lower value was saved for this meal.',
      NutrientInformationGap.partial =>
        'Some $lower information was missing when this meal was logged.',
      NutrientInformationGap.coverageNotRecorded =>
        '${nutrient.label} coverage was not recorded for this meal.',
    };
  }
}

/// Shorten only the display, and qualify any number that no longer parses to
/// the saved value. Significant digits retain tiny nonzero and signed amounts.
String _amount(double value, SupportedNutrient nutrient) {
  final double displayed = double.parse(value.toStringAsPrecision(6));
  final String number = displayed == 0
      ? '0'
      : displayed.toString().replaceFirst(RegExp(r'\.0$'), '');
  return '${displayed == value ? '' : 'about '}$number ${nutrient.unit}';
}

String _percentage(double value) {
  if (value > 0 && value < 0.1) return '<0.1';
  return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
