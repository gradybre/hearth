import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';

const Macros _all = Macros(
  kcal: 123.456,
  proteinG: 17.5,
  carbG: 21.5,
  fatG: 8.25,
  fiberG: 3.75,
  sodiumMg: 80.5,
  cholesterolMg: 6.25,
);

MealPlanEntry _entry({
  String id = 'saved',
  Macros macros = _all,
  NutrientCoverage coverage = const NutrientCoverage.allComplete(),
  bool logged = true,
  bool snapshot = true,
}) => MealPlanEntry(
  id: id,
  dayId: 'day',
  slot: MealSlot.lunch,
  refType: PlanRefType.recipe,
  refId: 'current-library-must-not-be-read',
  servings: 99,
  isLogged: logged,
  macroSnapshot: snapshot
      ? MacroSnapshot(
          macros: macros,
          servings: 0.5,
          label: 'Frozen meal name',
          capturedAt: DateTime(2026, 9, 30),
          coverage: coverage,
        )
      : null,
);

DailyNutrientContributors _project(
  List<MealPlanEntry> entries, {
  SupportedNutrient nutrient = SupportedNutrient.fiber,
}) => DailyNutrientContributors(
  date: DateTime(2026, 9, 30, 23, 59),
  nutrient: nutrient,
  entries: entries,
);

