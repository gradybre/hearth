import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:test/test.dart';

/// Where the three minor nutrients stand against their targets (spec §5.6).
///
/// The distinction the whole thing turns on: **fibre is a floor and the other
/// two are ceilings.** Reaching 28 g of fibre is an achievement; reaching
/// 2,300 mg of sodium is the thing you were trying not to do. A screen that
/// treated them alike would be wrong about two of the three.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  DayProgress dayOf(Macros consumed) =>
      DayProgress.from(consumed: consumed, targets: targets);

  group('which target it measures against', () {
    test('the Daily Value, when nobody has set one', () {
      final MinorProgress fibre = dayOf(const Macros(fiberG: 14))
          .minor(MinorNutrient.fiber)!;

      expect(fibre.target, 28);
      expect(fibre.fraction, closeTo(0.5, 1e-9));
    });

    test('and the household\'s own, when they have', () {
      final DayProgress day = DayProgress.from(
        consumed: const Macros(fiberG: 14),
        targets: const MacroTargets(
          kcal: 2000,
          proteinG: 150,
          carbG: 200,
          fatG: 70,
          fiberG: 40,
        ),
      );

      expect(day.minor(MinorNutrient.fiber)!.target, 40);
    });
  });

  group('a nutrient nobody knows about', () {
    test('has no progress at all, rather than progress of zero', () {
      // A bar reading "0 of 28 g" would say the day had no fibre. The truth
      // is that nothing logged has ever been asked, and those are different
      // claims (spec §5.6).
      expect(dayOf(const Macros(kcal: 500)).minor(MinorNutrient.fiber), isNull);
      expect(dayOf(const Macros(kcal: 500)).knownMinor, isEmpty);
    });

    test('while a stated zero is a real number and does show', () {
      final MinorProgress sodium = dayOf(const Macros(sodiumMg: 0))
          .minor(MinorNutrient.sodium)!;

      expect(sodium.consumed, 0);
      expect(sodium.state, MacroProgressState.under);
    });

    test('and only the known ones are offered for display', () {
      expect(
        dayOf(const Macros(fiberG: 10, sodiumMg: 500)).knownMinor
            .map((MinorProgress p) => p.nutrient),
        <MinorNutrient>[MinorNutrient.fiber, MinorNutrient.sodium],
      );
    });
  });

  group('fibre is a floor', () {
    test('most of the way there is neutral, not a warning', () {
      expect(
        dayOf(const Macros(fiberG: 14)).minor(MinorNutrient.fiber)!.tone,
        MacroTone.neutral,
      );
    });

    test('and reaching it is good, not over', () {
      final MinorProgress fibre = dayOf(const Macros(fiberG: 30))
          .minor(MinorNutrient.fiber)!;

      expect(fibre.state, MacroProgressState.over);
      // The arithmetic says over; the judgement says well done. Same split the
      // four macros already make for protein.
      expect(fibre.tone, MacroTone.good);
    });
  });

  group('sodium and cholesterol are ceilings', () {
    test('nearly spent is still neutral, not an achievement', () {
      // The rule inherited from MacroProgress says 90% of a target is good,
      // which is true of calories — a number you are trying to hit — and
      // false of sodium, which is a number you are trying to avoid. Being at
      // 2,200 of 2,300 mg is not doing well; it is nearly over.
      expect(
        dayOf(const Macros(sodiumMg: 2200)).minor(MinorNutrient.sodium)!.tone,
        MacroTone.neutral,
      );
    });

    test('under budget reads neutral', () {
      expect(
        dayOf(const Macros(sodiumMg: 900)).minor(MinorNutrient.sodium)!.tone,
        MacroTone.neutral,
      );
    });

    test('and past it reads over, unlike fibre at the same fraction', () {
      final MinorProgress sodium = dayOf(const Macros(sodiumMg: 2600))
          .minor(MinorNutrient.sodium)!;
      final MinorProgress cholesterol = dayOf(const Macros(cholesterolMg: 340))
          .minor(MinorNutrient.cholesterol)!;

      expect(sodium.tone, MacroTone.over);
      expect(cholesterol.tone, MacroTone.over);
    });

    test('what is left of a budget is what is left to spend', () {
      final MinorProgress sodium = dayOf(const Macros(sodiumMg: 1800))
          .minor(MinorNutrient.sodium)!;

      expect(sodium.remaining, 500);
      expect(sodium.barFill, closeTo(1800 / 2300, 1e-9));
    });
  });

  test('a bar never overfills, however far past the target', () {
    expect(
      dayOf(const Macros(sodiumMg: 9000)).minor(MinorNutrient.sodium)!.barFill,
      1,
    );
  });
}
