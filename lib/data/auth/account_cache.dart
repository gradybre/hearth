import 'dart:convert';

import '../local/preference_store.dart';
import 'auth_gateway.dart';

/// The last account we successfully resolved, kept on the device.
///
/// Hearth is offline-first and usable alone (spec §5.1), but the account
/// itself was the one thing that always needed the network: the household id
/// lives in a `profiles` row, and without it a cold start on a train put a
/// signed-in user on the sign-in screen with a perfectly good session in the
/// Keychain.
///
/// Device-local and never synced — this is a copy of something the server
/// already owns, not a fact about the household.
class AccountCache {
  AccountCache(this._preferences);

  static const String _key = 'auth.last_account';

  final PreferenceStore _preferences;

  Future<void> remember(HearthAccount account) => _preferences.write(
    _key,
    jsonEncode(<String, Object?>{
      'user_id': account.userId,
      'email': account.email,
      'household_id': account.householdId,
      'share_code': account.shareCode,
      'display_name': account.displayName,
    }),
  );

  Future<void> forget() => _preferences.write(_key, '');

  /// The cached account, but only when it belongs to [userId].
  ///
  /// The guard is the point: signing in as someone else must never inherit the
  /// previous person's household, and a stale cache is exactly how that would
  /// happen.
  Future<HearthAccount?> forUser(String userId) async {
    final String? stored = await _preferences.read(_key);
    if (stored == null || stored.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;

    final String cachedUser = '${decoded['user_id'] ?? ''}';
    final String householdId = '${decoded['household_id'] ?? ''}';
    if (cachedUser != userId || householdId.isEmpty) return null;

    return HearthAccount(
      userId: cachedUser,
      email: '${decoded['email'] ?? ''}',
      householdId: householdId,
      shareCode: decoded['share_code'] as String?,
      displayName: decoded['display_name'] as String?,
    );
  }
}
