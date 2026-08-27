import 'package:hearth/core/env.dart';
import 'package:test/test.dart';

/// Guards the first non-negotiable: the client ships a publishable key and
/// nothing else (spec §8.1).
///
/// Every key-shaped string below is a placeholder carrying an explicit
/// NOT_A_REAL_KEY marker, so a secret scan over the diff can tell a fixture
/// from an actual leak at a glance.
void main() {
  group('forbidden client keys', () {
    test('rejects a new-format secret key', () {
      expect(
        Env.isForbiddenClientKey('sb_secret_EXAMPLE_NOT_A_REAL_KEY'),
        isTrue,
      );
    });

    test('rejects legacy service_role and raw JWTs', () {
      expect(Env.isForbiddenClientKey('service_role_key_here'), isTrue);
      expect(
        Env.isForbiddenClientKey('eyJ.EXAMPLE_NOT_A_REAL_KEY.signature'),
        isTrue,
      );
    });

    test('accepts a publishable key', () {
      expect(
        Env.isForbiddenClientKey('sb_publishable_EXAMPLE_NOT_A_REAL_KEY'),
        isFalse,
      );
    });

    test('ignores surrounding whitespace when judging a key', () {
      // A key pasted from a dashboard often arrives with a stray newline;
      // that must not smuggle a secret past the check.
      expect(
        Env.isForbiddenClientKey('  sb_secret_EXAMPLE_NOT_A_REAL_KEY\n'),
        isTrue,
      );
    });
  });

  group('the compiled-in configuration', () {
    test('never contains a secret key', () {
      // This runs against whatever the test build was given. It is the
      // backstop that would catch a secret key reaching a real bundle.
      expect(
        Env.isForbiddenClientKey(Env.supabasePublishableKey),
        isFalse,
        reason:
            'A secret or legacy key was compiled into the client. Rotate it '
            'immediately and remove it from config/local.json.',
      );
    });

    test('assertUsable explains itself when configuration is missing', () {
      if (Env.isConfigured) return;
      expect(
        Env.assertUsable,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('config/local.json'),
          ),
        ),
      );
    });
  });
}
