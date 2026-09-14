import '../units/quantity.dart';
import '../units/unit.dart';
import 'amount_parser.dart';

/// A pack size — "1 lb", "7.2 oz", "680 g" — as a quantity, or null.
///
/// Reuses the pieces already here rather than a new parser: [parseAmount] for
/// the number, [Units.parse] for the unit, which is the pair the ingredient
/// parser uses. Null when either half is missing, because half a pack size
/// silently orders the wrong amount.
///
/// In `lib/domain/` rather than beside the food editor that first needed it,
/// because the nutrition sources parse the same thing: Open Food Facts
/// publishes the package size as a string in exactly this shape, and a data
/// adapter cannot reach into a feature to read it.
Quantity? parsePackSize(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return null;

  final Match? split = RegExp(r'^([^a-zA-Z]+)\s*(.*)$').firstMatch(text);
  if (split == null) return null;
  final double? amount = parseAmount(split.group(1)!);
  if (amount == null || amount <= 0) return null;

  final String unitWord = split.group(2)!.trim();
  final Unit? unit = unitWord.isEmpty ? Units.item : Units.parse(unitWord);
  return unit == null ? null : Quantity.of(amount, unit);
}
