import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/auth/supabase_auth_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two decisions that between them signed a user out mid-session.
///
/// Brendan lost his place twice: once flipping out of the app and back, once
/// while a food search was running. Both times he landed back on the screen
/// underneath. The cause was here, not in the screens — a signed-out account
/// swaps the whole router out for the sign-in screen, and every pushed route
/// and open sheet goes with it.
class FakeNetworkError implements Exception {
  const FakeNetworkError();
}

void main() {
  group('which auth events change who you are', () {
    test('signing in, out, or changing the user does', () {
      for (final AuthChangeEvent event in <AuthChangeEvent>[
        AuthChangeEvent.signedIn,
        AuthChangeEvent.signedOut,
        AuthChangeEvent.userUpdated,
      ]) {
        expect(
          SupabaseAuthGateway.changesWhoYouAre(event),
          isTrue,
          reason: '$event must re-resolve the account',
        );
      }
    });

    test('a token refresh does not', () {
      // The costly one. Supabase refreshes on resume and on a timer, and every
      // refresh used to trigger a network round trip for the profile — the
      // very round trip that could fail and take the session with it. The
      // token changed; who you are did not.
      expect(
        SupabaseAuthGateway.changesWhoYouAre(AuthChangeEvent.tokenRefreshed),
        isFalse,
      );
    });

    test('neither does anything else routine', () {
      for (final AuthChangeEvent event in <AuthChangeEvent>[
        AuthChangeEvent.initialSession,
        AuthChangeEvent.passwordRecovery,
        AuthChangeEvent.mfaChallengeVerified,
      ]) {
        expect(SupabaseAuthGateway.changesWhoYouAre(event), isFalse);
      }
    });
  });

  group('what a failed account resolve means', () {
    test('the server saying the session is unusable means sign out', () {
      // AuthFailure is raised only when the query *succeeded* and the answer
      // was that there is no household to belong to. That is not transient.
      expect(
        SupabaseAuthGateway.resolutionFor(const AuthFailure('no household')),
        AccountResolution.signOut,
      );
    });

    test('anything else does not', () {
      // This is the bug. Every failure used to sign the user out, so a moment
      // of bad signal during a token refresh threw away the session, swapped
      // the router for the sign-in screen, and destroyed every open route.
      // Being briefly unreachable is the normal condition of a phone.
      for (final Object error in <Object>[
        const FakeNetworkError(),
        StateError('something else entirely'),
      ]) {
        expect(
          SupabaseAuthGateway.resolutionFor(error),
          AccountResolution.keepGoing,
          reason: '$error is not proof the account is gone',
        );
      }
    });
  });

  group('what a refused password reset says (spec §8.3)', () {
    const String neutral =
        'The reset email could not be sent just now. Try again.';

    group('in Settings, where the address is your own', () {
      test('rate limiting is named, so the answer is to wait rather than retry', () {
        // Supabase throttles this endpoint hard. "Something went wrong"
        // would have someone hammering the button being throttled — and
        // here the address is already known to be theirs, so naming the
        // throttle tells them nothing they did not already know.
        for (final String message in <String>[
          'For security purposes, you can only request this after 51 seconds.',
          'Email rate limit exceeded',
          'Too many requests',
        ]) {
          expect(
            SupabaseAuthGateway.readableResetFailure(
              AuthException(message),
              ownAddress: true,
            ),
            contains('Wait a minute'),
            reason: '$message should read as throttling, not as breakage',
          );
        }
      });

      test('a malformed address is said plainly', () {
        expect(
          SupabaseAuthGateway.readableResetFailure(
            const AuthException(
              'Unable to validate email address: invalid format',
            ),
            ownAddress: true,
          ),
          'That does not look like an email address.',
        );
      });

      test('anything else is one message, not a tour of the backend', () {
        for (final String message in <String>[
          'Signups not allowed for this instance',
          'boom',
        ]) {
          expect(
            SupabaseAuthGateway.readableResetFailure(
              AuthException(message),
              ownAddress: true,
            ),
            neutral,
          );
        }
      });
    });

    group('on the sign-in screen, where anyone could have typed it', () {
      test('nothing the endpoint says is repeated back', () {
        // The oracle. GoTrue answers an address with no account with an early
        // 200 — no mail, no error — so *any* refusal that comes back from the
        // endpoint only ever happens for an address that does have one.
        // Repeating one, throttling most of all, turns "Forgot password?"
        // into a way to test whether a stranger is registered: type their
        // address, tap twice inside a minute, read the answer.
        for (final String message in <String>[
          'For security purposes, you can only request this after 51 seconds.',
          'Email rate limit exceeded',
          'Too many requests',
          'User not found',
          'Email not confirmed',
          'Signups not allowed for this instance',
          'boom',
        ]) {
          expect(
            SupabaseAuthGateway.readableResetFailure(
              AuthException(message),
              ownAddress: false,
            ),
            isNull,
            reason: '"$message" would say the address has an account',
          );
        }
      });

      test('a malformed address is still said, being true of any address', () {
        // The format check runs before any account is looked up, so this
        // answer is the same for an address with an account and one without.
        expect(
          SupabaseAuthGateway.readableResetFailure(
            const AuthException(
              'Unable to validate email address: invalid format',
            ),
            ownAddress: false,
          ),
          'That does not look like an email address.',
        );
      });

      test('so is never reaching the server, which is about the phone', () {
        // A request that never arrived says nothing about the address either,
        // and swallowing it would leave someone waiting on an email that was
        // never asked for.
        expect(
          SupabaseAuthGateway.readableResetFailure(
            AuthRetryableFetchException(),
            ownAddress: false,
          ),
          neutral,
        );
      });
    });
  });
}
