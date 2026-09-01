import 'package:meta/meta.dart';

/// The physical dimension a [Unit] measures.
///
/// Conversion inside a kind is always exact. Crossing from [volume] to [mass]
/// requires a density (see `density.dart`) and is flagged when unavailable —
/// spec §5.2.
enum UnitKind {
  /// Canonical unit: millilitre.
  volume,

  /// Canonical unit: gram.
  mass,

  /// Canonical unit: one item. Covers "2 eggs", "3 cloves".
  count,
}

/// A unit of measure with an exact factor to its kind's canonical unit.
///
/// Quantities are *stored* canonically and converted only at display time, so
/// per-user imperial/metric preferences render from one source of truth
/// (spec §4, "Canonical units").
@immutable
class Unit {
  const Unit({
    required this.id,
    required this.label,
    required this.kind,
    required this.toCanonical,
    this.aliases = const <String>[],
    this.system = UnitSystem.any,
  });

  /// Stable identifier, persisted with the row. Never localise this.
  final String id;

  /// Short human label used in the UI ("tbsp", "g").
  final String label;

  final UnitKind kind;

  /// Multiply an amount in this unit by this factor to get the canonical
  /// amount (ml for volume, g for mass, items for count).
  final double toCanonical;

  /// Spellings accepted when parsing free-typed ingredient text.
  final List<String> aliases;

  final UnitSystem system;

  @override
  bool operator ==(Object other) => other is Unit && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Unit($id)';
}

/// Which measurement system a unit belongs to, for per-user display preference.
enum UnitSystem { imperial, metric, any }

/// The unit registry.
///
/// Volume factors are the exact US customary definitions (1 tsp = 4.92892159375
/// ml); mass factors are the exact international avoirdupois definitions
/// (1 lb = 453.59237 g). Exactness matters because these feed the
/// "4 x 0.25 == 1" no-drift guarantee (spec §9.1).
abstract final class Units {
  // ── Volume ────────────────────────────────────────────────────────────────
  static const Unit tsp = Unit(
    id: 'tsp',
    label: 'tsp',
    kind: UnitKind.volume,
    toCanonical: 4.92892159375,
    aliases: <String>['teaspoon', 'teaspoons', 't'],
    system: UnitSystem.imperial,
  );
  static const Unit tbsp = Unit(
    id: 'tbsp',
    label: 'tbsp',
    kind: UnitKind.volume,
    toCanonical: 14.78676478125, // 3 tsp
    aliases: <String>['tablespoon', 'tablespoons', 'tbs', 'tbl', 'T'],
    system: UnitSystem.imperial,
  );
  static const Unit flOz = Unit(
    id: 'fl_oz',
    label: 'fl oz',
    kind: UnitKind.volume,
    toCanonical: 29.5735295625, // 2 tbsp
    aliases: <String>['fluid ounce', 'fluid ounces', 'floz'],
    system: UnitSystem.imperial,
  );
  static const Unit cup = Unit(
    id: 'cup',
    label: 'cup',
    kind: UnitKind.volume,
    toCanonical: 236.5882365, // 16 tbsp
    aliases: <String>['cups', 'c'],
    system: UnitSystem.imperial,
  );
  static const Unit pint = Unit(
    id: 'pint',
    label: 'pt',
    kind: UnitKind.volume,
    toCanonical: 473.176473,
    aliases: <String>['pints', 'pt'],
    system: UnitSystem.imperial,
  );
  static const Unit quart = Unit(
    id: 'quart',
    label: 'qt',
    kind: UnitKind.volume,
    toCanonical: 946.352946,
    aliases: <String>['quarts', 'qt'],
    system: UnitSystem.imperial,
  );
  static const Unit gallon = Unit(
    id: 'gallon',
    label: 'gal',
    kind: UnitKind.volume,
    toCanonical: 3785.411784,
    aliases: <String>['gallons', 'gal'],
    system: UnitSystem.imperial,
  );
  static const Unit millilitre = Unit(
    id: 'ml',
    label: 'ml',
    kind: UnitKind.volume,
    toCanonical: 1,
    aliases: <String>['millilitre', 'millilitres', 'milliliter', 'milliliters'],
    system: UnitSystem.metric,
  );
  static const Unit litre = Unit(
    id: 'l',
    label: 'L',
    kind: UnitKind.volume,
    toCanonical: 1000,
    aliases: <String>['litre', 'litres', 'liter', 'liters'],
    system: UnitSystem.metric,
  );

  // ── Mass ──────────────────────────────────────────────────────────────────
  static const Unit gram = Unit(
    id: 'g',
    label: 'g',
    kind: UnitKind.mass,
    toCanonical: 1,
    aliases: <String>['gram', 'grams', 'gr'],
    system: UnitSystem.metric,
  );
  static const Unit kilogram = Unit(
    id: 'kg',
    label: 'kg',
    kind: UnitKind.mass,
    toCanonical: 1000,
    aliases: <String>['kilogram', 'kilograms', 'kilo', 'kilos'],
    system: UnitSystem.metric,
  );
  static const Unit ounce = Unit(
    id: 'oz',
    label: 'oz',
    kind: UnitKind.mass,
    toCanonical: 28.349523125,
    aliases: <String>['ounce', 'ounces'],
    system: UnitSystem.imperial,
  );
  static const Unit pound = Unit(
    id: 'lb',
    label: 'lb',
    kind: UnitKind.mass,
    toCanonical: 453.59237,
    aliases: <String>['pound', 'pounds', 'lbs'],
    system: UnitSystem.imperial,
  );

