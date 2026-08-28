import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the Supabase session is kept between launches (spec §8.4).
///
/// supabase_flutter defaults to SharedPreferences, which on iOS and macOS is a
/// plist in the app container: readable by anything that can read the
/// container, and included in unencrypted backups. §8.4 requires the Keychain
/// instead, so this replaces the default rather than adding to it.
///
/// A refresh token is a long-lived credential for a household's whole
/// library. Losing one is not "log in again"; it is someone else reading your
/// recipes and your logs.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              // Available after the first unlock rather than always: the app
              // needs it in the background to refresh a session, but a device
              // that has not been unlocked since boot should not give it up.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  /// One key, not one per project: this app talks to a single Supabase project
  /// and a stale entry from another would be a session nobody can explain.
  static const String sessionKey = 'hearth.supabase.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: sessionKey)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: sessionKey, value: persistSessionString);
}
