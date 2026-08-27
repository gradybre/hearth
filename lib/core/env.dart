/// Compile-time configuration, supplied by
/// `--dart-define-from-file=config/local.json`.
///
/// Only two values ever live here, and both are public by design: the project
/// URL and the `sb_publishable_…` key. RLS is what protects the data behind
/// them (spec §8.1). The secret key, the Claude API key, and USDA keys live in
/// Edge Function secrets and must never reach this file, the repo, or a
/// built bundle.
library;

abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Prefixes that must never appear in a client bundle.
  ///
  /// `sb_secret_` is the new-format secret key; `service_role` and a bare JWT
  /// are the legacy shapes. Any of them in the client would bypass RLS
  /// entirely and hand every household's data to anyone who unzipped the app.
  static const List<String> forbiddenKeyPrefixes = <String>[
    'sb_secret_',
    'service_role',
    'eyJ', // a raw JWT — legacy anon/service_role keys look like this
  ];

  /// Whether [key] looks like something that must not ship in the client.
  static bool isForbiddenClientKey(String key) {
    final String trimmed = key.trim();
    return forbiddenKeyPrefixes.any(trimmed.startsWith);
  }

  /// Fails fast at startup rather than letting a misconfigured build reach a
  /// user, or a secret key reach a bundle.
  static void assertUsable() {
    if (!isConfigured) {
      throw StateError(
        'Supabase configuration is missing. Run with '
        '--dart-define-from-file=config/local.json (see config/example.json).',
      );
    }
    if (isForbiddenClientKey(supabasePublishableKey)) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY looks like a secret or legacy key. The '
        'client ships only sb_publishable_… — a secret key here would bypass '
        'RLS for anyone who opened the bundle. Rotate it immediately if this '
        'value has been committed or distributed.',
      );
    }
  }
}