  // ── Count ─────────────────────────────────────────────────────────────────
  static const Unit item = Unit(
    id: 'item',
    label: '',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['items', 'whole', 'each', 'ea'],
  );
  static const Unit clove = Unit(
    id: 'clove',
    label: 'clove',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['cloves'],
  );
  static const Unit slice = Unit(
    id: 'slice',
    label: 'slice',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['slices'],
  );
  static const Unit pinch = Unit(
    id: 'pinch',
    label: 'pinch',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['pinches'],
  );

  // ── Count: the words on packets ───────────────────────────────────────────
  //
  // A tub of protein powder is sold by the scoop, a cereal bar by the bar, and
  // cream cheese by the package. Offering only `item` meant a food's serving
  // was labelled with a word nobody uses, or the word was dropped and the
  // serving with it.
  //
  // Curated rather than free text, deliberately: `unitId` is persisted, synced
  // and matched against, so a typed-in unit would be a string nothing can
  // convert, compare, or ever tidy up. Adding another is one entry here.
  //
  // "Serving" is deliberately not among them. Every word here names something
  // you can hold; "1 serving" names only itself, and `ServingFormat` already
  // refuses it as a phrase for exactly that reason.
  //
  // None of these converts to any other — [UnitConverter] refuses to cross
  // into or out of count, and that is what makes "1 scoop" and "10 oz" of the
  // same food two facts rather than a contradiction. The pairing is what
  // states the scoop's weight; a label giving both is the only place that fact
  // exists.
  static const Unit scoop = Unit(
    id: 'scoop',
    label: 'scoop',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['scoops'],
  );
  static const Unit bar = Unit(
    id: 'bar',
    label: 'bar',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['bars'],
  );
  static const Unit package = Unit(
    id: 'package',
    label: 'package',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['packages', 'pkg', 'pack', 'packs'],
  );
  static const Unit packet = Unit(
    id: 'packet',
    label: 'packet',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['packets', 'sachet', 'sachets'],
  );
  static const Unit container = Unit(
    id: 'container',
    label: 'container',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['containers', 'tub', 'tubs'],
  );
  static const Unit bottle = Unit(
    id: 'bottle',
    label: 'bottle',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['bottles'],
  );
  static const Unit can = Unit(
    id: 'can',
    label: 'can',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['cans', 'tin', 'tins'],
  );
  static const Unit piece = Unit(
    id: 'piece',
    label: 'piece',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['pieces'],
  );
  static const Unit patty = Unit(
    id: 'patty',
    label: 'patty',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['patties'],
  );
  static const Unit stick = Unit(
    id: 'stick',
    label: 'stick',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['sticks'],
  );
  static const Unit square = Unit(
    id: 'square',
    label: 'square',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['squares'],
  );
  static const Unit tortilla = Unit(
    id: 'tortilla',
    label: 'tortilla',
    kind: UnitKind.count,
    toCanonical: 1,
    aliases: <String>['tortillas'],
  );

  /// Every known unit.
  static const List<Unit> all = <Unit>[
    tsp,
    tbsp,
    flOz,
    cup,
    pint,
    quart,
    gallon,
    millilitre,
    litre,
    gram,
    kilogram,
    ounce,
    pound,
    item,
    clove,
    slice,
    pinch,
    scoop,
    bar,
    package,
    packet,
    container,
    bottle,
    can,
    piece,
    patty,
    stick,
    square,
    tortilla,
  ];

  /// The canonical unit for a kind — the unit amounts are stored in.
  static Unit canonicalFor(UnitKind kind) => switch (kind) {
    UnitKind.volume => millilitre,
    UnitKind.mass => gram,
    UnitKind.count => item,
  };

  static final Map<String, Unit> _byId = <String, Unit>{
    for (final Unit u in all) u.id: u,
  };

  static final Map<String, Unit> _byToken = <String, Unit>{
    for (final Unit u in all) ...<String, Unit>{
      u.id.toLowerCase(): u,
      u.label.toLowerCase(): u,
      for (final String a in u.aliases) a.toLowerCase(): u,
    },
  }..remove('');

  /// Looks up a unit by its persisted [id]. Returns null when unknown.
  static Unit? byId(String id) => _byId[id];

  /// Resolves a free-typed token ("Tablespoons", "tbs", "g") to a unit.
  ///
  /// Case-insensitive except for the ambiguous single letters `t` (tsp) and
  /// `T` (tbsp), which follow the recipe-writing convention.
  static Unit? parse(String token) {
    final String trimmed = token.trim().replaceAll('.', '');
    if (trimmed.isEmpty) return null;
    if (trimmed == 'T') return tbsp;
    if (trimmed == 't') return tsp;
    return _byToken[trimmed.toLowerCase()];
  }
}
