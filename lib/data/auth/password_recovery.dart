import 'dart:async';

/// Whether the app is in the middle of setting a new password (spec §8.3,
/// R13).
///
/// A recovery link does not open a form — it opens a **session**. Supabase
/// signs the user in with it and fires `passwordRecovery`, and from the app's
/// point of view that is indistinguishable from an ordinary sign-in: the
/// account resolves, the gate opens, and somebody who came to change their
/// password is standing in their meal plan instead, holding a session minted
/// by a link out of an email.
///
/// So the fact is held here and the gate asks. Until the password is actually
/// set, the only screen a recovery session may reach is the one that sets it.
///
/// Its own object rather than a flag on the gateway: the gateway answers *who
/// is signed in*, and the answer during recovery is "somebody, but not for
/// anything yet", which is not a shape that field has.
class PasswordRecovery {
  PasswordRecovery();

  final StreamController<bool> _pending = StreamController<bool>.broadcast();
  bool _isPending = false;

  /// True from the moment a recovery link opens a session until the password
  /// is set or the attempt is abandoned.
  bool get isPending => _isPending;

  /// Re-emitted on every change, so the gate can rebuild on it.
  Stream<bool> watch() => _pending.stream;

  /// A recovery link has opened a session.
  void begin() => _set(true);

  /// The password was set, or the attempt was abandoned.
  ///
  /// Both end the same way deliberately. A recovery session that is not going
  /// to be used for recovery is not a session anybody asked for, and the
  /// caller signs out rather than keeping it — see the cancel path on the
  /// new-password screen.
  void end() => _set(false);

  void _set(bool value) {
    if (_isPending == value) return;
    _isPending = value;
    if (!_pending.isClosed) _pending.add(value);
  }

  void dispose() {
    unawaited(_pending.close());
  }
}
