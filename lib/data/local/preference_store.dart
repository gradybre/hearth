import 'package:drift/drift.dart';

import 'hearth_database.dart';

/// Reads and writes small device-local settings.
///
/// Deliberately not synced: these are choices about how the app is set up on
/// the device in your hand, and pushing them to a partner would change their
/// screen for no reason they could see.
class PreferenceStore {
  PreferenceStore(this._db);

  /// Whether cook-along last showed every step at once.
  static const String cookShowAllSteps = 'cook.show_all_steps';

  /// Light, dark, or whatever the device is doing — see `ThemeChoice`.
  static const String themeChoice = 'app.theme_choice';

  /// Whether the day's summary shows its rings and bars, or the compact
  /// readout (spec §5.6).
  ///
  /// Device-local, like the theme: how much of the summary you want to see
  /// before the meals is a choice about the screen in your hand, and pushing
  /// it to a partner would rearrange their day for no reason they could see.
  static const String daySummaryExpanded = 'plan.day_summary_expanded';

  /// Which screen the app opens on — see `LaunchTarget`. Device-local for the
  /// same reason as the theme: where your app opens is not a household
  /// decision.
  static const String launchTarget = 'app.launch_target';

  /// Which unit a food's portion was last typed in, one key per food id
  /// (review F06). Device-local for the same reason again: whether you weigh
  /// in grams or count pots is a habit of the phone in your hand.
  ///
  /// A prefix, not a key. Values are `PortionUnit.id` — `unit:g`,
  /// `serving:pot` — which is why they are stable identifiers and not labels:
  /// a food's serving can be renamed.
  static const String logUnitForFood = 'plan.log_unit.food.';

  /// And which unit one *entry* was typed in, one key per entry id, written
  /// only when it was not the default serving.
  ///
  /// A different question from [logUnitForFood] and deliberately never
  /// answered by it: an entry logged in ounces must re-open in ounces, not in
  /// whatever that food has been typed in since. The entry row cannot say so
  /// itself — `servings` is a count of the default serving and nothing else.
  ///
  /// These rows outlive the entries that made them, because entries are
  /// soft-deleted and restorable (non-negotiable 3): clearing one on removal
  /// would mean an undo brought the meal back in the wrong unit. One short
  /// row per portion ever typed in something other than the default.
  static const String logUnitForEntry = 'plan.log_unit.entry.';

  final HearthDatabase _db;

  Future<String?> read(String key) async {
    final PreferenceRow? row = await (_db.select(
      _db.preferences,
    )..where(($PreferencesTable p) => p.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<bool> readFlag(String key, {bool orElse = false}) async =>
      switch (await read(key)) {
        'true' => true,
        'false' => false,
        _ => orElse,
      };

  Future<void> write(String key, String value) => _db
      .into(_db.preferences)
      .insertOnConflictUpdate(PreferenceRow(key: key, value: value));

  Future<void> delete(String key) => (_db.delete(
    _db.preferences,
  )..where(($PreferencesTable p) => p.key.equals(key))).go();

  /// Every key beginning with [prefix]. Used to forget a whole family of
  /// settings at once rather than naming each of them.
  Future<void> deleteWithPrefix(String prefix) => (_db.delete(
    _db.preferences,
  )..where(($PreferencesTable p) => p.key.like('$prefix%'))).go();

  Future<void> writeFlag(String key, {required bool value}) =>
      write(key, value ? 'true' : 'false');
}
