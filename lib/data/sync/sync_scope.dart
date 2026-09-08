/// Whose data a sync pass is for.
///
/// A checkpoint is only meaningful next to the identity that earned it. The
/// first version of these keys was `sync.watermark.<table>` and carried no
/// identity at all, so a device that signed in as someone else inherited the
/// previous account's checkpoint — and because a checkpoint only ever moves
/// forward, everything the new account had written *before* that moment was
/// never asked for again. Not late: never.
///
/// Household as well as user: accepting an invitation to a different
/// household changes which library the server will hand over, and a
/// checkpoint from the old one would skip the new one's history the same way.
class SyncScope {
  const SyncScope({required this.userId, required this.householdId});

  /// Everything this class has ever written, so a sweep can find all of it
  /// including the unscoped keys from before there was a version.
  static const String prefix = 'sync.watermark.';

  /// The unscoped key this replaces. Read once, to be deleted rather than
  /// trusted — see [legacyKeyFor].
  static String legacyKeyFor(String table) => '$prefix$table';

  final String userId;
  final String householdId;

  /// Versioned as well as scoped. A v1 key cannot simply be re-read under a
  /// new name: it may have advanced past rows a truncated pull never
  /// delivered (R04), so its value is not trustworthy even for the account
  /// that wrote it.
  String watermarkKeyFor(String table) =>
      '${prefix}v2.$userId.$householdId.$table';

  /// Where the last fully-successful pass is remembered. Scoped for the same
  /// reason the watermarks are: it is a fact about this account on this
  /// device, and inheriting it across a sign-in would be reporting somebody
  /// else's sync as your own.
  ///
  /// The `#` is not decoration: without it this is exactly what
  /// `watermarkKeyFor('full-pass')` produces, and two different facts sharing
  /// a key is the kind of thing that is obvious only after it has happened.
  /// No table is called that today, which is the whole reason to spend one
  /// character on making it impossible rather than unlikely.
  String get lastFullPassKey => '${prefix}v2.$userId.$householdId.#full-pass';

  @override
  bool operator ==(Object other) =>
      other is SyncScope &&
      other.userId == userId &&
      other.householdId == householdId;

  @override
  int get hashCode => Object.hash(userId, householdId);

  @override
  String toString() => 'SyncScope($userId, $householdId)';
}
