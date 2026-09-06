import '../local/preference_store.dart';
import 'sync_scope.dart';

/// What a pass captured about itself before it asked its first question.
///
/// Two things, because two different events invalidate a pass in flight: the
/// account changing underneath it, and someone deliberately clearing the
/// checkpoints while it runs.
class SyncPass {
  const SyncPass({required this.scope, required this.clearings});

  final SyncScope scope;

  /// How many times the checkpoints had been deliberately forgotten when this
  /// pass began. A sign-out that clears them mid-pass would otherwise be
  /// undone the moment the pass finished and wrote its checkpoint back — the
  /// repair lever silently doing nothing, which is worse than not having one.
  final int clearings;
}

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

  /// Opens a pass. Everything it later checks itself against is read here,
  /// before the first request goes out.
  Future<SyncPass> begin() async =>
      SyncPass(scope: _scope(), clearings: await _clearings());

  /// Whether [pass] is still the pass that started.
  ///
  /// A pass that began under one session and finishes under another is
  /// receiving somebody else's answers to the first session's questions. A
  /// pass that outlived a deliberate clearing would put back the very
  /// checkpoint that clearing existed to remove.
  Future<bool> hasEnded(SyncPass pass) async =>
      _scope() != pass.scope || await _clearings() != pass.clearings;

  /// How far back this table should be asked about, under [pass]'s scope.
  ///
  /// Disposes of the unscoped v1 key on the way past. Deleted rather than
  /// migrated: besides belonging to nobody in particular, it may have been
  /// advanced past rows a truncated pull never delivered (R04), so its value
  /// is not trustworthy even for the account that wrote it. One re-read of
  /// the library is the whole cost of being sure.
  Future<DateTime?> since(SyncPass pass, String table) async {
    await _preferences.delete(SyncScope.legacyKeyFor(table));
    final String? stored = await _preferences.read(
      pass.scope.watermarkKeyFor(table),
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
  Future<void> forgetEverything() async {
    final int clearings = await _clearings();
    await _preferences.deleteWithPrefix(SyncScope.prefix);
    // Counted outside the swept prefix, and after the sweep, so a pass
    // already in flight sees the count move and abandons rather than writing
    // its checkpoint back over the clearing.
    await _preferences.write(_clearingsKey, '${clearings + 1}');
  }

  /// Kept outside [SyncScope.prefix] deliberately: the sweep must not erase
  /// its own record of having happened.
  static const String _clearingsKey = 'sync.checkpoints_cleared';

  Future<int> _clearings() async =>
      int.tryParse(await _preferences.read(_clearingsKey) ?? '') ?? 0;

  /// Records how far [table] has been read, under the scope that read it.
  Future<void> record(SyncPass pass, String table, DateTime upTo) =>
      _preferences.write(
        pass.scope.watermarkKeyFor(table),
        upTo.toIso8601String(),
      );
}
