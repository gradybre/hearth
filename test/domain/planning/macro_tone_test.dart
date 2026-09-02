import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:test/test.dart';

/// Whether a macro is somewhere worth being (spec §5.6).
///
/// Separate from where the number sits, because on protein those two answers
/// disagree: the target is a floor, and passing it is the object of the
/// exercise rather than a mistake.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 100,
    carbG: 200,
    fatG: 60,
  );

  DayProgress at({
    double kcal = 0,
    double proteinG = 0,
    double carbG = 0,
    double fatG = 0,
  }) => DayProgress.from(
    consumed: Macros(kcal: kcal, proteinG: proteinG, carbG: carbG, fatG: fatG),
    targets: targets,
  );

  group('a ceiling macro', () {
    test('is neutral while there is still room', () {
      expect(at(kcal: 1000).calories.tone, MacroTone.neutral);
      expect(at(kcal: 1799).calories.tone, MacroTone.neutral);
    });

    test('reads good from nine tenths of the way', () {
      // Landing exactly on a target is luck. A day that only turns
      // encouraging at the last mouthful encourages nobody.
      expect(at(kcal: 1800).calories.tone, MacroTone.good);
      expect(at(kcal: 2000).calories.tone, MacroTone.good);
    });

    test('and over once it is past', () {
      expect(at(kcal: 2001).calories.tone, MacroTone.over);
      expect(at(carbG: 260).carbs.tone, MacroTone.over);
      expect(at(fatG: 80).fat.tone, MacroTone.over);
    });
  });

  group('protein is a floor, not a ceiling', () {
    test('it reads good at nine tenths, like the rest', () {
      expect(at(proteinG: 89).protein.tone, MacroTone.neutral);
      expect(at(proteinG: 90).protein.tone, MacroTone.good);
    });

    test('and stays good however far past it you get', () {
      // The whole reason tone is not MacroProgressState: this is the case
      // where "over" and "wrong" come apart. A screen that turned red at the
      // moment you hit your protein goal would be worse than no colour.
      expect(at(proteinG: 150).protein.tone, MacroTone.good);
      expect(at(proteinG: 400).protein.tone, MacroTone.good);
      // The position is still reported honestly — only the judgement differs.
      expect(at(proteinG: 150).protein.state, MacroProgressState.over);
    });
  });

  test('a target of zero claims nothing', () {
    // No target set is not the same as a target met, and colour must not
    // imply otherwise.
    const MacroTargets none = MacroTargets(
      kcal: 0,
      proteinG: 0,
      carbG: 0,
      fatG: 0,
    );
    final DayProgress progress = DayProgress.from(
      consumed: const Macros(kcal: 500, proteinG: 40),
      targets: none,
    );

    expect(progress.calories.tone, MacroTone.neutral);
    expect(progress.protein.tone, MacroTone.neutral);
  });
}
