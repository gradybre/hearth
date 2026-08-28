import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/auth/secure_session_storage.dart';

/// Brings up anything that must exist before the first frame.
///
/// Supabase is started only when the build was given a configuration. An
/// unconfigured build is a real, supported way to run Hearth — offline, on one
/// device — and it should not die on a missing URL at launch.
Future<bool> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) return false;

  // Rejects a secret key before it can reach a running app, not after.
  Env.assertUsable();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // publishableKey, not anonKey: the legacy JWT anon key is deprecated and
    // is one of the shapes Env refuses outright.
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      // The Keychain, never SharedPreferences — see [SecureSessionStorage]
      // and spec §8.4.
      localStorage: SecureSessionStorage(),
    ),
  );
  return true;
}
