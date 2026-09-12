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
      linkedBy = null;

  const ThermostatLink.linked({
    required ThermostatState this.state,
    this.linkedAt,
    this.linkedBy,
  });

  /// What the thermostat reports. Null when nothing is connected.
  final ThermostatState? state;

  /// When the account was connected, and by which member — shown on the
  /// settings page, because "who turned this on" is the first question the
  /// other person in the house asks.
  final DateTime? linkedAt;
  final String? linkedBy;

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

  /// Where to send somebody to grant access.
  ///
  /// Built on the server: the URL carries the OAuth client id and the Device
  /// Access project id, and neither of those belongs in the app bundle
  /// (CLAUDE.md rule 1).
  Future<Uri> consentUrl();

  /// Exchanges the code the consent flow handed back.
  ///
  /// Returns what the thermostat is called, so the settings page can confirm
  /// with the device's own name rather than a tick.
  Future<String> link(String code);

  /// What the thermostat is doing, or [ThermostatLink.unlinked].
  Future<ThermostatLink> status();

  /// Sends a command and returns the state the device reports *afterwards*,
  /// rather than the state the caller asked for.
  ///
  /// The difference matters: a thermostat can accept a setpoint and round it,
  /// and a screen that keeps showing what it asked for is quietly wrong.
  Future<ThermostatLink> send(ThermostatCommand command);

  /// Forgets the account. The credential is destroyed, not marked.
  Future<void> unlink();
}
