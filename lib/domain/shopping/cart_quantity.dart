import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../units/quantity.dart';
import '../units/unit.dart';
import 'shopping_line.dart';

/// How many of a product to put in the cart (spec §5.7).
///
/// Walmart's quantity means *how many of this product*, and Hearth's list
/// says *how much of this ingredient*. Two pounds of beef is one two-pound
/// pack or two one-pound packs. [forReview] answers only from known pack
/// evidence; [forLine] retains the list's historical display fallback.
abstract final class CartQuantity {
  /// Above this, an amount is far likelier to be a mistyped pack size than a
  /// real shop. Two hundred packets of anything is not a weekly grocery run,
  /// and Walmart would accept the order without blinking.
  static const int cap = 24;

  /// A prefilled purchase count only when a known pack measures this need.
  ///
  /// A count of servings without a pack is not a count of retail products.
  /// Null asks the shopper to choose a count or skip this item. The older
  /// [forLine] remains the shopping-list display helper; its fallback must
  /// never authorize a retailer handoff.
  static CartQuantityEstimate? forReview({
    required ShoppingLine line,
    Quantity? pack,
  }) {
    final Quantity? need = line.toBuy;
    if (hasUnresolvedCountRemainder(line) ||
        line.hasUnquantified ||
        need == null ||
        !need.canonicalAmount.isFinite ||
        need.canonicalAmount <= 0 ||
        pack == null ||
        !pack.canonicalAmount.isFinite ||
        pack.canonicalAmount <= 0 ||
        pack.kind != need.kind ||
        !sameCountUnit(pack, need)) {
      return null;
    }
    final double packs = need.canonicalAmount / pack.canonicalAmount;
    // Check the cap before converting to an integer: a tiny positive pack
    // can overflow the ratio even though both input amounts are finite.
    if (!packs.isFinite || packs > cap + _slack) {
      return const CartQuantityEstimate(count: cap, wasCapped: true);
    }
    return CartQuantityEstimate(count: _bounded(_ceil(packs)));
  }

  /// Count nouns carry identity: a scoop is not a container. A missing hint
  /// is the legacy generic item, not permission to convert another noun.
  static bool sameCountUnit(Quantity a, Quantity b) =>
      a.kind != UnitKind.count ||
      b.kind != UnitKind.count ||
      (a.preferredUnit ?? Units.item).id == (b.preferredUnit ?? Units.item).id;

  /// Inspect the input before toBuy subtracts and loses the on-hand unit.
  /// These rows must remain reviewable even if that subtraction reports zero.
  static bool hasUnresolvedCountRemainder(ShoppingLine line) {
    final Quantity? need =
        line.wanted ?? (line.planned.length == 1 ? line.planned.single : null);
    final Quantity? have = line.onHand;
    return need != null &&
        have != null &&
        need.kind == UnitKind.count &&
        have.kind == UnitKind.count &&
        need.canonicalAmount > 0 &&
        have.canonicalAmount != 0 &&
        !sameCountUnit(need, have);
  }

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
      return _bounded(_ceil(packs));
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

  /// Rounds up, but not off the back of a rounding error.
  ///
  /// A need is a *sum*: `IngredientConsolidator.combine` adds every recipe's
  /// ask together, and an on-hand amount is subtracted from the total. Both
  /// leave a tail. Two recipes wanting 0.1 lb and 0.2 lb come to
  /// 0.30000000000000004 lb, which against a 0.3 lb pack is 1.0000000000000002
  /// packs — and a bare `ceil()` buys two of them.
  ///
  /// The list said as much out loud once the packs reached it: "2 × 0.3 lb ·
  /// needs 0.3 lb", a rounding shown beside the thing it did not round.
  /// `PackDisplay` already treats a gram either way as agreement; this is the
  /// same judgement one step earlier, where the decision is actually made.
  ///
  /// The slack is a double's last bits and nothing more — a gram over two
  /// jars is still three jars.
  static int _ceil(double packs) {
    final double whole = packs.roundToDouble();
    return (packs - whole).abs() <= _slack ? whole.toInt() : packs.ceil();
  }

  /// Measured on the pack *count*, not on the weight — which [cap] keeps
  /// small, so a fixed slack stays far below anything a shopper could act on.
  static const double _slack = 1e-9;
}

@immutable
class CartQuantityEstimate {
  const CartQuantityEstimate({required this.count, this.wasCapped = false});

  final int count;
  final bool wasCapped;
}
