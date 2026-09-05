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
    this.fiberG,
    this.sodiumMg,
    this.cholesterolMg,
  });

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// The three minor nutrients, **null meaning "use the Daily Value"** rather
  /// than "no target" (spec §5.6).
  ///
  /// Nullable and not required, so a week whose targets were set before these
  /// existed still reads — and so the ordinary case is not four more numbers
  /// to type before the screen works.
  final double? fiberG;
  final double? sodiumMg;
  final double? cholesterolMg;

  double forKind(MacroKind kind) => switch (kind) {
    MacroKind.calories => kcal,
    MacroKind.protein => proteinG,
    MacroKind.carbs => carbG,
    MacroKind.fat => fatG,
  };

  /// This household's target for [nutrient], or the Daily Value.
  double forNutrient(MinorNutrient nutrient) =>
      switch (nutrient) {
        MinorNutrient.fiber => fiberG,
        MinorNutrient.sodium => sodiumMg,
        MinorNutrient.cholesterol => cholesterolMg,
      } ??
      nutrient.dailyValue;

  /// Whether [nutrient] is measured against a number somebody chose.
  bool hasOwnTarget(MinorNutrient nutrient) =>
      switch (nutrient) {
        MinorNutrient.fiber => fiberG,
        MinorNutrient.sodium => sodiumMg,
        MinorNutrient.cholesterol => cholesterolMg,
      } !=
      null;

  @override
  bool operator ==(Object other) =>
      other is MacroTargets &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbG == carbG &&
      other.fatG == fatG &&
      other.fiberG == fiberG &&
      other.sodiumMg == sodiumMg &&
      other.cholesterolMg == cholesterolMg;

  @override
  int get hashCode =>
      Object.hash(kcal, proteinG, carbG, fatG, fiberG, sodiumMg, cholesterolMg);
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

/// One minor nutrient's progress for a day (spec §5.6).
///
/// Deliberately its own type rather than a [MacroProgress] with a different
/// enum on it. The four macros are always known; these three often are not,
/// and [consumed] is nullable precisely so that "nobody asked" can never be
/// rendered as "none". All three are shown either way — hiding an unknown one
/// made the whole feature invisible, because an absent row and a feature that
/// was never built look the same.
@immutable
class MinorProgress {
  const MinorProgress({
    required this.nutrient,
    required this.consumed,
    required this.target,
    required this.state,
    this.unknownCount = 0,
    this.countedParts = 0,
  });

  final MinorNutrient nutrient;

  /// **Null when nothing that counted has stated a value.**
  ///
  /// Not zero, and the difference is the whole of §5.6: a bar reading "0 of
  /// 28 g" claims the day had no fibre, when the truth is that nothing eaten
  /// has ever been asked. Those are different statements and only one of them
  /// is true.
  final double? consumed;

  final double target;
  final MacroProgressState state;

  /// How many of the things that counted said nothing about this nutrient.
  ///
  /// A running total is only as good as its coverage, and a partial one looks
  /// exactly like a whole one on screen — which is how "12 g of fibre" from
  /// two foods out of six becomes a number somebody trusts.
  final int unknownCount;

  /// How many things counted towards the day at all.
  ///
  /// Zero means nothing has been logged yet, which is a different silence
  /// from "six foods were asked and none of them knew" — and saying the wrong
  /// one of those is how a row stops being read.
  final int countedParts;

  bool get isKnown => consumed != null;

  /// What is left. For fibre that is what remains to get; for sodium and
  /// cholesterol it is what remains to spend.
  ///
  /// **Null when nothing has said**, rather than the whole target. "2,300 mg
  /// left" on a day nobody asked about sodium is a number this cannot know,
  /// and returning one would be a `?? 0` wearing a different hat.
  double? get remaining => consumed == null ? null : target - consumed!;

  double get fraction =>
      target > 0 && consumed != null ? consumed! / target : 0;

  double get barFill => fraction.clamp(0.0, 1.0).toDouble();

  bool get isOver => state == MacroProgressState.over;

