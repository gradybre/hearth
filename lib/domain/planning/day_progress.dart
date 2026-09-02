import 'package:meta/meta.dart';

import '../models/macros.dart';

/// A day's macro targets, set per week (spec §5.6).
@immutable
class MacroTargets {
  const MacroTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
  });

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  double forKind(MacroKind kind) => switch (kind) {
    MacroKind.calories => kcal,
    MacroKind.protein => proteinG,
    MacroKind.carbs => carbG,
    MacroKind.fat => fatG,
  };

  @override
  bool operator ==(Object other) =>
      other is MacroTargets &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbG == carbG &&
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbG, fatG);
}

/// Where one macro stands against its target.
///
/// The UI must convey this with an icon or label as well as colour — never
/// colour alone (spec §6.3).
enum MacroProgressState { under, met, over }

/// Whether a macro is somewhere worth being (spec §5.6, §6.3).
///
/// Deliberately separate from [MacroProgressState], which says only where a
/// number sits relative to its target. Position and desirability are not the
/// same question, and conflating them gets protein exactly backwards: passing
/// a protein target is the object of the exercise, and a screen that turned
/// red at the moment you succeeded would be worse than one with no colour at
/// all.
enum MacroTone {
  /// Still working towards it. The ordinary state for most of a day.
  neutral,

  /// Where you want to be — near the target, or past it on a macro that has
  /// no ceiling.
  good,

  /// Past a target that was a ceiling.
  over,
}

/// One macro's progress for a day.
@immutable
class MacroProgress {
  const MacroProgress({
    required this.kind,
    required this.consumed,
    required this.target,
    required this.state,
  });

  final MacroKind kind;
  final double consumed;
  final double target;
  final MacroProgressState state;

  /// What's left for the day. Negative once the target is passed, which is how
  /// the "142 g protein left" readout gets its over/under sign (spec §5.6).
  double get remaining => target - consumed;

  /// How far into the target, unclamped: 1.2 means 20% over.
  double get fraction => target > 0 ? consumed / target : 0;

  /// Progress-bar fill, clamped to the bar's length. Use [fraction] and
  /// [state] to say anything about overshoot — a full bar alone can't.
  double get barFill => fraction.clamp(0.0, 1.0).toDouble();

  bool get isOver => state == MacroProgressState.over;

  /// Macros you are trying to *reach* rather than stay under.
  ///
  /// Protein is the one Hearth tracks: the target is a floor, so there is no
  /// amount of it that counts as having gone wrong. Calories, carbs and fat
  /// are ceilings.
  static const Set<MacroKind> floors = <MacroKind>{MacroKind.protein};

  /// The share of a target at which a macro starts reading as good.
  ///
  /// Not 100%: landing exactly on a target is luck, and a day that only turns
  /// encouraging at the last mouthful is encouraging nobody. Ninety per cent
  /// is close enough to be finished with.
  static const double goodFrom = 0.9;

  /// How this number should read, as against merely where it sits.
  ///
  /// [MacroProgressState] does the arithmetic; this does the judgement, and
  /// the two differ on protein — see [MacroTone].
  MacroTone get tone {
    if (target <= 0 || fraction < goodFrom) return MacroTone.neutral;
    if (floors.contains(kind)) return MacroTone.good;
    return state == MacroProgressState.over ? MacroTone.over : MacroTone.good;
  }
}

/// A day's totals against its targets (spec §5.6).
///
/// Calories are the primary focus; protein, carbs, and fat are secondary.
@immutable
class DayProgress {
  const DayProgress({
    required this.consumed,
    required this.targets,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  /// Builds a day's progress from what's been eaten and the day's targets.
  ///
  /// [tolerance] is the fraction of a target within which the day counts as
  /// met rather than under or over — 0.02 treats 2% either side as on target.
  /// It defaults to exact, so a caller has to opt into fuzziness.
  factory DayProgress.from({
    required Macros consumed,
    required MacroTargets targets,
    double tolerance = 0,
  }) => DayProgress(
    consumed: consumed,
    targets: targets,
    calories: _progress(
      MacroKind.calories,
      consumed.kcal,
      targets.kcal,
      tolerance,
    ),
    protein: _progress(
      MacroKind.protein,
      consumed.proteinG,
      targets.proteinG,
      tolerance,
    ),
    carbs: _progress(MacroKind.carbs, consumed.carbG, targets.carbG, tolerance),
    fat: _progress(MacroKind.fat, consumed.fatG, targets.fatG, tolerance),
  );

  final Macros consumed;
  final MacroTargets targets;

  final MacroProgress calories;
  final MacroProgress protein;
  final MacroProgress carbs;
  final MacroProgress fat;

  /// All four, calories first — the display order (spec §5.6).
  List<MacroProgress> get all => <MacroProgress>[calories, protein, carbs, fat];

  MacroProgress forKind(MacroKind kind) => switch (kind) {
    MacroKind.calories => calories,
    MacroKind.protein => protein,
    MacroKind.carbs => carbs,
    MacroKind.fat => fat,
  };

  static MacroProgress _progress(
    MacroKind kind,
    double consumed,
    double target,
    double tolerance,
  ) {
    final double band = (target * tolerance).abs();
    final MacroProgressState state;
    if (target <= 0) {
      // No target set for this macro: report the number, claim nothing.
      state = MacroProgressState.under;
    } else if (consumed > target + band) {
      state = MacroProgressState.over;
    } else if (consumed >= target - band) {
      state = MacroProgressState.met;
    } else {
      state = MacroProgressState.under;
    }
    return MacroProgress(
      kind: kind,
      consumed: consumed,
      target: target,
      state: state,
    );
  }
}
