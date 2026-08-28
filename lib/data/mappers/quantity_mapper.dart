import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';

/// Maps a [Quantity] to and from its three stored columns.
///
/// The split is deliberate and matches the database: the canonical amount is
/// the value, the kind tells you which canonical unit it is in, and the unit
/// is only the display hint recording how the line was authored (spec §4).
abstract final class QuantityMapper {
  static const String _volume = 'volume';
  static const String _mass = 'mass';
  static const String _count = 'count';

  static String kindToSql(UnitKind kind) => switch (kind) {
    UnitKind.volume => _volume,
    UnitKind.mass => _mass,
    UnitKind.count => _count,
  };

  static UnitKind? kindFromSql(String? value) => switch (value) {
    _volume => UnitKind.volume,
    _mass => UnitKind.mass,
    _count => UnitKind.count,
    _ => null,
  };

  /// Rebuilds a quantity from its columns, or null when the line carried no
  /// amount ("salt to taste").
  ///
  /// An unrecognised unit id degrades to "no display hint" rather than
  /// throwing: the value is still correct, and losing the authored unit is a
  /// cosmetic loss, not a data one.
  static Quantity? fromSql({
    required double? canonicalAmount,
    required String? kind,
    required String? unitId,
  }) {
    if (canonicalAmount == null) return null;
    final UnitKind? resolved = kindFromSql(kind);
    if (resolved == null) return null;
    return Quantity.canonical(
      canonicalAmount: canonicalAmount,
      kind: resolved,
      preferredUnit: unitId == null ? null : Units.byId(unitId),
    );
  }

  static double? amountToSql(Quantity? quantity) => quantity?.canonicalAmount;

  static String? kindColumnToSql(Quantity? quantity) =>
      quantity == null ? null : kindToSql(quantity.kind);

  static String? unitToSql(Quantity? quantity) => quantity?.preferredUnit?.id;
}