  /// How this number should read, as against merely where it sits.
  ///
  /// [MinorNutrient.isFloor] decides which of two rules applies, and they are
  /// genuinely different rules rather than one with a sign flipped:
  ///
  ///  * A **floor** is a number to reach. Most of the way there is neutral,
  ///    nearly there is good, and past it is still good — the same shape
  ///    [MacroProgress.tone] gives protein.
  ///  * A **ceiling** is a number to avoid. It is neutral all the way up and
  ///    over once passed, with no good in between.
  ///
  /// That last part is why this is not [MacroProgress.tone] with a different
  /// enum. There, 90% of a calorie target is good, because calories are a
  /// number you are trying to hit. Sodium is a number you are trying not to
  /// hit, and 2,200 of a 2,300 mg budget is not doing well — it is nearly
  /// over, and colouring it as an achievement would encourage exactly the
  /// thing the budget exists to discourage.
  MacroTone get tone {
    // Nothing has said, so there is nothing to say about it either.
    if (target <= 0 || consumed == null) return MacroTone.neutral;
    if (!nutrient.isFloor) {
      return state == MacroProgressState.over
          ? MacroTone.over
          : MacroTone.neutral;
    }
    return fraction < MacroProgress.goodFrom
        ? MacroTone.neutral
        : MacroTone.good;
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
    this.unknownCounts = const <MinorNutrient, int>{},
    this.countedParts = 0,
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
    Map<MinorNutrient, int> unknownCounts = const <MinorNutrient, int>{},
    int countedParts = 0,
  }) => DayProgress(
    unknownCounts: unknownCounts,
    countedParts: countedParts,
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

  /// The same, from the parts rather than the total, so each bar can say how
  /// much of the day it actually covers.
  ///
  /// A running total looks the same whether it came from everything eaten or
  /// from one food out of six, and only one of those is worth reading.
  factory DayProgress.fromParts({
    required Iterable<Macros> parts,
    required MacroTargets targets,
    double tolerance = 0,
  }) {
    final List<Macros> all = parts.toList(growable: false);
    return DayProgress.from(
      consumed: Macros.sum(all),
      targets: targets,
      tolerance: tolerance,
      countedParts: all.length,
      unknownCounts: <MinorNutrient, int>{
        for (final MinorNutrient nutrient in MinorNutrient.values)
          nutrient: all
              .where((Macros macros) => !macros.knows(nutrient))
              .length,
      },
    );
  }

  final Macros consumed;
  final MacroTargets targets;

  /// How many of the contributing parts said nothing about each nutrient.
  ///
  /// Empty when the day was built from a total rather than from its parts, in
  /// which case a bar reports what it knows and claims nothing about coverage.
  final Map<MinorNutrient, int> unknownCounts;

  /// How many things counted towards the day, or zero when it was built from
  /// a total. Distinguishes "nothing logged" from "nothing knew".
  final int countedParts;

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

  /// Where [nutrient] stands. Its `consumed` is **null when nothing that
  /// counted has stated a value** — which is not the same as none (spec §5.6).
  MinorProgress minor(MinorNutrient nutrient) {
    final double? eaten = consumed.minor(nutrient);
    final double target = targets.forNutrient(nutrient);
    final MacroProgressState state;
    if (eaten == null || target <= 0) {
      state = MacroProgressState.under;
    } else if (eaten > target) {
      state = MacroProgressState.over;
    } else if (eaten == target) {
      state = MacroProgressState.met;
    } else {
      state = MacroProgressState.under;
    }

    return MinorProgress(
      nutrient: nutrient,
      consumed: eaten,
      target: target,
      state: state,
      unknownCount: unknownCounts[nutrient] ?? 0,
      countedParts: countedParts,
    );
  }

  /// All three, in their declared order, whether or not anything knows them.
  ///
  /// They are shown even on a day where nothing has stated a value, saying so
  /// rather than vanishing. An absent row and an unbuilt feature look
  /// identical from the sofa, and for a household whose foods predate these
  /// columns "nothing has said" is the ordinary answer — which made the whole
  /// thing invisible.
  List<MinorProgress> get allMinor => <MinorProgress>[
    for (final MinorNutrient nutrient in MinorNutrient.values) minor(nutrient),
  ];

  /// The ones something actually knows.
  List<MinorProgress> get knownMinor => <MinorProgress>[
    for (final MinorProgress progress in allMinor)
      if (progress.isKnown) progress,
  ];

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
