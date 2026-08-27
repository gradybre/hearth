import 'package:meta/meta.dart';

import 'unit.dart';

/// An amount of something, stored canonically.
///
/// Spec §4: quantities are stored in one canonical unit (ml / g / items) and
/// converted at display time, so two users with different imperial/metric
/// preferences render the same stored row. [preferredUnit] records the unit the
/// value was *authored* in so a recipe that was written as "1 cup" reads back
/// as "1 cup" rather than "237 ml" for an imperial user.
@immutable
class Quantity implements Comparable<Quantity> {
  const Quantity.canonical({
    required this.canonicalAmount,
    required this.kind,
    this.preferredUnit,
  });

  /// Builds a quantity from an amount expressed in [unit].
  factory Quantity.of(num amount, Unit unit) => Quantity.canonical(
    canonicalAmount: amount.toDouble() * unit.toCanonical,
    kind: unit.kind,
    preferredUnit: unit,
  );

  /// Amount in the canonical unit for [kind]: ml, g, or items.
  final double canonicalAmount;

  final UnitKind kind;

  /// The unit this quantity was authored in, if any. A display hint only —
  /// never the source of truth for the value.
  final Unit? preferredUnit;

  bool get isZero => canonicalAmount == 0;

  /// This amount expressed in [unit].
  ///
  /// Throws [ArgumentError] when [unit] measures a different [UnitKind];
  /// crossing volume and mass needs a density, so it goes through
  /// `UnitConverter.crossKind` instead.
  double amountIn(Unit unit) {
    if (unit.kind != kind) {
      throw ArgumentError(
        'Cannot express a ${kind.name} quantity in ${unit.id} '
        '(${unit.kind.name}) without a density.',
      );
    }
    return canonicalAmount / unit.toCanonical;
  }

  /// Multiplies the amount. Used by recipe scaling; never rounds.
  Quantity scaledBy(num factor) => Quantity.canonical(
    canonicalAmount: canonicalAmount * factor.toDouble(),
    kind: kind,
    preferredUnit: preferredUnit,
  );

  /// Adds a same-kind quantity. Used by shopping-list aggregation.
  ///
  /// Keeps the left operand's [preferredUnit] so "2 tbsp + 50 ml" still reads
  /// in tablespoons.
  Quantity operator +(Quantity other) {
    if (other.kind != kind) {
      throw ArgumentError(
        'Cannot add a ${other.kind.name} quantity to a ${kind.name} one '
        'without a density.',
      );
    }
    return Quantity.canonical(
      canonicalAmount: canonicalAmount + other.canonicalAmount,
      kind: kind,
      preferredUnit: preferredUnit ?? other.preferredUnit,
    );
  }

  Quantity withPreferredUnit(Unit? unit) => Quantity.canonical(
    canonicalAmount: canonicalAmount,
    kind: kind,
    preferredUnit: unit,
  );

  @override
  int compareTo(Quantity other) {
    if (other.kind != kind) {
      throw ArgumentError(
        'Cannot compare ${kind.name} with ${other.kind.name}.',
      );
    }
    return canonicalAmount.compareTo(other.canonicalAmount);
  }

  @override
  bool operator ==(Object other) =>
      other is Quantity &&
      other.kind == kind &&
      other.canonicalAmount == canonicalAmount;

  @override
  int get hashCode => Object.hash(kind, canonicalAmount);

  @override
  String toString() =>
      'Quantity($canonicalAmount ${Units.canonicalFor(kind).id})';
}
