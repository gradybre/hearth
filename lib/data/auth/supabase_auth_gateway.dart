import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';

/// The real accounts implementation, on Supabase Auth (spec §8.3).
///
/// Nothing here hashes a password or mints a token: Supabase does that, and
/// rolling our own is the one thing §8.3 rules out by name.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client) {
    _authChanges = _client.auth.onAuthStateChange.listen(
      (AuthState _) => _refresh(),
    );
  }

  final SupabaseClient _client;

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
    yield await currentAccount();
    yield* _accounts.stream;
  }

  Future<void> _refresh() async {
    if (_accounts.isClosed) return;
    try {
      _accounts.add(await currentAccount());
    } on AuthFailure catch (error) {
      _accounts.addError(error);
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
