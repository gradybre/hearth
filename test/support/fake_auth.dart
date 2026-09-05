import 'dart:async';

import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/data/auth/auth_gateway.dart';

/// An in-memory accounts backend.
///
/// Auth is exactly the kind of thing that has to be exercisable without a
/// network — the failure paths especially, since they are the ones a user
/// meets on a bad day and the ones no manual pass reliably reproduces.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.requiresConfirmation = false, HearthAccount? signedIn})
    : _account = signedIn;

  static const HearthAccount anAccount = HearthAccount(
    userId: 'user-1',
    email: 'cook@example.com',
    householdId: 'household-1',
    shareCode: 'QRSTUV23',
  );

  /// Whether signing up leaves the user signed out pending an email.
  final bool requiresConfirmation;

  final StreamController<HearthAccount?> _controller =
      StreamController<HearthAccount?>.broadcast();
  HearthAccount? _account;

  AuthFailure? nextFailure;

  /// Holds a call open so a test can look at the screen mid-flight.
  Completer<void>? gate;
  final List<String> joined = <String>[];

  /// Every address a reset was asked for, in order. The real gateway cannot
  /// report whether the address exists, so what a test can check is that the
  /// right address was asked about at all.
  final List<String> resetsRequested = <String>[];
  int signOuts = 0;

  @override
  Stream<HearthAccount?> watchAccount() async* {
    // Mirrors the real gateway: emit where things stand, then every change.
    yield _account;
    yield* _controller.stream;
  }

  @override
  Future<HearthAccount?> currentAccount() async => _account;

  @override
  Future<HearthAccount?> signUp({
    required String email,
    required String password,
  }) async {
    await gate?.future;
    _throwIfQueued();
    if (requiresConfirmation) return null;
    return _emit(anAccount);
  }

  @override
  Future<HearthAccount> signIn({
    required String email,
    required String password,
  }) async {
    await gate?.future;
    _throwIfQueued();
    return _emit(anAccount);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _account = null;
    _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await gate?.future;
    _throwIfQueued();
    resetsRequested.add(email);
  }

  @override
  Future<HearthAccount> joinHousehold(String shareCode) async {
    _throwIfQueued();
    joined.add(shareCode);
    return _emit(
      const HearthAccount(
        userId: 'user-1',
        email: 'cook@example.com',
        householdId: 'household-2',
        shareCode: 'WXYZ2345',
      ),
    );
  }

  HearthAccount _emit(HearthAccount account) {
    _account = account;
    _controller.add(account);
    return account;
  }

  void _throwIfQueued() {
    final AuthFailure? failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }
}

/// A sync controller that never touches a network or a clock.
///
/// The real one registers lifecycle observers and a debounce timer; a widget
/// test that leaves either running fails at teardown, and neither has anything
/// to do with the screen under test.
class FakeSyncController extends SyncController {
  @override
  SyncStatus build() => const SyncStatus.idle();

  @override
  void syncSoon() {}

  @override
  Future<void> sync() async {}
}
