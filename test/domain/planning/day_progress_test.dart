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
