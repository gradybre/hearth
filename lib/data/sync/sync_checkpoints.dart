import '../local/preference_store.dart';
import 'sync_scope.dart';

/// Reads and writes the per-table checkpoints, for both sync paths.
///
/// One implementation rather than two: the library and the records need the
/// same three things — a scoped key, the v1 key's disposal, and a way to ask
/// whether the account has changed underneath a pass — and a copy in each
/// would eventually answer differently.
class SyncCheckpoints {
  const SyncCheckpoints({
    required PreferenceStore preferences,
    required SyncScope Function() scope,
  }) : _preferences = preferences,
       _scope = scope;

  final PreferenceStore _preferences;
  final SyncScope Function() _scope;

  /// Whoever is signed in at this instant.
  SyncScope get current => _scope();

  /// Whether the account or household has changed since [captured].
  ///
  /// A pass that began under one session and finishes under another is
  /// receiving somebody else's answers to the first session's questions.
  bool changedSince(SyncScope captured) => _scope() != captured;

  /// How far back this table should be asked about, under [scope].
  ///
  /// Disposes of the unscoped v1 key on the way past. Deleted rather than
  /// migrated: besides belonging to nobody in particular, it may have been
  /// advanced past rows a truncated pull never delivered (R04), so its value
  /// is not trustworthy even for the account that wrote it. One re-read of
  /// the library is the whole cost of being sure.
  Future<DateTime?> since(SyncScope scope, String table) async {
    await _preferences.delete(SyncScope.legacyKeyFor(table));
    final String? stored = await _preferences.read(
      scope.watermarkKeyFor(table),
    );
    return stored == null ? null : DateTime.tryParse(stored)?.toUtc();
  }

  /// Forgets every checkpoint on this device, for every account.
  ///
  /// Called from an explicit sign-out and nowhere else. Scoping already makes
  /// it impossible for one account to read another's checkpoint, so this is
  /// not what keeps them apart — it is the repair lever. A checkpoint only
  /// moves forward, so if the server's copy of a row ever ends up older than
  /// the checkpoint that passed it — a restore from backup, a bug like the
  /// one that wrote local time as UTC — that row can never be asked for
  /// again. "Sign out and back in" is what someone will try, and this is what
  /// makes it mean something.
  ///
  /// Deliberately *not* wired to a session simply expiring: that happens on
  /// its own schedule, and re-downloading the library each time it does would
  /// be a cost nobody asked for.
  Future<void> forgetEverything() =>
      _preferences.deleteWithPrefix(SyncScope.prefix);

  /// Records how far [table] has been read, under the scope that read it.
  Future<void> record(SyncScope scope, String table, DateTime upTo) =>
      _preferences.write(scope.watermarkKeyFor(table), upTo.toIso8601String());
}
