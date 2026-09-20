/// How a mass ("weight") quantity should be shown to the reader.
///
/// `automatic` is deliberately not the same thing as "always show pounds":
/// most packaged foods are labelled in whichever unit the package itself
/// uses, and a recipe author who wrote "28 oz" chose that word on purpose.
/// The other two modes exist for surfaces that want to override that —
/// a unit-converter tool pinned to ounces, or a display that always wants
/// the promote/demote ladder regardless of what was typed.
enum MassDisplayMode {
  /// Prefer a compatible mass pack-size hint, then an explicit package unit,
  /// then an authored ounce reading (kept as-is, never promoted to pounds),
  /// and only then fall back to the ordinary promote/demote ladder.
  automatic,

  /// Always show ounces, regardless of magnitude.
  ounces,

  /// Always run the promote/demote ladder (oz <-> lb), ignoring any
  /// authored-ounce preservation that `automatic` would otherwise apply.
  weight;

  /// The short string persisted to storage.
  String toStorage() => switch (this) {
    MassDisplayMode.automatic => 'automatic',
    MassDisplayMode.ounces => 'ounces',
    MassDisplayMode.weight => 'weight',
  };

  /// Parses a persisted value. Anything unrecognised — including null, from
  /// older data that never had this field — defaults to [automatic] rather
  /// than failing to load.
  static MassDisplayMode fromStorage(String? value) => switch (value) {
    'ounces' => MassDisplayMode.ounces,
    'weight' => MassDisplayMode.weight,
    _ => MassDisplayMode.automatic,
  };
}
