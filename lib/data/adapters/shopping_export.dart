import 'package:meta/meta.dart';

import '../../domain/models/food.dart';
import '../../domain/shopping/cart_review.dart';
import '../../domain/shopping/shopping_line.dart';

/// A captured local source for the review. Callers supply a fresh source
/// before a handoff and return null if it is unavailable or no longer theirs.
/// Collections and the comparison evidence are captured at construction.
@immutable
class ShoppingExportSource {
  ShoppingExportSource({
    required List<ShoppingLine> lines,
    Map<String, Food> foods = const <String, Food>{},
  }) : lines = List<ShoppingLine>.unmodifiable(lines),
       foods = Map<String, Food>.unmodifiable(foods),
       fingerprint = CartReviewEvidence.capture(lines, foods);

  final List<ShoppingLine> lines;
  final Map<String, Food> foods;
  final String fingerprint;
}

/// One line as it will be handed to a store.
@immutable
class ShoppingExportItem {
  const ShoppingExportItem({
    required this.name,
    this.quantityLabel,
    this.shortfall,
    this.storeTag,
    this.productId,
    this.quantity,
    this.hasUnquantified = false,
    this.lineKey,
    this.productName,
    this.productBrand,
    this.needLabel,
    this.packLabel,
    this.wasCapped = false,
    this.hasUnresolvedAmount = false,
  });

  final String name;

  /// Already rendered for humans, and in the words the shelf uses where
  /// Hearth knows them: "3 tbsp olive oil" for a thing sold loose, "3 × 24 oz"
  /// for a thing sold in jars (spec §5.7).
  final String? quantityLabel;

  /// What the recipes asked for, when the packs do not come to it.
  ///
  /// Null unless [quantityLabel] is a pack count that rounded up. Three jars
  /// is seventy-two ounces and the ragu wants sixty-four, and a rounding the
  /// shopper cannot see is a rounding they cannot judge — the same pair the
  /// list itself shows, so the copy in their hand says what the screen said.
  final String? shortfall;

  final String? storeTag;

  /// The shop's own code for this product, when the household has told Hearth
  /// one. Null for most items, and for everything added by hand — a cart
  /// hand-off can only carry the ones it can name.
  final String? productId;

  /// At least one ask has no measured amount. Keep it in copy and search,
  /// but do not present a cart count as covering the complete need.
  final bool hasUnquantified;

  /// A known pack count or an explicit trip-only choice. Null means that no
  /// conversion is known, or the shopper chose to skip this product.
  final int? quantity;

  final String? lineKey;
  final String? productName;
  final String? productBrand;
  final String? needLabel;
  final String? packLabel;
  final bool wasCapped;

  /// No single complete, measured need is available. Unlike an unknown pack
  /// conversion, this remains excluded until the shopping amount is resolved.
  final bool hasUnresolvedAmount;

  bool get canChooseCartQuantity =>
      productId != null && !hasUnquantified && !hasUnresolvedAmount;

  ShoppingExportItem withCartQuantity(int? count) => ShoppingExportItem(
    name: name,
    quantityLabel: quantityLabel,
    shortfall: shortfall,
    storeTag: storeTag,
    productId: productId,
    quantity: count,
    hasUnquantified: hasUnquantified,
    lineKey: lineKey,
    productName: productName,
    productBrand: productBrand,
    needLabel: needLabel,
    packLabel: packLabel,
    wasCapped: wasCapped,
    hasUnresolvedAmount: hasUnresolvedAmount,
  );
}

/// What an export produced, for the UI to act on.
@immutable
class ShoppingExportResult {
  const ShoppingExportResult({
    required this.kind,
    this.deepLinks = const <Uri>[],
    this.clipboardText,
    this.cartLink,
  });

  final ShoppingExportKind kind;

  /// One search link per item, for adapters that can only deep-link.
  final List<Uri> deepLinks;

  /// The list as text, for the one-tap copy path.
  final String? clipboardText;

  /// One link that fills a basket, when the shop offers such a thing and
  /// enough items could be named. Kept apart from [deepLinks] so nothing can
  /// confuse "fill a basket" with "search for one thing".
  final Uri? cartLink;
}

enum ShoppingExportKind { deepLink, clipboard, cart }

/// A store hand-off, behind an interface (CLAUDE.md rule 7).
///
/// Builds copy, searches and a basket link from saved product identities and
/// reviewed purchase counts. Implementations do not launch external actions.
///
/// **Nothing here may send anything anywhere on its own.** The list is fully
/// editable first and the export is a deliberate, reviewed hand-off, never a
/// silent one (spec §5.7, CLAUDE.md rule 4).
///
abstract interface class ShoppingExportAdapter {
  /// Shown on the export button.
  String get displayName;

  /// What this adapter can actually do, so the UI can describe the hand-off
  /// honestly rather than promising a cart it cannot fill.
  ShoppingExportKind get kind;

  /// Builds the hand-off from an already-reviewed list.
  Future<ShoppingExportResult> export(List<ShoppingExportItem> items);
}