void main() {
  for (final (SupportedNutrient, double) nutrient
      in <(SupportedNutrient, double)>[
        (SupportedNutrient.calories, 123.456),
        (SupportedNutrient.protein, 17.5),
        (SupportedNutrient.carbs, 21.5),
        (SupportedNutrient.fat, 8.25),
        (SupportedNutrient.fiber, 3.75),
        (SupportedNutrient.sodium, 80.5),
        (SupportedNutrient.cholesterol, 6.25),
      ]) {
    test('${nutrient.$1.name} reads full precision saved portion only', () {
      final MealPlanEntry entry = _entry();
      final DailyNutrientContributors result = _project(<MealPlanEntry>[
        entry,
      ], nutrient: nutrient.$1);
      expect(result.knownTotal, nutrient.$2);
      expect(result.knownContributors.single.amount, nutrient.$2);
      expect(result.knownContributors.single.entry, same(entry));
      expect(result.percentageOf(result.knownContributors.single), 100);
      expect(result.isComplete, isTrue);
      expect(result.missingInformation, isEmpty);
    });
  }

  test('captures a calendar date and immutable logged-only lists', () {
    final List<MealPlanEntry> entries = <MealPlanEntry>[
      _entry(),
      _entry(id: 'planned', logged: false),
    ];
    final DailyNutrientContributors result = _project(entries);
    entries.clear();
    expect(result.date, DateTime(2026, 9, 30));
    expect(result.entries.map((MealPlanEntry entry) => entry.id), <String>[
      'saved',
    ]);
    expect(() => result.entries.clear(), throwsUnsupportedError);
    expect(() => result.knownContributors.clear(), throwsUnsupportedError);
    expect(() => result.missingInformation.clear(), throwsUnsupportedError);
  });

  test(
    'missing snapshot is missing evidence, never a live fallback or zero',
    () {
      final DailyNutrientContributors result = _project(<MealPlanEntry>[
        _entry(snapshot: false),
      ], nutrient: SupportedNutrient.calories);
      expect(result.entries, hasLength(1));
      expect(result.knownTotal, isNull);
      expect(result.knownContributors, isEmpty);
      expect(
        result.missingInformation.single.gap,
        NutrientInformationGap.snapshotUnavailable,
      );
    },
  );

  test('known zero is a contributor while unknown is not', () {
    final DailyNutrientContributors result = _project(<MealPlanEntry>[
      _entry(id: 'zero', macros: const Macros(fiberG: 0)),
      _entry(
        id: 'unknown',
        macros: const Macros(),
        coverage: const NutrientCoverage.allUnknown(),
      ),
    ]);
    expect(result.knownTotal, 0);
    expect(result.knownContributors.single.entry.id, 'zero');
    expect(result.knownContributors.single.amount, 0);
    expect(result.missingInformation.single.entry.id, 'unknown');
    expect(result.isComplete, isFalse);
    expect(result.percentageOf(result.knownContributors.single), isNull);
  });

  test('explicit unknown coverage does not count a placeholder number', () {
    final DailyNutrientContributors result = _project(<MealPlanEntry>[
      _entry(
        macros: const Macros(fiberG: 0),
        coverage: const NutrientCoverage.allUnknown(),
      ),
    ]);
    expect(result.knownTotal, isNull);
    expect(result.knownContributors, isEmpty);
    expect(
      result.missingInformation.single.gap,
      NutrientInformationGap.valueUnavailable,
    );
  });

  test('partial saved subtotal contributes once and identifies its gap', () {
    final DailyNutrientContributors result = _project(<MealPlanEntry>[
      _entry(id: 'complete', macros: const Macros(fiberG: 3)),
      _entry(
        id: 'partial',
        macros: const Macros(fiberG: 2),
        coverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
          MinorNutrient.fiber: MinorCoverage.partial,
        }),
      ),
      _entry(
        id: 'unknown',
        macros: const Macros(),
        coverage: const NutrientCoverage.allUnknown(),
      ),
    ]);
    expect(result.knownTotal, 5);
    expect(
      result.missingInformation.map((NutrientContributor row) => row.entry.id),
      <String>['partial', 'unknown'],
    );
    expect(result.knownContributors.last.gap, NutrientInformationGap.partial);
    expect(result.percentageOf(result.knownContributors.first), 60);
    expect(result.percentageOf(result.knownContributors.last), 40);
    expect(result.isComplete, isFalse);
  });

  test('legacy numeric evidence remains visible but cannot justify shares', () {
    final DailyNutrientContributors result = _project(<MealPlanEntry>[
      _entry(id: 'complete', macros: const Macros(fiberG: 3)),
      _entry(
        id: 'legacy',
        macros: const Macros(fiberG: 2),
        coverage: const NutrientCoverage.notRecorded(),
      ),
    ]);
    expect(result.knownTotal, 5);
    expect(result.knownContributors.last.amount, 2);
    expect(
      result.missingInformation.single.gap,
      NutrientInformationGap.coverageNotRecorded,
    );
    expect(result.hasUnrecordedCoverage, isTrue);
    for (final NutrientContributor row in result.knownContributors) {
      expect(result.percentageOf(row), isNull);
    }
  });

  test(
    'does not infer missing major-nutrient ingredients from minor coverage',
    () {
      final DailyNutrientContributors result = _project(<MealPlanEntry>[
        _entry(coverage: const NutrientCoverage.allUnknown()),
      ], nutrient: SupportedNutrient.protein);
      expect(result.knownTotal, 17.5);
      expect(result.missingInformation, isEmpty);
      expect(result.hasUnrecordedCoverage, isFalse);
    },
  );

  test('signed recipe amounts are retained and never presented as shares', () {
    final DailyNutrientContributors result = _project(<MealPlanEntry>[
      _entry(id: 'base', macros: const Macros(fiberG: 8)),
      _entry(id: 'deduction', macros: const Macros(fiberG: -2)),
    ]);
    expect(result.knownTotal, 6);
    expect(result.knownContributors.last.amount, -2);
    expect(result.hasSignedContributions, isTrue);
    expect(result.percentageOf(result.knownContributors.first), isNull);
    expect(result.percentageOf(result.knownContributors.last), isNull);
  });

  test('all-unknown and empty days do not claim recorded zero intake', () {
    final DailyNutrientContributors unknown = _project(<MealPlanEntry>[
      _entry(
        macros: const Macros(),
        coverage: const NutrientCoverage.allUnknown(),
      ),
    ]);
    final DailyNutrientContributors empty = _project(<MealPlanEntry>[]);
    expect(unknown.knownTotal, isNull);
    expect(unknown.missingInformation, hasLength(1));
    expect(empty.knownTotal, isNull);
    expect(empty.entries, isEmpty);
    expect(empty.missingInformation, isEmpty);
    expect(empty.isComplete, isFalse);
  });

  test('nonfinite values and overflowing totals never produce percentages', () {
    final DailyNutrientContributors invalid = _project(<MealPlanEntry>[
      _entry(macros: const Macros(fiberG: double.nan)),
    ]);
    expect(invalid.knownTotal, isNull);
    expect(
      invalid.missingInformation.single.gap,
      NutrientInformationGap.valueUnavailable,
    );
    final DailyNutrientContributors overflow = _project(<MealPlanEntry>[
      _entry(id: 'one', macros: const Macros(fiberG: 1e308)),
      _entry(id: 'two', macros: const Macros(fiberG: 1e308)),
    ]);
    expect(overflow.knownTotal, isNull);
    expect(overflow.knownContributors, hasLength(2));
    expect(overflow.percentageOf(overflow.knownContributors.first), isNull);
  });

  test('a contribution from another receipt is never given a share', () {
    final DailyNutrientContributors first = _project(<MealPlanEntry>[_entry()]);
    final DailyNutrientContributors second = _project(<MealPlanEntry>[
      _entry(id: 'other'),
    ]);
    expect(first.percentageOf(second.knownContributors.single), isNull);
  });
}
