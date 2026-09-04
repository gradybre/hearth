import 'package:meta/meta.dart';

import '../models/food.dart';
import '../units/quantity.dart';
import '../units/unit.dart';

/// The restaurants a household has seeded, and what is on their menus
/// (spec §5.2).
///
/// **A restaurant is a brand, not a table.** The foods already carry one, it
/// is already displayed and searched, and one string is all that is needed to
/// group a menu — so seeding a second chain is adding foods, not running a
/// migration. What that costs is per-restaurant metadata and a cheap rename;
/// neither is worth a table for a household that eats at a handful of places.
/// A real `venues` table can replace this later without changing anything a
/// user sees, because the brand string becomes its name.
abstract final class RestaurantMenu {
  /// Every restaurant with at least one food, alphabetically.
  ///
  /// Alphabetical rather than by how often they are used: a list that
  /// reorders itself is one you cannot build muscle memory against, which is
  /// the same reason the recents list sorts by recency alone.
  static List<String> restaurantsIn(Iterable<Food> library) {
    final Set<String> names = <String>{
      for (final Food food in library)
        if (_isMenuItem(food)) food.brand!.trim(),
    };
    return names.toList()..sort(_byName);
  }

  /// One restaurant's menu, in the order the restaurant lays it out.
  ///
  /// `menuOrder` is the position on the sheet, so items come out where the
  /// sheet put them. Anything without one falls to the end, alphabetically —
  /// an item added by hand has no place on a sheet nobody pasted, and putting
  /// it first would push the menu down the screen.
  static List<Food> itemsFor(String restaurant, Iterable<Food> library) {
    final String wanted = restaurant.trim().toLowerCase();
    return <Food>[
      for (final Food food in library)
        if (_isMenuItem(food) && food.brand!.trim().toLowerCase() == wanted)
          food,
    ]..sort(_bySheet);
  }

  /// One restaurant's menu in its sections, in the order they are printed.
  ///
  /// A menu is not an alphabetical list: meats sit together, salsas sit
  /// together, and somebody looking for guacamole looks under the toppings.
  /// A builder that sorts A to Z asks them to read the whole thing instead.
  ///
  /// Sections are ordered by **where each first appears on the sheet**, not
  /// by name — which is what makes this the restaurant's own order rather
  /// than one imposed on it. Items with no section come last under a null
  /// heading, so an item added by hand is never lost, only unlabelled.
  static List<MenuSection> sectionsFor(
    String restaurant,
    Iterable<Food> library,
  ) {
    final List<Food> items = itemsFor(restaurant, library);
    final Map<String?, List<Food>> grouped = <String?, List<Food>>{};
    for (final Food food in items) {
      final String? section = (food.menuGroup ?? '').trim().isEmpty
          ? null
          : food.menuGroup!.trim();
      grouped.putIfAbsent(section, () => <Food>[]).add(food);
    }

    // `items` is already in sheet order, so insertion order *is* first
    // appearance — the map has done the ordering by being filled in order.
    final List<MenuSection> sections = <MenuSection>[
      for (final MapEntry<String?, List<Food>> entry in grouped.entries)
        MenuSection(name: entry.key, items: entry.value),
    ];

    // The unnamed one is last wherever it turned up.
    final int unnamed = sections.indexWhere((MenuSection s) => s.name == null);
    if (unnamed >= 0 && unnamed != sections.length - 1) {
      sections.add(sections.removeAt(unnamed));
    }
    return sections;
  }

  /// Sheet order, then name for anything the sheet never numbered.
  static int _bySheet(Food a, Food b) {
    final int? left = a.menuOrder;
    final int? right = b.menuOrder;
    if (left != null && right != null) return left.compareTo(right);
    if (left != null) return -1;
    if (right != null) return 1;
    return _byName(a.name, b.name);
  }

  /// A live food read off a restaurant's own menu, with a restaurant on it.
  ///
  /// The brand check is not belt-and-braces: a restaurant food with no brand
  /// belongs to no menu, so listing it would put an item on a screen that no
  /// restaurant could reach. The editor refuses to save one, and this is what
  /// happens to any that predate that rule.
  static bool _isMenuItem(Food food) =>
      food.source == FoodSource.restaurant &&
      !food.isDeleted &&
      (food.brand ?? '').trim().isNotEmpty;

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}

/// One part of a menu — "Proteins", "Salsas" — and what is in it.
///
/// A null [name] is the items the sheet never sectioned, which the builder
/// shows without a heading rather than under one it invented.
@immutable
class MenuSection {
  const MenuSection({required this.name, required this.items});

  final String? name;
  final List<Food> items;
}

/// One thing picked off a menu, and how much of it.
///
/// [count] multiplies the food's own serving rather than naming an amount:
/// every portion on a restaurant sheet is the portion they serve, so the only
/// question anybody has is how many of them. Double meat is 2.
@immutable
class MenuPick {
  const MenuPick({required this.food, this.count = 1});

  final Food food;
  final double count;

  MenuPick withCount(double next) => MenuPick(food: food, count: next);

  /// What this pick amounts to, or null for a food with no serving at all.
  Quantity? get quantity {
    final ServingOption? serving = food.defaultServing;
    if (serving == null) return null;
    return Quantity.canonical(
      canonicalAmount: serving.amount.canonicalAmount * count,
      kind: serving.amount.kind,
      preferredUnit: serving.amount.preferredUnit,
    );
  }

  /// The ingredient line this pick writes into a recipe.
  ///
  /// Written so the parser reads it straight back — the amount, the unit as
  /// it was authored, then the name. A count unit has an empty label, so
  /// `ea` stands in: "2 Flour Tortilla" would leave the parser with a bare
  /// number and no unit to hang it on.
  String get line {
    final Quantity? amount = quantity;
    if (amount == null) return food.name;

    final Unit unit = amount.preferredUnit ?? Units.canonicalFor(amount.kind);
    final String label = unit.label.isEmpty ? 'ea' : unit.label;
    return '${_number(amount.amountIn(unit))} $label ${food.name}';
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  @override
  bool operator ==(Object other) =>
      other is MenuPick && other.food.id == food.id && other.count == count;

  @override
  int get hashCode => Object.hash(food.id, count);
}
