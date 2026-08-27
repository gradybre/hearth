/// Ingredient densities in grams per millilitre, for volume <-> weight
/// conversion (spec §5.2).
///
/// **Scope is deliberately small and is an open decision (spec §12).** These are
/// pantry staples where a cup-to-gram figure is stable and well documented.
/// Anything absent falls back to a literal multiply that is *flagged* rather
/// than silently guessed — an unflagged wrong conversion is worse than an
/// honest "we don't know".
library;

/// A density lookup over a normalised ingredient name.
abstract final class DensityTable {
  /// Grams per millilitre. Values chosen from standard baking references
  /// (e.g. all-purpose flour at 125 g per US cup = 0.528 g/ml).
  static const Map<String, double> gramsPerMillilitre = <String, double>{
    // Liquids
    'water': 1.0,
    'milk': 1.03,
    'buttermilk': 1.03,
    'heavy cream': 0.994,
    'greek yogurt': 1.03,
    'yogurt': 1.03,
    'chicken broth': 1.0,
    'chicken stock': 1.0,
    'vegetable broth': 1.0,
    'soy sauce': 1.11,
    'vinegar': 1.01,
    'olive oil': 0.918,
    'vegetable oil': 0.92,
    'canola oil': 0.92,
    'butter': 0.911,
    'honey': 1.42,
    'maple syrup': 1.32,
    'molasses': 1.4,
    'peanut butter': 1.08,

    // Dry goods
    'all-purpose flour': 0.528,
    'bread flour': 0.55,
    'whole wheat flour': 0.51,
    'granulated sugar': 0.845,
    'brown sugar': 0.93,
    'powdered sugar': 0.53,
    'cornstarch': 0.51,
    'cocoa powder': 0.42,
    'rolled oats': 0.4,
    'white rice': 0.85,
    'breadcrumbs': 0.42,
    'grated parmesan': 0.4,
    'table salt': 1.22,
    'kosher salt': 0.6,
    'baking soda': 0.92,
    'baking powder': 0.9,
  };

  /// Aliases mapping common ingredient spellings onto a table key.
  static const Map<String, String> _aliases = <String, String>{
    'flour': 'all-purpose flour',
    'plain flour': 'all-purpose flour',
    'ap flour': 'all-purpose flour',
    'sugar': 'granulated sugar',
    'white sugar': 'granulated sugar',
    'caster sugar': 'granulated sugar',
    'confectioners sugar': 'powdered sugar',
    'icing sugar': 'powdered sugar',
    'light brown sugar': 'brown sugar',
    'dark brown sugar': 'brown sugar',
    'salt': 'table salt',
    'evoo': 'olive oil',
    'extra virgin olive oil': 'olive oil',
    'unsalted butter': 'butter',
    'salted butter': 'butter',
    'melted butter': 'butter',
    'whole milk': 'milk',
    'skim milk': 'milk',
    'double cream': 'heavy cream',
    'whipping cream': 'heavy cream',
    'parmesan': 'grated parmesan',
    'parmigiano reggiano': 'grated parmesan',
    'oats': 'rolled oats',
    'rice': 'white rice',
    'cocoa': 'cocoa powder',
    'corn starch': 'cornstarch',
    'cornflour': 'cornstarch',
  };

  /// Normalises an ingredient string for lookup: lowercase, punctuation
  /// stripped, whitespace collapsed.
  static String normalise(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Density for [ingredient] in g/ml, or null when unknown.
  ///
  /// Tries an exact match on the normalised name, then the alias table, then
  /// the longest table key contained in the name — so "freshly grated
  /// parmesan" and "extra virgin olive oil, divided" both resolve.
  static double? lookup(String ingredient) {
    final String key = normalise(ingredient);
    if (key.isEmpty) return null;

    final double? exact = gramsPerMillilitre[key];
    if (exact != null) return exact;

    final String? aliased = _aliases[key];
    if (aliased != null) return gramsPerMillilitre[aliased];

    String? bestKey;
    for (final String candidate in <String>[
      ...gramsPerMillilitre.keys,
      ..._aliases.keys,
    ]) {
      if (!key.contains(candidate)) continue;
      if (bestKey == null || candidate.length > bestKey.length) {
        bestKey = candidate;
      }
    }
    if (bestKey == null) return null;
    return gramsPerMillilitre[bestKey] ??
        gramsPerMillilitre[_aliases[bestKey]!];
  }

  /// True when a real density is known for [ingredient].
  static bool knows(String ingredient) => lookup(ingredient) != null;
}
