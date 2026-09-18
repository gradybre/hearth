/// One place that knows how to reach the house
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.1, §5.2, §6).
///
/// The pieces below it each do one thing and know nothing about the others:
/// `HaEndpoint` decides where a token may be sent, `HaCredentialStore` keeps
/// the token, `HaSession` speaks the protocol, `HaConnection` owns a session's
/// life. This is what holds them together, and it exists so that **nothing
/// above it ever handles a token**.
///
/// That is the load-bearing property. A screen asks this to prove an address
/// and a token, and asks it to save them; it never sees the token again
/// afterwards, and the connection it later uses is opened from the stored one.
/// A feature that could read the credential back is a feature that can log it.
library;

import 'dart:convert';

import '../../domain/house/ha_endpoint.dart';
import '../local/preference_store.dart';
import 'ha_connection.dart';
import 'ha_credentials.dart';
import 'ha_session.dart';
import 'ha_socket.dart';

/// Why a connection attempt did not end in a live session.
///
/// A closed set rather than a message, because §4.1 requires setup to tell an
/// address failure from a TLS failure from a refused token — and a screen can
/// only say which if the answer arrives as a kind.
enum HaProbeOutcome {
  reachable,
  unreachable,
  insecure,
  refused,
  notHomeAssistant,
}

/// Reads and writes one installation's Home Assistant connection.
class HaRepository {
  HaRepository({
    required PreferenceStore preferences,
    required HaCredentialStore credentials,
    required this.scope,
    HaSocketOpener? opener,
  }) : _preferences = preferences,
       _credentials = credentials,
       _opener = opener ?? WebSocketHaSocket.connect;

  final PreferenceStore _preferences;
  final HaCredentialStore _credentials;
  final HaSocketOpener _opener;

  /// Which Hearth user, household and connection this is for.
  final HaCredentialScope scope;

  /// `house.ha.endpoint/<user>/<household>/<connection>`.
  ///
  /// Beside the selection's key rather than inside the keychain: an address is
  /// not a secret, and §5.3 puts non-secret connection metadata through the
  /// preference abstraction. It is still scoped, because a second person on
  /// this phone should not inherit a server address either.
  String get _endpointKey =>
      'house.ha.endpoint/${scope.userId}/${scope.householdId}/'
      '${scope.connectionId}';

  /// The configured address, or null when there is none.
  Future<HaEndpoint?> endpoint() async {
    final String? raw = await _preferences.read(_endpointKey);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      // Re-parsed rather than trusted. A stored address was validated when it
      // was written, by a version of these rules that may since have got
      // stricter — and the one place that decides where a credential may be
      // sent should decide every time, not once.
      return switch (HaEndpoint.parse(
        decoded['url'] as String?,
        allowPlainHttpOnLocalNetwork: decoded['plainHttp'] == true,
      )) {
        HaEndpointAccepted(:final HaEndpoint endpoint) => endpoint,
        HaEndpointRefused() => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// Whether this installation has a connection configured at all.
  Future<bool> get isConfigured async =>
      await endpoint() != null && await _credentials.read(scope) != null;

  /// Tries an address and a token without operating anything.
  ///
  /// §4.1: "Test connectivity and authentication without operating devices."
  /// So this opens a session, bootstraps to prove the token can actually read,
  /// and closes it. Nothing is switched, dimmed or asked to move.
  Future<HaProbeOutcome> probe(HaEndpoint endpoint, String token) async {
    HaSession? session;
    try {
      session = await HaSession.open(
        url: endpoint.webSocketUri,
        token: token,
        opener: _opener,
        generation: 0,
      );
      await session.bootstrap();
      return HaProbeOutcome.reachable;
    } on HaSessionException catch (failure) {
      return switch (failure.failure) {
        HaSessionFailure.credentialsRejected => HaProbeOutcome.refused,
        HaSessionFailure.unsupportedServer => HaProbeOutcome.notHomeAssistant,
        HaSessionFailure.connectionLost => HaProbeOutcome.unreachable,
      };
    } on Object catch (error) {
      // A TLS failure arrives as a platform exception rather than one of ours.
      // Told apart by shape rather than by message, because a message is
      // localised and a type is not.
      return _looksLikeCertificate(error)
          ? HaProbeOutcome.insecure
          : HaProbeOutcome.unreachable;
    } finally {
      await session?.close();
    }
  }

  static bool _looksLikeCertificate(Object error) =>
      error.runtimeType.toString().contains('HandshakeException') ||
      error.runtimeType.toString().contains('CertificateException');

  /// Stores a proved connection.
  ///
  /// The token first. If the keychain refuses, nothing else is written — an
  /// address saved beside a credential that is not there is a connection that
  /// looks configured and cannot work, and the screen would have no way to
  /// tell somebody why.
  Future<void> save(HaEndpoint endpoint, String token) async {
    await _credentials.write(scope, token);
    await _preferences.write(
      _endpointKey,
      jsonEncode(<String, Object?>{
        // The origin plus any proxy prefix, not the REST base — `restBase`
        // already has `/api/` on it, and re-parsing that would store the
        // prefix twice on the next read.
        'url': endpoint.origin.replace(path: endpoint.pathPrefix).toString(),
        // Recorded so the re-parse below can reach the same verdict. Without
        // it a stored `http://` address is refused on read, and a working
        // local connection silently becomes "not configured" after a restart.
        'plainHttp': !endpoint.usesTls,
      }),
    );
  }

  /// Forgets this connection on this device.
  ///
  /// **Local only.** §4.1 and §5.2 are emphatic: deleting a long-lived token
  /// here does not revoke it in Home Assistant, and the screen that calls this
  /// has to say where to do that rather than implying it is done. This method
  /// cannot revoke anything and does not pretend to.
  ///
  /// The credential goes first and unconditionally, so that a phone that
  /// cannot reach the Pi can still be disconnected — §4.1 requires exactly
  /// that.
  Future<void> forget() async {
    await _credentials.forget(scope);
    await _preferences.delete(_endpointKey);
  }

  /// A connection over the stored address and token.
  ///
  /// Returns null when there is nothing configured. The token is read here and
  /// handed straight to the session; it is never returned to a caller, which
  /// is the whole reason this class exists.
  Future<HaConnection?> connect() async {
    final HaEndpoint? where = await endpoint();
    if (where == null) return null;
    final String? token = await _credentials.read(scope);
    if (token == null) return null;

    return HaConnection(
      open: ({required int generation}) => HaSession.open(
        url: where.webSocketUri,
        token: token,
        opener: _opener,
        generation: generation,
      ),
    );
  }
}
