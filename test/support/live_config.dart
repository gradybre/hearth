import 'dart:io';

/// Where the live integration suite points (spec §9.3).
///
/// The *test* project, never the one holding real recipes and logs: these
/// tests write, and a suite that quietly runs against production is one bad
/// afternoon away from being the reason a week of logging disappears.
///
/// Read from gitignored config, never from the repo. The USDA and Claude keys
/// are not here and never pass through the client — that is the whole reason
/// the Edge Functions exist (§8.1).
///
/// Run deliberately:
///
///   HEARTH_LIVE=1 flutter test --tags live test/integration
({String url, String key})? liveConfig() {
  if (Platform.environment['HEARTH_LIVE'] != '1') return null;

  final File file = File('config/hosted-test.json');
  if (!file.existsSync()) return null;

  final String text = file.readAsStringSync();
  final String? url = RegExp('"SUPABASE_URL"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);
  final String? key = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"')
      .firstMatch(text)
      ?.group(1);

  if (url == null || key == null || key.isEmpty) return null;
  return (url: url, key: key);
}

/// Why the suite is being skipped, or null when it can run.
String? liveSkipReason() => liveConfig() == null
    ? 'needs HEARTH_LIVE=1 and config/hosted-test.json with a publishable key'
    : null;
