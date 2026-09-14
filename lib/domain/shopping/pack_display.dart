import '../format/quantity_format.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'cart_quantity.dart';
import 'shopping_line.dart';

/// What a line says when the thing is sold in packs (spec §5.7).
///
/// A shopping list's job is to tell you what to pick up, and for anything in
/// a jar, a can or a bag a weight does not. Rao's marinara comes in 24-ounce
/// jars; "4 lb" is arithmetically perfect and useless at the shelf, because
/// nobody sells four pounds of it and the only question you actually have is
/// how many jars.
///
/// So: **three by twenty-four ounces**, not three jars. The pack size is
/// something Open Food Facts and USDA both publish, and the noun is not — a
/// vocabulary of jars, cans, tubs and pouches would have to be typed by hand
/// across every food or guessed from a product name, and a wrong guess reads
/// worse than no noun at all. The multiplication says everything the noun
/// would have, in terms that come free with the data.
///
/// Foods sold by weight are untouched. Two pounds of mince stays two pounds,
/// because that is what the scale at the counter is going to say.
abstract final class PackDisplay {
  /// How the amount reads, or null when this is not a packaged thing.
  ///
  /// Null rather than a fallback string, so the caller keeps whatever it was
  /// already showing — this only ever *replaces* an answer that was already
  /// correct, and a packaged food Hearth knows nothing about is a food it
  /// should go on describing by weight.
  static String? forLine({required ShoppingLine line, Quantity? pack}) {
    if (pack == null || pack.isZero) return null;

    final Quantity? need = line.toBuy;
    // A line the recipes could only say two ways at once has no single amount
    // to divide, and one that is already dealt with has nothing to pick up.
    if (need == null || need.isZero || need.kind != pack.kind) return null;

    final int packs = CartQuantity.forLine(line: line, pack: pack);

    // Formatted as authored, never normalised. A pack size is the shop's own
    // words — a 24-ounce jar is not a 1.5-pound jar, whatever the arithmetic
    // says, and converting it puts back exactly the number this exists to
    // get rid of.
    final String each = QuantityFormat.formatAsAuthored(pack);

    // One pack is not a multiplication. "1 × 24 oz" reads as arithmetic
    // somebody forgot to finish.
    return packs == 1 ? each : '$packs × $each';
  }

  /// What the recipes actually asked for, when that is not what you are
  /// buying.
  ///
  /// Three jars is seventy-two ounces and the ragu wants sixty-four, and the
  /// eight ounces over are the whole reason to show both: a line that only
  /// says "3 × 24 oz" has quietly rounded up, and a shopper who cannot see
  /// the rounding cannot judge it. Null when they agree.
  static String? shortfall({required ShoppingLine line, Quantity? pack}) {
    if (pack == null || pack.isZero) return null;

    final Quantity? need = line.toBuy;
    if (need == null || need.isZero || need.kind != pack.kind) return null;

    final int packs = CartQuantity.forLine(line: line, pack: pack);
    final double bought = pack.canonicalAmount * packs;
    // Equal to within a gram or a millilitre. Canonical amounts are doubles
    // and a pack that divides exactly still arrives with a rounding tail.
    if ((bought - need.canonicalAmount).abs() < 1) return null;

    // In the pack's own unit, so the two numbers can be read against each
    // other. "3 × 24 oz / needs 4 lb" makes the reader do the conversion
    // before they can see whether the rounding is worth minding.
    final Unit? unit = pack.preferredUnit;
    return unit == null
        ? 'needs ${QuantityFormat.format(need)}'
        : 'needs ${QuantityFormat.formatIn(need, unit)}';
  }
}
