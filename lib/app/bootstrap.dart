import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/auth/secure_session_storage.dart';
import '../data/local/hearth_database.dart';
import '../data/local/preference_store.dart';
import 'shell/launch_target.dart';
import 'theme/theme_choice.dart';

/// What the app has in hand before its first frame.
class Boot {
  const Boot({
    required this.connected,
    required this.database,
    required this.theme,
    required this.launchTarget,
    required this.daySummaryExpanded,
  });

  /// Whether Supabase was configured and started.
  final bool connected;

  /// Opened here rather than left to the provider, because [theme] is read
  /// out of it before anything is painted and a second connection to the same
  /// file would be one open too many.
  final HearthDatabase database;

  /// The stored light/dark choice (spec §6.1).
  final ThemeChoice theme;

  /// The screen the app was told to open on (spec §6.2). Read here for a
  /// louder version of [theme]'s reason: the router is built with a starting
  /// route, and a route decided after the first frame means watching the home
  /// screen appear and then be replaced.
  final LaunchTarget launchTarget;

  /// Whether the day's summary opens on its rings (spec §5.6). Same reason
  /// again, and it is worth about 170 points: a value that arrives a frame
  /// late means the card renders compact and then jumps, under the thumb of
  /// somebody about to log a meal.
  final bool daySummaryExpanded;
}

/// Brings up anything that must exist before the first frame.
///
/// Supabase is started only when the build was given a configuration. An
/// unconfigured build is a real, supported way to run Hearth — offline, on one
/// device — and it should not die on a missing URL at launch.
Future<Boot> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read here, before the first frame, and not from the provider that owns it:
  // that read is a Drift open plus a query, and until it returned the app
  // painted ThemeMode.system — so a dark-mode user watched it flash cream on
  // every cold start.
  final HearthDatabase database = HearthDatabase();
  ThemeChoice theme = ThemeChoice.system;
  LaunchTarget launchTarget = LaunchTarget.home;
  bool daySummaryExpanded = false;
  try {
    final PreferenceStore preferences = PreferenceStore(database);
    theme = ThemeChoice.parse(
      await preferences.read(PreferenceStore.themeChoice),
    );
    launchTarget = LaunchTarget.parse(
      await preferences.read(PreferenceStore.launchTarget),
    );
    daySummaryExpanded = await preferences.readFlag(
      PreferenceStore.daySummaryExpanded,
    );
  } on Object {
    // A local cache that cannot be read is a real problem, but it is not this
    // function's to report: failing here would replace the app with a blank
    // screen over a preference. Follow the device, open on the home screen,
    // and let the failure surface where the data is actually needed.
  }

  if (!Env.isConfigured) {
    return Boot(
      connected: false,
      database: database,
      theme: theme,
      launchTarget: launchTarget,
      daySummaryExpanded: daySummaryExpanded,
    );
  }

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
  return Boot(
    connected: true,
    database: database,
    theme: theme,
    launchTarget: launchTarget,
    daySummaryExpanded: daySummaryExpanded,
  );
}
