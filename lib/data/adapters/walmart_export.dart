import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/shopping/cart_quantity.dart';
import '../../domain/shopping/pack_display.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/units/quantity.dart';
import 'shopping_export.dart';

/// Handing the list to Walmart (spec §5.7).
///
/// Walmart *does* have an open add-to-cart URL — `/sc/cart/addToCart?items=`,
/// documented at walmart.io/docs/atc/v1/add-to-cart, and explicitly available
/// whether or not you are onboarded to Impact Radius. What it will not do is
/// take a name: it wants Walmart item ids, and resolving "ground beef" to one
/// needs the catalog API, which *is* partner-gated.
///
/// So v1 is a search link per item and the list as text, until a food can
/// carry an item id of its own. The interface is what lets that, or
/// Instacart's cart API, replace this without the screen changing.
///
/// **Nothing here sends anything.** It builds links and text and hands them
/// back; opening or copying is a separate, deliberate tap (rule 4).
class WalmartExport implements ShoppingExportAdapter {
  const WalmartExport();

  static const String _search = 'https://www.walmart.com/search';

  @override
  String get displayName => 'Walmart';

  @override
  ShoppingExportKind get kind => ShoppingExportKind.deepLink;

  /// The open add-to-cart URL: comma-separated `itemId_qty`, a bare id
  /// meaning one. Documented at walmart.io/docs/atc/v1/add-to-cart, and
  /// explicitly available whether or not you are onboarded to Impact Radius —
  /// no key, no approval.
  static const String _cart = 'https://www.walmart.com/sc/cart/addToCart';

  /// A basket of everything Hearth can name, or null when it can name none.
  ///
  /// Only items with a product id go in. Walmart's documentation says that if
  /// *any* item fails to add, the shopper gets an error modal and is dropped
  /// on the homepage — so a link carrying a name it invented would cost the
  /// whole trip, not just that line.
  static Uri? cartLinkFor(List<ShoppingExportItem> items) {
    final List<String> named = <String>[
      for (final ShoppingExportItem item in items)
        if (item.productId case final String id)
          // A bare id already means one, so the suffix is noise on most lines.
          item.quantity <= 1 ? id : '${id}_${item.quantity}',
    ];
    if (named.isEmpty) return null;
    return Uri.parse(_cart)
        .replace(queryParameters: <String, String>{'items': named.join(',')});
  }

  @override
  Future<ShoppingExportResult> export(List<ShoppingExportItem> items) async {
    final Uri? cart = cartLinkFor(items);
    return ShoppingExportResult(
      // `cart` only when something can actually go in one — the kind is what
      // a screen reads to decide whether to offer the basket at all.
      kind: cart == null
          ? ShoppingExportKind.deepLink
          : ShoppingExportKind.cart,
      cartLink: cart,
      deepLinks: <Uri>[
        for (final ShoppingExportItem item in items)
          Uri.parse(_search).replace(
            // The name only. A quantity in a search box finds nothing —
            // "2 lb ground beef" is not a product, and the amount is for
            // the person reading the list, not for the shop's index.
            queryParameters: <String, String>{'q': item.name},
          ),
      ],
      clipboardText: asText(items),
    );
  }

  /// The list as something you can paste anywhere.
  ///
  /// Grouped by store, because that is how it was read on screen and a list
  /// that reorders itself on the way out is a list you have to check again.
  static String asText(List<ShoppingExportItem> items) {
    final Map<String, List<ShoppingExportItem>> byStore =
        <String, List<ShoppingExportItem>>{};
    for (final ShoppingExportItem item in items) {
      byStore
          .putIfAbsent(item.storeTag ?? '', () => <ShoppingExportItem>[])
          .add(item);
    }

    final List<String> stores = byStore.keys.toList()
      ..sort((String a, String b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    final StringBuffer out = StringBuffer();
    for (final String store in stores) {
      if (stores.length > 1 || store.isNotEmpty) {
        if (out.isNotEmpty) out.writeln();
        out.writeln(store.isEmpty ? 'Anywhere' : store);
      }
      for (final ShoppingExportItem item in byStore[store]!) {
        final String amount = item.quantityLabel ?? '';
        // The rounding travels with the pack count, the way it does on the
        // list: "3 × 24 oz marinara (needs 64 oz)". After the name rather
        // than inside the amount, because the amount is what the line leads
        // with and a parenthesis in front of it reads as part of the number.
        final String needs = item.shortfall == null
            ? ''
            : ' (${item.shortfall})';
        out.writeln(
          amount.isEmpty
              ? '- ${item.name}$needs'
              : '- $amount ${item.name}$needs',
        );
      }
    }
    return out.toString().trimRight();
  }
}

/// The lines an export should carry.
///
/// What is left to buy, in the amount to buy — not what the recipes wanted.
/// A ticked line and a line you already have enough of are the same thing to
/// somebody standing in a shop: nothing to pick up.
/// [foods] is passed in rather than looked up, so this and the adapter stay
/// pure — nothing in here may reach a database or a network.
List<ShoppingExportItem> exportableLines(
  List<ShoppingLine> lines, {
  Map<String, Food> foods = const <String, Food>{},
}) => <ShoppingExportItem>[
  for (final ShoppingLine line in lines)
    if (!line.isChecked)
      if (_food(line, foods) case final Food? food)
        if (_amount(line, food?.packSize) case final _Amount amount)
          ShoppingExportItem(
            name: line.name,
            quantityLabel: amount.label,
            shortfall: amount.shortfall,
            storeTag: line.storeTag,
            productId: food?.walmartItemId,
            quantity: CartQuantity.forLine(line: line, pack: food?.packSize),
          ),
];

Food? _food(ShoppingLine line, Map<String, Food> foods) =>
    line.foodId == null ? null : foods[line.foodId];

typedef _Amount = ({String? label, String? shortfall});

/// What the exported line says to buy, in words.
///
/// The same order the list on screen reads in, and through the same
/// [PackDisplay] — a second opinion about how a pack reads is how the copy in
/// somebody's hand comes to disagree with the screen they copied it from.
_Amount _amount(ShoppingLine line, Quantity? pack) {
  // Packs first, where the thing comes in them. "4 lb" of a sauce sold in
  // 24-ounce jars is arithmetically perfect and useless at the shelf.
  final String? packed = PackDisplay.forLine(line: line, pack: pack);
  if (packed != null) {
    return (
      label: packed,
      shortfall: PackDisplay.shortfall(line: line, pack: pack),
    );
  }

  final Quantity? buy = line.toBuy;
  if (buy != null) {
    return (
      label: buy.isZero ? null : QuantityFormat.format(buy),
      shortfall: null,
    );
  }
  if (line.planned.isEmpty) return (label: null, shortfall: null);
  // Written two ways at once and never settled — both go, because dropping
  // one would be choosing an amount the app declined to choose.
  return (
    label: line.planned.map(QuantityFormat.format).join(' + '),
    shortfall: null,
  );
}
