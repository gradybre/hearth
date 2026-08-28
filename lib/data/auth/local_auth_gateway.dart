import 'dart:async';

import 'auth_gateway.dart';

/// A standing, single-user account with no backend at all.
///
/// This is what runs when there is no `config/local.json` — widget tests, and
/// anyone who clones the repo and hits run. Hearth is offline-first and
/// genuinely usable alone (spec §5.1's "solo by default"), so a missing
/// backend should mean "no sync yet", not a locked door.
///
/// The ids are fixed and local, and deliberately *not* the ids a real account
/// gets. Signing in for the first time therefore switches to a real household
/// and anything written while unconfigured stays behind, invisible — it is
/// still on disk under `local-household`, not lost, but not adopted either.
///
/// That is the right trade for now: adopting it would mean re-stamping every
/// local row and queueing it all for a sync that does not exist yet. It only
/// bites a build run without configuration, which is a development path — a
/// real user signs up before they have a library to strand.
class LocalAuthGateway implements AuthGateway {
  static const HearthAccount account = HearthAccount(
    userId: 'local-user',
    householdId: 'local-household',
    email: '',
  );

  @override
  Stream<HearthAccount?> watchAccount() =>
      Stream<HearthAccount?>.value(account);

  @override
  Future<HearthAccount?> currentAccount() async => account;

  @override
  Future<HearthAccount?> signUp({
    required String email,
    required String password,
  }) async => account;

  @override
  Future<HearthAccount> signIn({
    required String email,
    required String password,
  }) async => account;

  @override
  Future<void> signOut() async {}

  @override
  Future<HearthAccount> joinHousehold(String shareCode) async =>
      throw const AuthFailure(
        'Joining a household needs a connection. Sign in first.',
      );
}
