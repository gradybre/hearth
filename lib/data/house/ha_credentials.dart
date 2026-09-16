/// Where a Home Assistant token lives, and what it is bound to
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.2, spec §11).
///
/// A long-lived access token is a bearer credential for somebody's house: the
/// lights, the plugs, and every camera Home Assistant can see. It is also a
/// **different kind of secret** from the ones `CLAUDE.md` rule 1 governs. Rule
/// 1 is about keys Hearth ships — the publishable key in the bundle, the
/// service key that must never be there. This one is typed in by the person
/// using the app, at runtime, and never exists in the repository at all. The
/// rules that apply to it are therefore about *storage and lifetime* rather
/// than about what may be committed.
///
/// Three things this class exists to guarantee:
///
///  1. **It is never in the ordinary preference store.** `PreferenceStore`
///     writes to SQLite, which is on disk in the clear and goes into a
///     backup. §5.2 names that specifically: no globally shared
///     `home_assistant_token` preference.
///  2. **It is keyed apart from the Supabase session.** A different key in the
///     same keychain, so signing out of Hearth and losing a house are separate
///     events, and neither can silently take the other with it.
///  3. **It is bound to a context.** Hearth user, household, and a local
///     connection id. §5.2 requires that an account change, a household
///     change, or a disconnect tears down the old context's credentials — and
///     you cannot tear down what you cannot name.
///
/// What it deliberately does *not* do is fall back. If the keychain refuses,
/// that is an error the setup screen shows, not a reason to put a bearer token
/// somewhere easier to read.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

/// Which Hearth context a credential belongs to.
///
/// All three parts matter. The user and household are Hearth's own identities
/// — the same phone signed in as somebody else must not reach the first
/// person's house. The connection id is local and lets one installation hold a
/// credential per configured server without them colliding, which is what
/// makes "replace the token" a safe operation: the new one is written under a
/// new id and the old one deleted only once the new one validates.
@immutable
class HaCredentialScope {
  const HaCredentialScope({
    required this.userId,
    required this.householdId,
    required this.connectionId,
  });

  final String userId;
  final String householdId;
  final String connectionId;

  /// The keychain key for this scope.
  ///
  /// Prefixed so [HaCredentialStore.forgetEverything] can find every Home
  /// Assistant credential without touching the Supabase session beside them,
  /// and segmented so a partial prefix names a whole user or a whole
  /// household — which is exactly what sign-out and household-change need.
  String get key => '$_prefix$userId/$householdId/$connectionId';

  /// Every credential for one signed-in person, whatever household.
  static String userPrefix(String userId) => '$_prefix$userId/';

  /// Every credential for one person in one household.
  static String householdPrefix(String userId, String householdId) =>
      '$_prefix$userId/$householdId/';

  /// The root. Nothing else in the keychain begins with this.
  static const String _prefix = 'hearth.ha.token/';

  /// The prefix as the store sees it, for callers that need to sweep.
  static String get allPrefix => _prefix;

  @override
  bool operator ==(Object other) =>
      other is HaCredentialScope &&
      other.userId == userId &&
      other.householdId == householdId &&
      other.connectionId == connectionId;

  @override
  int get hashCode => Object.hash(userId, householdId, connectionId);

  /// Never the token. A scope is safe to log; what it points at is not, and
  /// keeping them in separate types is what makes that distinction hold.
  @override
  String toString() => 'HaCredentialScope($userId/$householdId/$connectionId)';
}

/// Raised when secure storage will not cooperate.
///
/// §4.1: losing secure-storage access must fail clearly, and a credential must
/// never be quietly written somewhere ordinary instead. So this is thrown
/// rather than swallowed, and the setup screen turns it into a sentence.
///
/// [toString] deliberately carries no token and no platform detail that could
/// contain one — §4.1 also says no token echo in errors.
class HaCredentialException implements Exception {
  const HaCredentialException(this.message);

  final String message;

  @override
  String toString() => 'HaCredentialException: $message';
}

/// The four operations this store needs from a keychain.
///
/// A port of Hearth's own rather than the plugin's interface (rule 7). Two
/// reasons, and the second is the one that matters: a narrow seam is trivial
/// to fake in a test, and `flutter_secure_storage` changes the shape of its
/// per-platform options between majors — coupling every caller and every test
/// to that is how a dependency bump turns into a day.
abstract interface class HaSecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// The real one: the platform keychain.
class KeychainVault implements HaSecretVault {
  KeychainVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              // Matches `SecureSessionStorage`: available after first unlock
              // rather than always. Hearth may need to reconnect to the house
              // while backgrounded, but a device that has not been unlocked
              // since boot should not give up a bearer token for it.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// Reads and writes Home Assistant tokens, and nothing else.
///
/// Deliberately not a general-purpose secret store: a type that can hold any
/// secret ends up holding several, and the sweeping operations below would
/// then be dangerous rather than useful.
class HaCredentialStore {
  HaCredentialStore({HaSecretVault? vault}) : _vault = vault ?? KeychainVault();

  final HaSecretVault _vault;

  /// The token for this scope, or null when there is none.
  Future<String?> read(HaCredentialScope scope) async {
    try {
      return await _vault.read(scope.key);
    } on Object catch (error) {
      throw HaCredentialException(_describe(error, 'read'));
    }
  }

  /// Stores [token] against [scope], replacing whatever was there.
  ///
  /// Refuses an empty token rather than storing one: an empty string reads
  /// back as a present credential and fails at the server with an
  /// authentication error, which sends somebody looking in the wrong place.
  Future<void> write(HaCredentialScope scope, String token) async {
    if (token.isEmpty) {
      throw const HaCredentialException('There is no token to save.');
    }
    try {
      await _vault.write(scope.key, token);
    } on Object catch (error) {
      throw HaCredentialException(_describe(error, 'save'));
    }
  }

  /// Removes one connection's token.
  ///
  /// This is local only. §4.1 and §5.2 are emphatic that deleting a
  /// long-lived token here does **not** revoke it in Home Assistant, and the
  /// screen that calls this has to say where to do that rather than implying
  /// it is done.
  Future<void> forget(HaCredentialScope scope) async {
    try {
      await _vault.delete(scope.key);
    } on Object catch (error) {
      throw HaCredentialException(_describe(error, 'remove'));
    }
  }

  /// Removes every token under [prefix].
  ///
  /// The sweep sign-out and household changes need. Takes a prefix rather than
  /// deleting everything, because the Supabase session lives in the same
  /// keychain and must survive a household change — and `deleteAll()` would
  /// take it.
  Future<void> forgetEverything(String prefix) async {
    assert(
      prefix.startsWith(HaCredentialScope.allPrefix),
      'a sweep outside the Home Assistant prefix would take the Supabase '
      'session with it',
    );
    try {
      final Map<String, String> all = await _vault.readAll();
      for (final String key in all.keys) {
        if (key.startsWith(prefix)) await _vault.delete(key);
      }
    } on Object catch (error) {
      throw HaCredentialException(_describe(error, 'remove'));
    }
  }

  /// A sentence for a person, carrying nothing from the underlying error.
  ///
  /// The platform exception can quote the value it was handling. Rethrowing it
  /// verbatim is how a bearer token reaches a crash report, so only the verb
  /// survives.
  static String _describe(Object error, String verb) =>
      'Hearth could not $verb the Home Assistant token securely on this '
      'device. It has not been saved anywhere else.';
}
