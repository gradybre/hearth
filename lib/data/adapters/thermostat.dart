import 'package:meta/meta.dart';

import '../../domain/house/thermostat.dart';

/// The thermostat, behind an interface (CLAUDE.md rule 7).
///
/// Hearth talks to a Google Nest today. Nothing above this line knows that:
/// the screen asks for a state and sends commands, and which company's cloud
/// answers is a fact about one file in `lib/data/adapters/`.
///
/// Every method can throw [ThermostatException]. That is deliberate rather
/// than a nullable return — a thermostat that cannot be reached is a sentence
/// worth putting on screen, and a null would throw that sentence away.

/// Whether the household has connected an account, and what the thermostat
/// said when it was last asked.
///
/// One type for both answers because the screen has to tell them apart and
/// nothing else does: an unlinked household and an unreachable thermostat
/// look identical if all you have is a null.
@immutable
class ThermostatLink {
  const ThermostatLink.unlinked()
    : state = null,
      linkedAt = null,
      linkedByYou = false;

  const ThermostatLink.linked({
    required ThermostatState this.state,
    this.linkedAt,
    this.linkedByYou = false,
  });

  /// What the thermostat reports. Null when nothing is connected.
  final ThermostatState? state;

  /// When the account was connected.
  final DateTime? linkedAt;

  /// Whether *you* connected it, rather than the other person in the house.
  ///
  /// A boolean rather than a name, because the only thing the screen has to
  /// say is whose Google account has to reconnect when the link dies — and in
  /// a two-person household that is a question with two answers. The server
  /// stores a user id; putting that on screen would say nothing, and resolving
  /// it to a name would be another query for the same sentence.
  final bool linkedByYou;

  bool get isLinked => state != null;
}

/// Something went wrong between here and the house.
///
/// Three states rather than one, because the screen does something different
/// with each: [needsRelink] is a dead credential and the only cure is the
/// consent flow again; [isRetryable] is weather, and the button stays live;
/// neither is a refusal that will not change however many times it is tried.
@immutable
class ThermostatException implements Exception {
  const ThermostatException(
    this.message, {
    this.isRetryable = true,
    this.needsRelink = false,
  });

  /// A sentence worth showing somebody, never a status code.
  final String message;

  final bool isRetryable;

  /// The authorisation is gone — revoked, expired, or never survived its
  /// first week. Nothing but connecting the account again will fix it.
  final bool needsRelink;

  @override
  String toString() => 'ThermostatException: $message';
}

/// A household's thermostat.
abstract interface class ThermostatGateway {
  /// Named on the settings page, so "connected to" has something to say.
  String get displayName;

  /// Opens a consent attempt and says where to send the browser.
  ///
  /// Built on the server: the URL carries the OAuth client id, the Device
  /// Access project id and a single-use nonce, none of which belongs in the
  /// app bundle (CLAUDE.md rule 1).
  ///
  /// Nothing comes back through the app. Google redirects the browser to a
  /// function of Hearth's own, which finishes the exchange — so the app finds
  /// out by asking [status] again, not by being handed a code. The first
  /// design did hand back a code for the user to paste, and it does not work
  /// on a phone: `google.com` is a universal link claimed by the Google app,
  /// so iOS hands the redirect there and the code is never visible.
  Future<Uri> consentUrl();

  /// What the thermostat is doing, or [ThermostatLink.unlinked].
  Future<ThermostatLink> status();

  /// Sends a command.
  ///
  /// Returns nothing rather than the new state: reading back costs a second
  /// request against a five-a-minute device ceiling, which one drag of a
  /// setpoint would exhaust. The caller shows what it asked for and lets the
  /// next [status] correct it.
  Future<void> send(ThermostatCommand command);

  /// Forgets the account. The credential is destroyed, not marked.
  Future<void> unlink();
}
