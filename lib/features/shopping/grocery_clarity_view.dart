import '../../domain/models/food.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/units/quantity.dart';

/// Presentation states only. The resolver remains the authority on amounts.
enum GroceryLineState { remaining, bought, atHome, notNeeded }

GroceryLineState groceryLineState(ShoppingLine line, {Food? food}) {
  if (line.checked) return GroceryLineState.bought;
  final ResolvedShoppingLine resolved = ShoppingLineResolver.resolve(
    line: line,
    food: food,
  );
  final Quantity? need = resolved.line.fullAmount;
  if (need == null || line.hasUnquantified) return GroceryLineState.remaining;
  if (need.canonicalAmount <= 0) return GroceryLineState.notNeeded;
  final Quantity? have = resolved.onHand;
  if (have != null &&
      have.canonicalAmount > 0 &&
      have.kind == need.kind &&
      (resolved.toBuy?.isZero ?? false)) {
    return GroceryLineState.atHome;
  }
  return GroceryLineState.remaining;
}

/// Replaces only the visible slots in one store's order. Hidden rows stay
/// between the same slots, and rows added during a drag keep their place.
List<ShoppingLine> reorderGroceryLines({
  required List<ShoppingLine> lines,
  required String store,
  required List<String> visibleOrder,
}) {
  final List<ShoppingLine> group =
      <ShoppingLine>[
        for (final ShoppingLine line in lines)
          if ((line.storeTag ?? '') == store) line,
      ]..sort(
        (ShoppingLine a, ShoppingLine b) => a.sortOrder.compareTo(b.sortOrder),
      );
  final Map<String, ShoppingLine> byKey = <String, ShoppingLine>{
    for (final ShoppingLine line in group) line.key: line,
  };
  final List<String> surviving = <String>[
    for (final String key in visibleOrder)
      if (byKey.containsKey(key)) key,
  ];
  final Set<String> moved = surviving.toSet();
  final Iterator<String> reordered = surviving.iterator;
  final Map<String, int> order = <String, int>{};
  for (int i = 0; i < group.length; i++) {
    String key = group[i].key;
    if (moved.contains(key)) {
      reordered.moveNext();
      key = reordered.current;
    }
    order[key] = i;
  }
  return <ShoppingLine>[
    for (final ShoppingLine line in lines)
      if (order[line.key] case final int position)
        line.copyWith(sortOrder: position)
      else
        line,
  ];
}
