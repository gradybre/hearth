import 'package:meta/meta.dart';

/// The four tracked macros (spec §5.6): calories, protein, carbohydrate, fat,
/// plus three optional minor nutrients.
///
/// The four are always known and default to zero. Fibre, sodium and
/// cholesterol are **nullable, and null means unknown** — a food with no fibre
/// data is not a food with no fibre. Everything below that treats them
/// differently from the four follows from that one distinction, and a careless
/// `?? 0` anywhere in a mapper turns a missing number into a wrong one.
///
/// Micronutrients beyond these, and sugar, remain out of scope (spec §12) — do
/// not add fields here without that decision changing. The three that are here
/// were lifted from §12 deliberately and the spec was amended to say so.
///
/// Values are full precision. Rounding is a display concern and happens in the
/// format layer, never here (spec §4).
@immutable
class Macros {
  const Macros({
    this.kcal = 0,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.fiberG,
    this.sodiumMg,
    this.cholesterolMg,
  });

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// Grams of dietary fibre, or null when the source did not say.
  final double? fiberG;

  /// **Milligrams** of sodium, or null. Open Food Facts reports sodium in
  /// grams per 100 g and a nutrition label prints milligrams; the adapters
  /// convert, and nothing here will fail loudly if one of them forgets — hence
  /// the unit in the name.
  final double? sodiumMg;

  /// **Milligrams** of cholesterol, or null.
  final double? cholesterolMg;

  static const Macros zero = Macros();

  /// Whether the four tracked macros are all zero.
  ///
  /// Deliberately says nothing about the minor three: a food is not made
  /// non-zero by knowing its sodium, and `isZero` is what decides whether a
  /// food has usable nutrition at all.
  bool get isZero => kcal == 0 && proteinG == 0 && carbG == 0 && fatG == 0;

  /// Whether any column has gone under zero — a total that is not a meal.
  ///
  /// Deductions are real (spec §5.2): a modifier the chain publishes, and an
  /// ordinary component somebody asked them to leave off. Neither may take a
  /// total below nothing, and two places have to ask that question — the
  /// eat-out builder before it assembles a meal, and the macro calculator
  /// before one is logged. One predicate rather than two copies, because two
  /// copies drift and then the screens disagree about the same meal.
  ///
  /// All seven columns, not just the calories: a deduction can leave the
  /// calories standing while the carbohydrate goes under. Null is "nobody
  /// said" rather than a number below zero, so an unknown is not a breach.
  bool get isBelowNothing =>
      kcal < 0 ||
      proteinG < 0 ||
      carbG < 0 ||
      fatG < 0 ||
      (fiberG ?? 0) < 0 ||
      (sodiumMg ?? 0) < 0 ||
      (cholesterolMg ?? 0) < 0;

  /// This macros' value for [nutrient], in that nutrient's own unit.
  double? minor(MinorNutrient nutrient) => switch (nutrient) {
    MinorNutrient.fiber => fiberG,
    MinorNutrient.sodium => sodiumMg,
    MinorNutrient.cholesterol => cholesterolMg,
  };

  /// Whether anything is known about [nutrient] here.
  bool knows(MinorNutrient nutrient) => minor(nutrient) != null;

  /// Whether there is any minor nutrient worth showing at all.
  bool get knowsAnyMinor => MinorNutrient.values.any(knows);

  /// Adds two values where **either** side knows one.
  ///
  /// Null only when neither did. The alternative — one unmatched ingredient
  /// poisoning a whole recipe's fibre to null — would leave these blank
  /// essentially always, which is the same as not having them. §4's standing
  /// rule is that incomplete data flags rather than blocks, and a partial
  /// total that says it is partial is the useful shape of that here.
  static double? _add(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0) + (b ?? 0);
  }

  static double? _subtract(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0) - (b ?? 0);
  }

  Macros operator +(Macros other) => Macros(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbG: carbG + other.carbG,
    fatG: fatG + other.fatG,
    fiberG: _add(fiberG, other.fiberG),
    sodiumMg: _add(sodiumMg, other.sodiumMg),
    cholesterolMg: _add(cholesterolMg, other.cholesterolMg),
  );

  Macros operator -(Macros other) => Macros(
    kcal: kcal - other.kcal,
    proteinG: proteinG - other.proteinG,
    carbG: carbG - other.carbG,
    fatG: fatG - other.fatG,
    fiberG: _subtract(fiberG, other.fiberG),
    sodiumMg: _subtract(sodiumMg, other.sodiumMg),
    cholesterolMg: _subtract(cholesterolMg, other.cholesterolMg),
  );

  Macros scaledBy(num factor) {
    final double f = factor.toDouble();
    // Half of "we do not know" is still "we do not know" — and so is zero
    // times it. Scaling a portion to nothing must not invent a number.
    double? scale(double? value) => value == null ? null : value * f;
    return Macros(
      kcal: kcal * f,
      proteinG: proteinG * f,
      carbG: carbG * f,
      fatG: fatG * f,
      fiberG: scale(fiberG),
      sodiumMg: scale(sodiumMg),
      cholesterolMg: scale(cholesterolMg),
    );
  }

  /// Sums a collection. Used for recipe totals and daily logs.
  static Macros sum(Iterable<Macros> parts) =>
      parts.fold(zero, (Macros a, Macros b) => a + b);

  @override
  bool operator ==(Object other) =>
      other is Macros &&
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

  @override
  String toString() => 'Macros(${kcal}kcal P$proteinG C$carbG F$fatG)';
}

/// Which of the four macros a UI element is talking about.
///
/// Calories are the primary focus, the other three secondary (spec §5.6).
enum MacroKind { calories, protein, carbs, fat }

/// The three optional nutrients carried alongside the four macros (spec §5.6).
///
/// Deliberately **not** members of [MacroKind]. That enum drives progress
/// against `macro_target`, and these have no targets: they are shown where
/// known and absent where not, never a bar to fill.
enum MinorNutrient {
  fiber('Fibre', 'g'),
  sodium('Sodium', 'mg'),
  cholesterol('Cholesterol', 'mg');

  const MinorNutrient(this.label, this.unit);

  /// What the nutrient is called on screen.
  final String label;

  /// The unit it is stored and displayed in — grams for fibre, milligrams for
  /// the other two. Shown always, because "200 sodium" means nothing.
  final String unit;

  /// Whether the target is a floor to reach rather than a ceiling to stay
  /// under (spec §5.6).
  ///
  /// The three do not point the same way, and a screen that treated them
  /// alike would be wrong about two of them. Fibre is something to get to —
  /// 28 g is an achievement. Sodium and cholesterol are budgets, and passing
  /// one is the thing you were trying not to do. Same distinction the four
  /// macros already make between protein and the rest.
  bool get isFloor => this == MinorNutrient.fiber;

  /// What the Daily Value is, when nobody has set a target of their own.
  ///
  /// The FDA's, for a 2,000-calorie diet. Defaults rather than requirements:
  /// a number to measure against beats no number, and "612 mg sodium" means
  /// nothing until it sits next to 2,300.
  double get dailyValue => switch (this) {
    MinorNutrient.fiber => 28,
    MinorNutrient.sodium => 2300,
    MinorNutrient.cholesterol => 300,
  };
}
