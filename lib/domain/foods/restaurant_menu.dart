import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/recipe.dart';
import '../parsing/amount_parser.dart';
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

  /// The household's own saved orders for [restaurant] (review N03).
  ///
  /// A restaurant meal is an ordinary recipe — `RecipeKind.eatenOut`, with the
  /// menu's foods as its components — so this surfaces what is already there
  /// rather than keeping a second store of orders beside the library.
  ///
  /// **Matched by the components first.** The builder records the restaurant
  /// in the recipe's `notes`, and `notes` is a plain text box in the editor:
  /// anybody who rewrites it as "the one on Fulton St" would sever the tie.
  /// A recipe whose matched foods are this restaurant's menu foods is one of
  /// its orders whatever the notes were changed to, and that cannot be typed
  /// over. The notes are the fallback, and they still carry the case the
  /// components cannot — an order saved before its ingredients were matched
  /// to anything.
  ///
  /// A cooked recipe is never an order, however it is made: you can cook with
  /// a food that came off a menu, and dinner at home is not a thing you
  /// ordered.
  /// How many are offered above the menu.
  ///
  /// They sit between the search field and the first heading, on the screen
  /// whose whole subject is reaching the menu faster — so a household with
  /// fifteen orders here would be the problem wearing a different hat. The
  /// rest are in the recipe library, which is where a list of everything
  /// belongs.
  static const int usualOrdersShown = 3;

  static List<Recipe> usualOrders({
    required String restaurant,
    required Iterable<Recipe> recipes,
    required Map<String, Food> foods,
    Set<String> favourites = const <String>{},
  }) {
    final String wanted = restaurant.trim().toLowerCase();
    if (wanted.isEmpty) return const <Recipe>[];

    bool fromHere(Recipe recipe) {
      for (final RecipeIngredient ingredient in recipe.allIngredients) {
        final String? id = ingredient.foodId;
        if (id == null) continue;
        final Food? food = foods[id];
        if (food == null || !_isMenuItem(food)) continue;
        if (food.brand!.trim().toLowerCase() == wanted) return true;
      }
      // Nothing matched to a menu food. The builder's own note is all that is
      // left, and it is what an unmatched order still has.
      return (recipe.notes ?? '').trim().toLowerCase() == wanted;
    }

    final List<Recipe> found = <Recipe>[
      for (final Recipe recipe in recipes)
        if (recipe.kind == RecipeKind.eatenOut &&
            !recipe.isDeleted &&
            fromHere(recipe))
          recipe,
    ];

    // Favourite first, then whatever order they arrived in — which is
    // already most-recent, because the library reads `updatedAt desc`. A
    // stable sort, so two favourites keep that recency between them.
    final List<Recipe> ordered = <Recipe>[
      for (final Recipe recipe in found)
        if (favourites.contains(recipe.id)) recipe,
      for (final Recipe recipe in found)
        if (!favourites.contains(recipe.id)) recipe,
    ];

    return ordered.take(usualOrdersShown).toList();
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

  /// Whether this row can be picked in the *other* direction — taken out of a
  /// meal rather than put into one (spec §5.2).
  ///
  /// Two rows cannot be, and for opposite reasons:
  ///
  ///  * a **modifier** is a deduction the chain published, so taking one out
  ///    would be an addition it never published;
  ///  * a row the sheet gave **no portion** has no amount for the sign to sit
  ///    on. [MenuPick.line] writes the bare name for one, so "take out X"
  ///    would become an unquantified ingredient that subtracts nothing and is
  ///    flagged for having no amount — a deduction that silently does not
  ///    deduct, which is worse than one that is never offered.
  ///
  /// Whether anything is picked yet for it to come *out of* is a separate
  /// question, and one only the builder can answer.
  static bool canBeTakenOut(Food food) =>
      !food.isModifier && food.defaultServing != null;

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
///
/// **A negative count takes the component out.** A published cheeseburger
/// figure counts the lettuce that came on it, so "no lettuce" is that same
/// ordinary menu row picked in the other direction (spec §5.2). It is
/// deliberately not the modifier mechanism: a modifier is a row the chain
/// itself publishes as a deduction, with per-column signs of its own, and this
/// is a positive row the person eating chose to subtract. The sign lives on
/// the pick, so nothing about the food changes and the same row serves both
/// directions.
@immutable
class MenuPick {
  const MenuPick({required this.food, this.count = 1});

  final Food food;
  final double count;

  /// Whether this pick takes its component out rather than putting it in.
  bool get isRemoval => count < 0;

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

  /// Just the amount — "8 oz", "2 oz" — for a row that already names the
  /// thing beside it.
  String get portionLabel {
    final Quantity? amount = quantity;
    if (amount == null) return '';
    final Unit unit = amount.preferredUnit ?? Units.canonicalFor(amount.kind);
    final String label = unit.label.isEmpty ? 'ea' : unit.label;
    return '${_number(amount.amountIn(unit))} $label';
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

    return '$portionLabel ${food.name}';
  }

  /// A portion, written the way a person would write it.
  ///
  /// [writeAmount] gives whole numbers and friendly fractions — both of which
  /// [parseAmount] reads straight back, which matters because this string is
  /// parsed again by the recipe editor.
  ///
  /// The rounding in front of it is the fix for a real report: a bowl arrived
  /// reading "4.000000017636981 oz Cilantro-Lime Brown Rice". Converting out
  /// of a canonical amount and back is floating-point arithmetic, so a
  /// portion stored as 4 oz can return 4.000000018 — and that is not a
  /// quantity anybody typed or would recognise.
  ///
  /// Snapped rather than rounded, and the difference matters: rounding to a
  /// fixed number of places turns a third of a cup into "0.333333", because
  /// [writeAmount] recognises 1/3 only to within a billionth. So the value is
  /// moved to the nearest thousandth **only when it is already essentially
  /// there** — which erases conversion residue and leaves anything anybody
  /// actually meant exactly where it was.
  ///
  /// The sign is written separately from the magnitude, and as the real minus
  /// U+2212: that is what the ingredient parser reads back as a deduction,
  /// where a hyphen would be read as a bullet and quietly dropped — turning
  /// "no lettuce" into extra lettuce. Separately, because [writeAmount] splits
  /// a mixed number into a whole part and a remainder, and a sign has no
  /// business in that arithmetic.
  static String _number(double value) {
    final double magnitude = value.abs();
    final double snapped = (magnitude * 1000).roundToDouble() / 1000;
    final String written = writeAmount(
      (magnitude - snapped).abs() < 1e-6 ? snapped : magnitude,
    );
    return value < 0 ? '−$written' : written;
  }

  @override
  bool operator ==(Object other) =>
      other is MenuPick && other.food.id == food.id && other.count == count;

  @override
  int get hashCode => Object.hash(food.id, count);
}
