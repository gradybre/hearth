import 'package:meta/meta.dart';

import '../models/food.dart';
import '../units/quantity.dart';

/// How much a pack size on this food would actually be worth (spec §5.7).
///
/// The shopping list counts jars instead of weighing them, and it can only do
/// that for a food that says how big one jar is. A library that has been
/// going for a year has hundreds of foods and only a handful of them ever
/// reach a shopping list, so a queue sorted by name is a queue nobody
/// finishes — the twenty that matter are scattered through it.
enum PackNeed {
  /// On the list as it stands. Filling this one changes a line you are going
  /// to read at a shelf this week.
  onTheList('On your shopping list'),

  /// A recipe names it, so the next list built from the plan can ask for it.
  inARecipe('Used by your recipes'),

  /// Everything else — logged, saved, never shopped for. Still offered,
  /// because a food only ever joins the two above by being bought.
  elsewhere('Everything else');

  const PackNeed(this.heading);

  /// What the section above these rows is called.
  final String heading;
}

/// One food with no pack size, and what it would be worth filling in.
@immutable
class PackSizeGap {
  const PackSizeGap({
    required this.food,
    required this.need,
    this.recipeCount = 0,
  });

  final Food food;
  final PackNeed need;

  /// How many recipes name it. Orders [PackNeed.inARecipe] within itself: the
  /// thing six recipes want is the thing to fill in first.
  final int recipeCount;

  /// The barcode, when there is one worth asking a database about.
  ///
  /// Blank and whitespace-only codes answer null rather than being sent
  /// outward, because a lookup on an empty string is a round trip that can
  /// only miss.
  String? get barcode {
    final String code = food.barcode?.trim() ?? '';
    return code.isEmpty ? null : code;
  }

  bool get canBeLookedUp => barcode != null;
}

/// Every food that could carry a pack size and does not (spec §5.7).
@immutable
class PackSizeQueue {
  const PackSizeQueue(this.gaps);

  /// Worst first: on the list, then in a recipe, then the rest.
  final List<PackSizeGap> gaps;

  bool get isEmpty => gaps.isEmpty;
  int get length => gaps.length;

  /// The ones a barcode lookup could answer, in the same order.
  List<PackSizeGap> get lookupable => <PackSizeGap>[
    for (final PackSizeGap gap in gaps)
      if (gap.canBeLookedUp) gap,
  ];

  /// Reads the library and finds what has no pack size.
  ///
  /// Four kinds of food are left out, and each for a reason that would
  /// otherwise show up as a wrong number rather than as a missing one:
  ///
  ///  * one that already has a pack size — this is a gap list, not an audit;
  ///  * a soft-deleted one (spec §4), which is not in the library any more;
  ///  * a restaurant menu row, which is eaten rather than bought, so there is
  ///    no shelf and no jar for a pack size to describe;
  ///  * a modifier — "no cheese", a deduction rather than a thing (§5.2).
  ///
  /// Global foods stay in. They are server-owned and saving one writes a
  /// household copy, which is exactly what the food editor already does when
  /// you correct one by hand; leaving them out here would hide a food the
  /// manual path can fix.
  static PackSizeQueue build({
    required Iterable<Food> foods,
    Set<String> onShoppingList = const <String>{},
    Map<String, int> recipeUses = const <String, int>{},
  }) {
    final List<PackSizeGap> gaps = <PackSizeGap>[];
    for (final Food food in foods) {
      if (food.packSize != null) continue;
      if (food.isDeleted) continue;
      if (food.source == FoodSource.restaurant) continue;
      if (food.isModifier) continue;

      final int uses = recipeUses[food.id] ?? 0;
      gaps.add(
        PackSizeGap(
          food: food,
          need: onShoppingList.contains(food.id)
              ? PackNeed.onTheList
              : uses > 0
              ? PackNeed.inARecipe
              : PackNeed.elsewhere,
          recipeCount: uses,
        ),
      );
    }

    gaps.sort((PackSizeGap a, PackSizeGap b) {
      final int byNeed = a.need.index.compareTo(b.need.index);
      if (byNeed != 0) return byNeed;
      final int byUses = b.recipeCount.compareTo(a.recipeCount);
      if (byUses != 0) return byUses;
      final int byName = a.food.name.toLowerCase().compareTo(
        b.food.name.toLowerCase(),
      );
      // Ids last, so two foods with one name keep a stable order rather than
      // swapping places every time the list is rebuilt under somebody's
      // finger.
      return byName != 0 ? byName : a.food.id.compareTo(b.food.id);
    });

    return PackSizeQueue(gaps);
  }
}

/// Putting a pack size onto a food, without touching anything else.
///
/// Its own function rather than a general `copyWith` on [Food]: this is the
/// one field this flow may change, and a copier that could change any of them
/// is a copier that can quietly change one of them. The macros a log was
/// frozen against are not this screen's business (CLAUDE.md rule 3).
extension PackSizeFill on Food {
  Food withPackSize(Quantity? pack) => Food(
    id: id,
    name: name,
    servingOptions: servingOptions,
    source: source,
    householdId: householdId,
    brand: brand,
    storeTag: storeTag,
    walmartItemId: walmartItemId,
    packSize: pack,
    barcode: barcode,
    menuGroup: menuGroup,
    menuOrder: menuOrder,
    gramsPerMillilitre: gramsPerMillilitre,
    macrosOverridden: macrosOverridden,
    isDefault: isDefault,
    isZeroCalorie: isZeroCalorie,
    isModifier: isModifier,
    isDeleted: isDeleted,
    updatedAt: updatedAt,
  );
}
