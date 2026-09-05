import 'package:meta/meta.dart';

/// Who is signed in, and what household they belong to.
///
/// The household id is carried alongside the user because every
/// household-scoped read needs it and re-reading the profile per query would
/// be a round trip for a value that changes about twice in an app's life.
@immutable
class HearthAccount {
  const HearthAccount({
    required this.userId,
    required this.email,
    required this.householdId,
    this.shareCode,
    this.displayName,
  });

  final String userId;
  final String email;

  /// Every user has one from the moment they sign up: a solo user is a
  /// household of one, and the app is usable before anyone links (spec §5.1).
  final String householdId;

  /// The code a partner types to join. Only the household's own members can
  /// read it.
  final String? shareCode;

  final String? displayName;
}

/// Something the user did wrong, phrased for the user.
///
/// Supabase's own messages are written for developers ("Invalid login
/// credentials", "User already registered"); these are the same facts said
/// the way a person would say them.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accounts and household membership (spec §5.1, §8.3).
///
/// An interface because the app has to run without a backend at all — widget
/// tests, and any build with no `config/local.json` — and because auth is
/// exactly the kind of thing that must be exercisable without a network.
abstract interface class AuthGateway {
  /// The signed-in account, re-emitted on every sign-in and sign-out. Null
  /// when nobody is signed in.
  Stream<HearthAccount?> watchAccount();

  /// The account as it stands right now, without waiting for the stream.
  Future<HearthAccount?> currentAccount();

  /// Creates the account. The database gives every new user their own
  /// household, so there is nothing to choose here (spec §5.1).
  ///
  /// Returns null when the project requires email confirmation and the user
  /// therefore is not signed in yet — the caller shows "check your email"
  /// rather than treating it as a failure.
  Future<HearthAccount?> signUp({
    required String email,
    required String password,
  });

  Future<HearthAccount> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  /// Asks the backend to email a link for setting a new password.
  ///
  /// Returns normally whether or not an account exists for [email] — the
  /// backend deliberately does not say, and neither should the caller. A
  /// screen that reported "no such account" would turn this into a way to
  /// test whether an address is registered.
  ///
  /// Throws [AuthFailure] only when the request itself could not be made:
  /// rate limiting, a malformed address, no connection.
  Future<void> sendPasswordReset(String email);

  /// Joins the household the code belongs to, and returns the account as it
  /// stands afterwards.
  Future<HearthAccount> joinHousehold(String shareCode);
}
