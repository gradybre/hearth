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

  /// Which screen the app opens on — see `LaunchTarget`. Device-local for the
  /// same reason as the theme: where your app opens is not a household
  /// decision.
  static const String launchTarget = 'app.launch_target';

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
