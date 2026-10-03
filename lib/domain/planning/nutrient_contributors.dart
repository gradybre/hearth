import 'package:meta/meta.dart';

import '../models/macros.dart';
import 'meal_plan.dart';
import 'nutrient_coverage.dart';

/// The existing daily intake fields; targets do not affect this receipt.
enum SupportedNutrient {
  calories,
  protein,
  carbs,
  fat,
  fiber,
  sodium,
  cholesterol,
}

extension SupportedNutrientDetails on SupportedNutrient {
  String get label => switch (this) {
    SupportedNutrient.calories => 'Calories',
    SupportedNutrient.protein => 'Protein',
    SupportedNutrient.carbs => 'Carbohydrate',
    SupportedNutrient.fat => 'Fat',
    SupportedNutrient.fiber => 'Fibre',
    SupportedNutrient.sodium => 'Sodium',
    SupportedNutrient.cholesterol => 'Cholesterol',
  };

  String get unit => switch (this) {
    SupportedNutrient.calories => 'kcal',
    SupportedNutrient.sodium || SupportedNutrient.cholesterol => 'mg',
    _ => 'g',
  };

  MinorNutrient? get minor => switch (this) {
    SupportedNutrient.fiber => MinorNutrient.fiber,
    SupportedNutrient.sodium => MinorNutrient.sodium,
    SupportedNutrient.cholesterol => MinorNutrient.cholesterol,
    _ => null,
  };

  double? savedAmount(Macros macros) => switch (this) {
    SupportedNutrient.calories => macros.kcal,
    SupportedNutrient.protein => macros.proteinG,
    SupportedNutrient.carbs => macros.carbG,
    SupportedNutrient.fat => macros.fatG,
    SupportedNutrient.fiber => macros.fiberG,
    SupportedNutrient.sodium => macros.sodiumMg,
    SupportedNutrient.cholesterol => macros.cholesterolMg,
  };
}

/// Only gaps established by stored evidence. Major-nutrient ingredient
/// coverage is not recorded, so minor coverage cannot qualify those totals.
enum NutrientInformationGap {
  snapshotUnavailable,
  valueUnavailable,
  partial,
  coverageNotRecorded,
}

@immutable
class NutrientContributor {
  const NutrientContributor({
    required this.entry,
    required this.amount,
    required this.coverage,
    required this.gap,
  });

  final MealPlanEntry entry;
  final double? amount;
  final MinorCoverage? coverage;
  final NutrientInformationGap? gap;

  static NutrientContributor _from(
    MealPlanEntry entry,
    SupportedNutrient nutrient,
  ) {
    final MacroSnapshot? snapshot = entry.macroSnapshot;
    if (snapshot == null) {
      return NutrientContributor(
        entry: entry,
        amount: null,
        coverage: null,
        gap: NutrientInformationGap.snapshotUnavailable,
      );
    }
    final MinorNutrient? minor = nutrient.minor;
    final MinorCoverage? coverage = minor == null
        ? null
        : snapshot.coverage.of(minor);
    final double? saved = nutrient.savedAmount(snapshot.macros);
    final double? amount =
        saved != null && saved.isFinite && coverage != MinorCoverage.unknown
        ? saved
        : null;
    return NutrientContributor(
      entry: entry,
      amount: amount,
      coverage: coverage,
      gap: amount == null
          ? NutrientInformationGap.valueUnavailable
          : switch (coverage) {
              MinorCoverage.partial => NutrientInformationGap.partial,
              MinorCoverage.notRecorded =>
                NutrientInformationGap.coverageNotRecorded,
              _ => null,
            },
    );
  }
}

/// An immutable receipt for one captured diary date. The caller supplies that
/// day's entries; no library, clock, current selection or target is consulted.
///
/// Nutrition already describes the saved portion. In particular, neither the
/// entry's current serving count nor live recipe nutrition may rescale it.
@immutable
class DailyNutrientContributors {
  factory DailyNutrientContributors({
    required DateTime date,
    required SupportedNutrient nutrient,
    required Iterable<MealPlanEntry> entries,
  }) {
    final List<MealPlanEntry> logged = List<MealPlanEntry>.unmodifiable(
      entries.where((MealPlanEntry entry) => entry.isLogged),
    );
    final List<NutrientContributor> rows = <NutrientContributor>[
      for (final MealPlanEntry entry in logged)
        NutrientContributor._from(entry, nutrient),
    ];
    final List<NutrientContributor> known =
        List<NutrientContributor>.unmodifiable(
          rows.where((NutrientContributor row) => row.amount != null),
        );
    final double sum = known.fold<double>(
      0,
      (double total, NutrientContributor row) => total + row.amount!,
    );
    return DailyNutrientContributors._(
      date: DateTime(date.year, date.month, date.day),
      nutrient: nutrient,
      entries: logged,
      knownContributors: known,
      missingInformation: List<NutrientContributor>.unmodifiable(
        rows.where((NutrientContributor row) => row.gap != null),
      ),
      knownTotal: known.isNotEmpty && sum.isFinite ? sum : null,
      hasUnrecordedCoverage: rows.any(
        (NutrientContributor row) => row.coverage == MinorCoverage.notRecorded,
      ),
      hasSignedContributions: known.any(
        (NutrientContributor row) => row.amount! < 0,
      ),
    );
  }

  const DailyNutrientContributors._({
    required this.date,
    required this.nutrient,
    required this.entries,
    required this.knownContributors,
    required this.missingInformation,
    required this.knownTotal,
    required this.hasUnrecordedCoverage,
    required this.hasSignedContributions,
  });

  final DateTime date;
  final SupportedNutrient nutrient;
  final List<MealPlanEntry> entries;
  final List<NutrientContributor> knownContributors;

  /// Partial and legacy rows can appear here and in [knownContributors]. Their
  /// saved amount contributes only once; this list records the missing evidence.
  final List<NutrientContributor> missingInformation;

  /// Null when nothing stated a usable value, including an empty diary.
  final double? knownTotal;
  final bool hasUnrecordedCoverage;
  final bool hasSignedContributions;
  bool get isComplete => entries.isNotEmpty && missingInformation.isEmpty;

  /// A share of the saved known sum, never a share of a target. The UI must say
  /// "of known total" when [isComplete] is false. Legacy coverage cannot support
  /// that qualification, and signed or nonpositive totals have no useful share.
  double? percentageOf(NutrientContributor contributor) {
    final double? total = knownTotal;
    if (total == null ||
        total <= 0 ||
        hasUnrecordedCoverage ||
        hasSignedContributions ||
        !knownContributors.contains(contributor)) {
      return null;
    }
    return contributor.amount! / total * 100;
  }
}
