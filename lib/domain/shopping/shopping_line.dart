import 'package:meta/meta.dart';

import '../units/quantity.dart';

/// One line of a shopping list (spec §5.7).
///
/// Three quantities, because the line has to be able to show its own
/// arithmetic — *buy 1 lb — need 2 lb, have 1 lb* — and each of the three
/// answers a different question that only the person shopping can settle:
///
///  * [planned] is what the recipes add up to. Hearth's number.
///  * [wanted] is what you decided to buy instead, because 1.5 lb of beef is
///    two packets. Yours, and it overrides.
///  * [onHand] is what is already in the cupboard.
///
/// [toBuy] is the one that goes to the shop, and the only one printed large.
@immutable
class ShoppingLine {
  const ShoppingLine({
    required this.key,
    required this.name,
    required this.planned,
    this.wanted,
    this.onHand,
    this.checked = false,
    this.foodId,
    this.storeTag,
    this.isManual = false,
    this.hasUnquantified = false,
    this.sortOrder = 0,
    this.sourceRecipeIds = const <String>[],
  });

  /// A manual line — coffee, paper towels — which no recipe asked for.
  ///
  /// Its [planned] is whatever you typed, so it behaves like any other line
  /// from there on. What makes it different is that a rebuild cannot remove
  /// it: the plan never put it here, so the plan does not get a vote.
  factory ShoppingLine.manual({
    required String key,
    required String name,
    List<Quantity> planned = const <Quantity>[],
    String? storeTag,
    int sortOrder = 0,
  }) => ShoppingLine(
    key: key,
    name: name,
    planned: planned,
    storeTag: storeTag,
    isManual: true,
    sortOrder: sortOrder,
  );

  /// What duplicates were matched on — a food id where one is attached, the
  /// normalised name otherwise. The same key `IngredientConsolidator` groups
  /// by, so a line survives a rebuild by being recognised rather than by
  /// position.
  final String key;

  final String name;

  /// What the recipes call for. More than one entry when the same thing was
  /// written in units that cannot be reconciled — 2 tbsp of butter and 50 g
  /// with no density known — which §5.7 says to show side by side rather than
  /// guess at.
  final List<Quantity> planned;

  /// What you decided to buy, when that differs. Null means "what the recipes
  /// said", and the difference is what [isEdited] reports.
  final Quantity? wanted;

  /// How much of it you already have.
  final Quantity? onHand;

  /// Ticked off by hand.
  ///
  /// Kept as its own fact rather than derived from [onHand] covering the need.
  /// They were one thing at first, and that left a line the recipes could only
  /// express in two units at once — 2 tbsp of butter *and* 50 g — with no way
  /// to be marked done at all, because there is no single amount to record as
  /// had. The tick has to work on a line that cannot be measured; that is most
  /// of what a tick is for.
  final bool checked;

  final String? foodId;
  final String? storeTag;
  final bool isManual;

  /// True when a contributing line had no amount at all ("salt to taste"), so
  /// the total understates what is needed. Carried through from the
  /// consolidator rather than recomputed.
  final bool hasUnquantified;

  /// Where this sits in its store's group — the order you walk the shop in.
  final int sortOrder;

  final List<String> sourceRecipeIds;

  /// Whether the amount was decided by hand rather than by the recipes.
  bool get isEdited => wanted != null;

  /// Whether this line can be measured at all.
  ///
  /// False for a line the recipes could only express in two units at once, and
  /// for a manual item typed without an amount. Both are real and both are
  /// bought by eye.
  bool get isMeasurable => planned.length == 1 || wanted != null;

  /// What the shop needs, after your own amount and what you already have.
  ///
  /// Null when the line cannot be measured — then [isChecked] is the only
  /// thing that can be said about it, which is why a mixed-unit line offers
  /// the tick and nothing finer.
  ///
  /// Floored at zero: having more than you need does not mean buying a
  /// negative amount of it, it means buying none.
  Quantity? get toBuy {
    final Quantity? need =
        wanted ?? (planned.length == 1 ? planned.first : null);
    if (need == null) return null;
    if (onHand == null) return need;
    if (onHand!.kind != need.kind) return need;

    final double left = need.canonicalAmount - onHand!.canonicalAmount;
    return Quantity.canonical(
      canonicalAmount: left <= 0 ? 0 : left,
      kind: need.kind,
      preferredUnit: need.preferredUnit,
    );
  }

  /// Whether this is dealt with — ticked, or covered by what you already have.
  ///
  /// Two ways to the same state, which is why the screen reads one thing off
  /// this rather than showing a tick and a shortfall side by side.
  bool get isChecked => checked || (toBuy?.isZero ?? false);

  /// The amount that would tick this line, for the whole-line check-off.
  Quantity? get fullAmount =>
      wanted ?? (planned.length == 1 ? planned.first : null);

  ShoppingLine copyWith({
    String? name,
    List<Quantity>? planned,
    Quantity? wanted,
    bool clearWanted = false,
    Quantity? onHand,
    bool clearOnHand = false,
    bool? checked,
    String? foodId,
    String? storeTag,
    bool? hasUnquantified,
    int? sortOrder,
    List<String>? sourceRecipeIds,
  }) => ShoppingLine(
    key: key,
    name: name ?? this.name,
    planned: planned ?? this.planned,
    wanted: clearWanted ? null : (wanted ?? this.wanted),
    onHand: clearOnHand ? null : (onHand ?? this.onHand),
    checked: checked ?? this.checked,
    foodId: foodId ?? this.foodId,
    storeTag: storeTag ?? this.storeTag,
    isManual: isManual,
    hasUnquantified: hasUnquantified ?? this.hasUnquantified,
    sortOrder: sortOrder ?? this.sortOrder,
    sourceRecipeIds: sourceRecipeIds ?? this.sourceRecipeIds,
  );

  /// Ticked, or un-ticked.
  ///
  /// Un-ticking also clears an on-hand amount that was covering the need —
  /// otherwise the line would tick itself straight back on and the tap would
  /// look broken. A *partial* amount is left alone: it is a separate fact and
  /// un-ticking was not a claim about it.
  ShoppingLine ticked(bool value) {
    if (value) return copyWith(checked: true);
    final bool covered = toBuy?.isZero ?? false;
    return copyWith(checked: false, clearOnHand: covered);
  }

  @override
  String toString() => 'ShoppingLine($name, buy $toBuy)';
}
