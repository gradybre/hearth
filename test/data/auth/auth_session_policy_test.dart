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
}
