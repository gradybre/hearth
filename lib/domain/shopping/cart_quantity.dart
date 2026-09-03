import 'dart:math' as math;

import '../units/quantity.dart';
import '../units/unit.dart';
import 'shopping_line.dart';

/// How many of a product to put in the cart (spec §5.7).
///
/// Walmart's quantity means *how many of this product*, and Hearth's list
/// says *how much of this ingredient*. Two pounds of beef is one two-pound
/// pack or two one-pound packs, and nothing in the app knows which — so this
/// is a fallback chain rather than a calculation, and every step of it is
/// allowed to say "one".
abstract final class CartQuantity {
  /// Above this, an amount is far likelier to be a mistyped pack size than a
  /// real shop. Two hundred packets of anything is not a weekly grocery run,
  /// and Walmart would accept the order without blinking.
  static const int cap = 24;

  static int forLine({required ShoppingLine line, Quantity? pack}) {
    final Quantity? need = line.toBuy;
    if (need == null || need.isZero) return 1;

    // Whole packs, rounded **up**: coming home short is the failure that
    // costs another trip, and one spare pack of something you buy anyway is
    // not a failure at all.
    if (pack != null && !pack.isZero && pack.kind == need.kind) {
      // Canonical amounts are directly comparable within a kind, so this
      // needs no conversion — and asking for one across kinds would throw
      // rather than answer (see Quantity.amountIn).
      final double packs = need.canonicalAmount / pack.canonicalAmount;
      return _bounded(packs.ceil());
    }

    // No pack size. A countable line is the one case where the list's number
    // and the shop's mean something close to the same thing.
    //
    // Close, not the same: Hearth counts *servings*, so six servings of
    // yoghurt asks for six of whatever a yoghurt is sold as. Accepted
    // deliberately — it is right for the loose produce this mostly covers.
    if (need.kind == UnitKind.count) {
      return _bounded(need.canonicalAmount.ceil());
    }

    return 1;
  }

  static int _bounded(int quantity) => math.max(1, math.min(cap, quantity));
}
