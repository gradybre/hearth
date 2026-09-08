import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_cache.dart';
import 'auth_gateway.dart';
import 'password_recovery.dart';

/// The real accounts implementation, on Supabase Auth (spec §8.3).
///
/// Nothing here hashes a password or mints a token: Supabase does that, and
/// rolling our own is the one thing §8.3 rules out by name.
/// What to do when the account cannot be resolved.
enum AccountResolution {
  /// The server answered, and the answer was that this session is unusable.
  signOut,

  /// Something went wrong that says nothing about the account — carry on with
  /// what we already knew.
  keepGoing,
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(
    this._client, {
    AccountCache? cache,
    PasswordRecovery? recovery,
    String? recoveryRedirect,
  }) : _cache = cache,
       _recovery = recovery,
       _recoveryRedirect = recoveryRedirect {
    _authChanges = _client.auth.onAuthStateChange.listen((AuthState state) {
      // Before the refresh below, deliberately. A recovery link *signs the
      // user in* — the account resolves and the gate opens — so the fact that
      // this session exists only to set a password has to be recorded before
      // anything acts on the session itself.
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _recovery?.begin();
      }
      if (changesWhoYouAre(state.event)) _refresh();
    });
  }

  /// Whether an auth event means the account itself may have changed.
  ///
  /// Deliberately narrow. A token refresh fires on resume and on a timer, and
  /// re-resolving on it meant a network round trip for the profile every time
  /// — which is the round trip that could fail and take the session down with
  /// it. The token changed; who you are did not.
  static bool changesWhoYouAre(AuthChangeEvent event) => switch (event) {
    AuthChangeEvent.signedIn ||
    AuthChangeEvent.signedOut ||
    AuthChangeEvent.userUpdated => true,
    _ => false,
  };

  /// What a failure to resolve the account actually tells us.
  ///
  /// Only [AuthFailure] means the account is gone: it is raised when the
  /// profile query *succeeded* and said there is no household to belong to.
  /// Everything else — a socket closing, a timeout, a 500 — is the phone being
  /// briefly unreachable, which is its normal condition and no reason to throw
  /// away a session.
  ///
  /// This used to sign out on anything at all. A moment of bad signal during a
  /// token refresh would clear the session, swap the router for the sign-in
  /// screen, and destroy every pushed route and open sheet with it.
  static AccountResolution resolutionFor(Object error) => error is AuthFailure
      ? AccountResolution.signOut
      : AccountResolution.keepGoing;

  final SupabaseClient _client;

  /// Where the last good account is kept so a cold start without signal can
  /// still get in. Null in builds that have no local database to write to.
  final AccountCache? _cache;
  final PasswordRecovery? _recovery;

  /// Where a recovery link should land, when the project has been told to
  /// allow it. Null is the shipped default and means the project's own page.
  final String? _recoveryRedirect;

  /// Pushed to whenever the account may have changed.
  ///
  /// Auth events are not the only thing that changes it: joining a household
  /// moves the user without touching their session, and a screen still holding
  /// the old account would go on showing the *previous* household's share
  /// code — a code that now sends whoever types it somewhere else entirely.
  final StreamController<HearthAccount?> _accounts =
      StreamController<HearthAccount?>.broadcast();
  late final StreamSubscription<AuthState> _authChanges;

  @override
  Stream<HearthAccount?> watchAccount() async* {
    // The account as it stands, before waiting for anything to happen to it:
    // a fresh listener must not sit on a spinner until the next auth event.
    yield await _accountOrSignOut();
    yield* _accounts.stream;
  }

  /// The last account we successfully resolved, so a blip does not look like a
  /// sign-out.
  HearthAccount? _lastKnown;

  Future<void> _refresh() async {
    if (_accounts.isClosed) return;
    _accounts.add(await _accountOrSignOut());
  }

  /// The account, or null after clearing a session the server says is unusable.
  ///
  /// A failure to read the profile is almost always the network, and treating
  /// it as proof the account is gone is how a bad moment of signal becomes a
  /// sign-out. Only [AuthFailure] — the query answering that there is no
  /// household — clears the session; anything else keeps the last account we
  /// actually saw.
  Future<HearthAccount?> _accountOrSignOut() async {
    try {
      final HearthAccount? account = await currentAccount();
      _lastKnown = account;
      if (account != null) {
        await _cache?.remember(account);
      } else {
        await _cache?.forget();
      }
      return account;
    } on Object catch (error) {
      switch (resolutionFor(error)) {
        case AccountResolution.signOut:
          _lastKnown = null;
          await _cache?.forget();
          await _client.auth.signOut();
          return null;
        case AccountResolution.keepGoing:
          // In-memory first, then the device. The cache is what carries a
          // signed-in user through a cold start with no signal — the session
          // is in the Keychain, and the only thing missing is the household
          // id, which we already knew last time.
          final String? userId = _client.auth.currentUser?.id;
          if (_lastKnown != null || userId == null) return _lastKnown;
          return _lastKnown = await _cache?.forUser(userId);
      }
    }
  }

  void dispose() {
    _authChanges.cancel();
    _accounts.close();
  }

  @override
  Future<HearthAccount?> currentAccount() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    return _accountFor(user);
  }

  @override
  Future<HearthAccount?> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final User? user = response.user;
      // No session means the project requires confirmation: the account
      // exists but nobody is signed in yet. That is not a failure.
      if (user == null || response.session == null) return null;
      return await _accountFor(user);
    } on AuthException catch (error) {
      throw AuthFailure(_readable(error));
    }
  }

  @override
  Future<HearthAccount> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final User? user = response.user;
      if (user == null) {
        throw const AuthFailure('That did not sign you in. Try again.');
      }
      return await _accountFor(user);
    } on AuthException catch (error) {
      throw AuthFailure(_readable(error));
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Sends the reset email (spec §8.3 — Supabase Auth owns the credential).
  ///
  /// **No `redirectTo` on purpose.** The link therefore lands on whatever the
  /// project has as its Site URL, in a browser. Passing a deep link Hearth
  /// cannot yet answer — nothing listens for
  /// `AuthChangeEvent.passwordRecovery`, and no scheme is registered outside
  /// iOS — would produce a link that looks right and goes nowhere, which is
  /// worse than one that plainly goes to the project's own page. Both screens
  /// say as much rather than promising an in-app step that does not exist.
  /// Finishing the loop in-app means: allow-listing a redirect in the
  /// Supabase dashboard, registering the scheme on macOS and Windows, and a
  /// screen that calls `updateUser(password:)` on the recovery session.
  ///
  /// A missing account is not an error here, by design: Supabase answers an
  /// unknown address with an early 200, so nothing this returns says whether
  /// an address is registered. See [readableResetFailure] for what that costs
  /// on the signed-out path, and for the one channel it does not close.
  @override
  Future<void> setPassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      // The project's own policy, said as it said it: a length or strength
      // rule belongs to the project, and repeating it here would be a second
      // copy that eventually disagrees with the one being enforced.
      throw AuthFailure(error.message);
    }
    // The session stays, and that is deliberate: they are signed in on this
    // device, having just proved they can read the account's email. Signing
    // them out to make them type the password they set eight seconds ago
    // would be ceremony, not security.
  }

  @override
  Future<void> sendPasswordReset(
    String email, {
    bool ownAddress = false,
  }) async {
    try {
      // Sent only when there is somewhere allow-listed for it to go. An
      // unconfigured build asks for the same email it always did, landing on
      // the project's own page — because a `redirectTo` the dashboard has not
      // been told about produces a link that looks right and goes nowhere,
      // which is worse than one that plainly goes elsewhere.
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _recoveryRedirect,
      );
    } on AuthException catch (error) {
      final String? readable = readableResetFailure(
        error,
        ownAddress: ownAddress,
      );
      // Null means saying anything at all would answer whether that address
      // has an account. The caller then reports what it reports for a request
      // that went through — which is all the endpoint is willing to say
      // either way.
      if (readable != null) throw AuthFailure(readable);
    }
  }

  @override
  Future<HearthAccount> joinHousehold(String shareCode) async {
    try {
      // An RPC, not a table write: the joiner cannot see the household through
      // RLS until they belong to it, and the function takes a code rather than
      // an id so it cannot be used to probe for one.
      await _client.rpc<void>(
        'join_household',
        params: <String, Object?>{'p_share_code': shareCode},
      );
    } on PostgrestException catch (error) {
      throw AuthFailure(_readableJoin(error));
    }

    final HearthAccount? account = await currentAccount();
    if (account == null) {
      throw const AuthFailure('You are no longer signed in.');
    }
    // Tell everyone watching: the household changed without an auth event.
    if (!_accounts.isClosed) _accounts.add(account);
    return account;
  }

  /// Reads the profile row that the signup trigger created.
  Future<HearthAccount> _accountFor(User user) async {
    final Map<String, dynamic>? profile = await _client
        .from('profiles')
        .select('household_id, display_name, households(share_code)')
        .eq('id', user.id)
        .maybeSingle();

    final String? householdId = profile?['household_id'] as String?;
    if (householdId == null) {
      // The trigger makes one on signup, so this means the row has not landed
      // yet or something is wrong with the project — either way, saying so
      // beats handing the app a null it will scatter through every query.
      throw const AuthFailure(
        'Your household could not be loaded. Try signing in again.',
      );
    }

    final Object? household = profile?['households'];
    return HearthAccount(
      userId: user.id,
      email: user.email ?? '',
      householdId: householdId,
      shareCode: household is Map<String, dynamic>
          ? household['share_code'] as String?
          : null,
      displayName: profile?['display_name'] as String?,
    );
  }

  /// Supabase writes for developers; the user gets the same fact in their own
  /// language, and never a hint about which half was wrong.
  static String _readable(AuthException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'There is already an account with that email.';
    }
    if (message.contains('email not confirmed')) {
      return 'Check your email and confirm the address first.';
    }
    if (message.contains('password')) {
      // The project's own policy is the authority on length and characters,
      // so its wording is passed through rather than second-guessed.
      return error.message;
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts just now. Wait a minute and try again.';
    }
    return 'Something went wrong signing you in. Try again.';
  }

  /// Why the reset email could not even be asked for — or null when saying
  /// would answer a question this flow refuses to answer.
  ///
  /// Public where its siblings are private because it is the one that carries
  /// a decision worth pinning down in a test.
  ///
  /// [ownAddress] is true only where the address is already known to belong to
  /// the person asking: the Settings row, which sends to the account they are
  /// signed in as. There, naming the throttle tells them nothing they did not
  /// already know, and "wait a minute" is the difference between waiting and
  /// hammering a button that is being throttled.
  ///
  /// On the sign-in screen the address is whatever was typed, and the rule
  /// inverts. GoTrue answers an address with no account with an early 200 — no
  /// mail, no error — so *every* refusal that comes back from the endpoint can
  /// only have happened for an address that has one. Repeating any of them
  /// there, the per-user throttle most of all ("you can only request this
  /// after 51 seconds"), turns "Forgot password?" into a way to test whether a
  /// stranger is registered: type their address, tap twice inside a minute,
  /// read the reply. Two failures happen before any account is looked up and
  /// read the same for every address, so those are still said: a malformed
  /// address, and never reaching the server at all.
  ///
  /// This closes the message channel, not the timing one: the existing-account
  /// path does its SMTP work inside the request, so it answers measurably
  /// slower than the early 200 for an address with no account. That is
  /// GoTrue's shape and cannot be fixed from here.
  static String? readableResetFailure(
    AuthException error, {
    required bool ownAddress,
  }) {
    final String message = error.message.toLowerCase();
    final bool malformed =
        message.contains('invalid') && message.contains('email');
    final bool throttled =
        message.contains('rate limit') ||
        message.contains('too many') ||
        message.contains('security purposes');
    // Never reached the endpoint, so nothing about the address was learned —
    // and swallowing it would leave someone waiting on an email that was
    // never asked for.
    final bool neverArrived = error is AuthRetryableFetchException;

    if (malformed) return 'That does not look like an email address.';
    if (throttled && ownAddress) {
      return 'That has been asked for a few times just now. Wait a minute '
          'and try again.';
    }
    if (!ownAddress && !neverArrived) return null;
    return 'The reset email could not be sent just now. Try again.';
  }

  static String _readableJoin(PostgrestException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('no household matches')) {
      return 'No household matches that code. Check it and try again.';
    }
    if (message.contains('not authenticated')) {
      return 'You are no longer signed in.';
    }
    return 'That code could not be used just now. Try again.';
  }
}
