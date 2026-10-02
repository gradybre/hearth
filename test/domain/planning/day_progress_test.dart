import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:test/test.dart';

void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2200,
    proteinG: 180,
    carbG: 220,
    fatG: 70,
  );

  test(
    'intake without targets retains known, unknown and partial nutrients',
    () {
      final DayProgress day = DayProgress.fromParts(
        parts: const <Macros>[
          Macros(kcal: 400, proteinG: 20, fiberG: 4),
          Macros(kcal: 100),
        ],
      );
      expect(day.consumed.kcal, 500);
      expect(day.calories.hasTarget, isFalse);
      expect(day.calories.tone, MacroTone.neutral);
      expect(day.minor(MinorNutrient.fiber).consumed, 4);
      expect(day.minor(MinorNutrient.fiber).isPartial, isTrue);
      expect(day.minor(MinorNutrient.fiber).hasTarget, isFalse);
      expect(day.minor(MinorNutrient.sodium).isKnown, isFalse);
      expect(day.countedParts, 2);
    },
  );
  test('a logged zero and an empty day remain different', () {
    final DayProgress empty = DayProgress.fromParts(parts: const <Macros>[]);
    final DayProgress zero = DayProgress.fromParts(
      parts: const <Macros>[Macros.zero],
    );
    expect(empty.consumed.kcal, zero.consumed.kcal);
    expect(empty.countedParts, 0);
    expect(zero.countedParts, 1);
  });

  group('missing saved nutrition', () {
    test('an absent-only day has no intake or target verdict', () {
      final DayProgress day = DayProgress.fromParts(
        parts: const <Macros>[Macros.zero],
        missingSnapshotCount: 1,
        targets: targets,
      );
      expect(day.countedParts, 1);
      expect(day.availability, SavedNutritionAvailability.unavailable);
      for (final MacroProgress macro in day.all) {
        expect(macro.hasKnownIntake, isFalse);
        expect(macro.canCompare, isFalse);
        expect(macro.remaining, isNull);
        expect(macro.tone, MacroTone.neutral);
        expect(macro.isOver, isFalse);
      }
      for (final MinorProgress minor in day.allMinor) {
        expect(minor.isKnown, isFalse);
        expect(minor.canCompare, isFalse);
        expect(minor.remaining, isNull);
      }
    });

    test(
      'a mixed day preserves its known subtotal without a complete judgment',
      () {
        final DayProgress day = DayProgress.fromParts(
          parts: const <Macros>[
            Macros(kcal: 2300, proteinG: 180, fiberG: 28, sodiumMg: 2400),
            Macros.zero,
          ],
          missingSnapshotCount: 1,
          targets: targets,
        );
        expect(day.availability, SavedNutritionAvailability.partial);
        expect(day.consumed.kcal, 2300);
        for (final MacroProgress macro in day.all) {
          expect(macro.hasKnownIntake, isTrue);
          expect(macro.canCompare, isFalse);
          expect(macro.remaining, isNull);
          expect(macro.tone, MacroTone.neutral);
        }
        expect(day.minor(MinorNutrient.fiber).consumed, 28);
        expect(day.minor(MinorNutrient.sodium).consumed, 2400);
        for (final MinorProgress minor in day.allMinor) {
          expect(minor.canCompare, isFalse);
          expect(minor.remaining, isNull);
          expect(minor.tone, MacroTone.neutral);
        }
      },
    );

    test('a real zero remains known beside unavailable history', () {
      final DayProgress day = DayProgress.fromParts(
        parts: const <Macros>[Macros.zero, Macros.zero],
        missingSnapshotCount: 1,
      );
      expect(day.availability, SavedNutritionAvailability.partial);
      expect(day.calories.hasKnownIntake, isTrue);
      expect(day.calories.consumed, 0);
    });
  });

  group('remaining for the day (spec §5.6)', () {
    test('reports what is left', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(kcal: 1400, proteinG: 38, carbG: 150, fatG: 40),
        targets: targets,
      );
      // The readout the spec names: "142 g protein left".
      expect(day.protein.remaining, 142);
      expect(day.calories.remaining, 800);
    });

    test('goes negative once the target is passed', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(kcal: 2500),
        targets: targets,
      );
      expect(day.calories.remaining, -300);
      expect(day.calories.isOver, isTrue);
    });
  });

  group('over / under state', () {
    test('under, met, and over are distinguished exactly by default', () {
      MacroProgressState stateFor(double kcal) => DayProgress.from(
        consumed: Macros(kcal: kcal),
        targets: targets,
      ).calories.state;

      expect(stateFor(2199), MacroProgressState.under);
      expect(stateFor(2200), MacroProgressState.met);
      expect(stateFor(2201), MacroProgressState.over);
    });

    test('a tolerance widens the met band on both sides', () {
      MacroProgressState stateFor(double kcal) => DayProgress.from(
        consumed: Macros(kcal: kcal),
        targets: targets,
        tolerance: 0.02,
      ).calories.state;

      expect(stateFor(2170), MacroProgressState.met);
      expect(stateFor(2240), MacroProgressState.met);
      expect(stateFor(2100), MacroProgressState.under);
      expect(stateFor(2300), MacroProgressState.over);
    });

    test('a macro with no target claims nothing', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(kcal: 500),
        targets: const MacroTargets(kcal: 0, proteinG: 0, carbG: 0, fatG: 0),
      );
      expect(day.calories.state, MacroProgressState.under);
      expect(day.calories.fraction, 0);
    });
  });

  group('progress bars', () {
    test('fraction is unclamped so overshoot stays visible in the data', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(kcal: 2640),
        targets: targets,
      );
      expect(day.calories.fraction, closeTo(1.2, 1e-9));
      expect(day.calories.barFill, 1.0);
    });

    test('bar fill tracks the fraction below the target', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(kcal: 1100),
        targets: targets,
      );
      expect(day.calories.barFill, closeTo(0.5, 1e-9));
    });
  });

  test('calories come first in display order (spec §5.6)', () {
    final DayProgress day = DayProgress.from(
      consumed: const Macros(kcal: 100),
      targets: targets,
    );
    expect(day.all.first.kind, MacroKind.calories);
    expect(day.all.map((MacroProgress p) => p.kind), <MacroKind>[
      MacroKind.calories,
      MacroKind.protein,
      MacroKind.carbs,
      MacroKind.fat,
    ]);
  });

  test('forKind matches the named getters', () {
    final DayProgress day = DayProgress.from(
      consumed: const Macros(kcal: 100, proteinG: 20),
      targets: targets,
    );
    expect(day.forKind(MacroKind.protein).consumed, 20);
    expect(day.forKind(MacroKind.protein), day.protein);
  });
}
