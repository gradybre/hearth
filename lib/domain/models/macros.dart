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
  });

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  static const Macros zero = Macros();

  bool get isZero => kcal == 0 && proteinG == 0 && carbG == 0 && fatG == 0;

  Macros operator +(Macros other) => Macros(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbG: carbG + other.carbG,
    fatG: fatG + other.fatG,
  );

  Macros operator -(Macros other) => Macros(
    kcal: kcal - other.kcal,
    proteinG: proteinG - other.proteinG,
    carbG: carbG - other.carbG,
    fatG: fatG - other.fatG,
  );

  Macros scaledBy(num factor) {
    final double f = factor.toDouble();
    return Macros(
      kcal: kcal * f,
      proteinG: proteinG * f,
      carbG: carbG * f,
      fatG: fatG * f,
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
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbG, fatG);

  @override
  String toString() => 'Macros(${kcal}kcal P$proteinG C$carbG F$fatG)';
}

/// Which of the four macros a UI element is talking about.
///
/// Calories are the primary focus, the other three secondary (spec §5.6).
enum MacroKind { calories, protein, carbs, fat }
