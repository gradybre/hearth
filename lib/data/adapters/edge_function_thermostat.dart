import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/house/thermostat.dart';
import 'thermostat.dart';

/// A Google Nest, through the `nest` Edge Function (spec §11).
///
/// The function holds three secrets the app must never see: the Device Access
/// project id, the OAuth client id, and the client secret. The household's
/// refresh token never leaves the server at all — it is a key to Brendan's
/// house, and the app ships a publishable key anybody can read out of the
/// bundle (CLAUDE.md rule 1, §8.1).
///
/// It also narrows Google's response into the small shape [stateFrom] reads,
/// for the same reason [EdgeFunctionRecipeAi] does: a trait rename at Google
/// becomes a redeploy rather than an App Store release.
class EdgeFunctionThermostat implements ThermostatGateway {
  EdgeFunctionThermostat(this._client);

  static const String functionName = 'nest';

  final SupabaseClient _client;

  @override
  String get displayName => 'Google Nest';

  @override
  Future<Uri> consentUrl() async {
    final Map<Object?, Object?> data = await _invoke(<String, Object?>{
      'action': 'consent-url',
    });
    final Object? url = data['url'];
    final Uri? parsed = url is String ? Uri.tryParse(url) : null;
    if (parsed == null || !parsed.hasScheme) {
      throw const ThermostatException(
        'Hearth could not work out where to send you to sign in.',
        isRetryable: false,
      );
    }
    return parsed;
  }

  @override
  Future<String> link(String code) async {
    final String trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw const ThermostatException(
        'Paste the code from the address bar first.',
        isRetryable: false,
      );
    }
    final Map<Object?, Object?> data = await _invoke(<String, Object?>{
      'action': 'link',
      'code': trimmed,
    });
    final Object? label = data['deviceLabel'];
    return label is String && label.isNotEmpty ? label : 'Thermostat';
  }

  @override
  Future<ThermostatLink> status() async =>
      linkFrom(await _invoke(<String, Object?>{'action': 'status'}));

  /// Sends a command. Returns nothing, deliberately.
  ///
  /// A command followed by a read is two requests against a five-a-minute
  /// device ceiling, so one drag of a setpoint would exhaust it. The server
  /// answers `{applied: true}` and the screen folds in what it asked for; the
  /// next poll, at most a minute away, is what confirms it against the
  /// thermostat's own account of itself.
  @override
  Future<void> send(ThermostatCommand command) async {
    await _invoke(<String, Object?>{
      'action': 'command',
      'command': wireFor(command),
    });
  }

  @override
  Future<void> unlink() async {
    await _invoke(<String, Object?>{'action': 'unlink'});
  }

  /// What one command looks like on the wire.
  ///
  /// Public for the same reason [stateFrom] is: this is a translation with
  /// rules in it — the fan's duration goes out in the `"900s"` shape Google's
  /// Fan trait insists on — and a translation worth testing directly.
  static Map<String, Object?> wireFor(ThermostatCommand command) =>
      switch (command) {
        SetHeat(:final double heatC) => <String, Object?>{
          'kind': 'setHeat',
          'heatC': heatC,
        },
        SetCool(:final double coolC) => <String, Object?>{
          'kind': 'setCool',
          'coolC': coolC,
        },
        SetRange(:final double heatC, :final double coolC) => <String, Object?>{
          'kind': 'setRange',
          'heatC': heatC,
          'coolC': coolC,
        },
        SetMode(:final ThermostatMode mode) => <String, Object?>{
          'kind': 'setMode',
          'mode': mode.sdm,
        },
        SetEco(:final bool on) => <String, Object?>{'kind': 'setEco', 'on': on},
        SetFanTimer(:final bool on, :final Duration? duration) =>
          <String, Object?>{
            'kind': 'setFanTimer',
            'on': on,
            if (on && duration != null) 'duration': '${duration.inSeconds}s',
          },
      };

  /// Reads the function's envelope into a [ThermostatLink].
  ///
  /// Public because it is the seam worth testing: the network cannot be mocked
  /// without mocking Supabase's client whole, but every shape the function
  /// might send — including the ones it should never send — can be put through
  /// this directly.
  static ThermostatLink linkFrom(Map<Object?, Object?> envelope) {
    if (envelope['linked'] != true) return const ThermostatLink.unlinked();
    final Object? device = envelope['device'];
    if (device is! Map) {
      // Linked, and nothing to show. That is a failure, not an absence: the
      // server said this household *has* a thermostat, so reporting no
      // thermostat would put a Connect button in front of somebody whose link
      // is fine, and pressing it starts a consent flow for no reason.
      throw const ThermostatException('The thermostat did not answer.');
    }
    return ThermostatLink.linked(
      state: stateFrom(device),
      linkedAt: _time(envelope['linkedAt']),
      linkedByYou: envelope['linkedByYou'] == true,
    );
  }

  /// Reads one device block.
  ///
  /// Absent is meaningful here, not merely tolerated: no `fan` key means the
  /// thermostat has no fan wire, and no `humidityPercent` means the model has
  /// no sensor. Both become null, and the screen draws neither control.
  static ThermostatState stateFrom(Map<Object?, Object?> device) {
    final Object? fan = device['fan'];
    final Object? modes = device['availableModes'];

    return ThermostatState(
      label:
          device['label'] is String && (device['label']! as String).isNotEmpty
          ? device['label']! as String
          : 'Thermostat',
      ambientC:
          _number(device['ambientC']) ??
          (throw const ThermostatException(
            'The thermostat did not say how warm it is.',
          )),
      humidityPercent: _number(device['humidityPercent']),
      mode: ThermostatMode.fromSdm(_text(device['mode'])),
      availableModes: <ThermostatMode>{
        if (modes is List)
          for (final Object? mode in modes)
            if (ThermostatMode.fromSdm(_text(mode)) != ThermostatMode.unknown)
              ThermostatMode.fromSdm(_text(mode)),
      },
      hvac: HvacStatus.fromSdm(_text(device['hvac'])),
      heatC: _number(device['heatC']),
      coolC: _number(device['coolC']),
      eco: EcoMode.fromSdm(_text(device['eco'])),
      fan: fan is Map
          ? FanState(isOn: fan['on'] == true, until: _time(fan['until']))
          : null,
    );
  }

  Future<Map<Object?, Object?>> _invoke(Map<String, Object?> body) async {
    final Object? data;
    try {
      final FunctionResponse response = await _client.functions.invoke(
        functionName,
        body: body,
      );
      data = response.data;
    } on FunctionException catch (error) {
      // 409 is the one answer that changes what the screen offers: the
      // authorisation is gone, and no amount of retrying brings it back.
      final bool gone = error.status == 409;
      throw ThermostatException(
        _messageFrom(error.details) ?? 'That did not go through.',
        isRetryable: !gone && error.status >= 500,
        needsRelink: gone,
      );
    } on Object {
      throw const ThermostatException('Could not reach the thermostat.');
    }

    if (data is! Map) {
      throw const ThermostatException(
        'That came back in a shape Hearth cannot read.',
      );
    }
    final Object? error = data['error'];
    if (error != null) throw ThermostatException('$error');
    return data;
  }

  /// The function answers `{ "error": "a sentence" }`; older platform errors
  /// arrive as a bare string. Both are worth showing, neither is a code.
  static String? _messageFrom(Object? details) {
    if (details is Map) {
      final Object? error = details['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    if (details is String && details.trim().isNotEmpty) return details.trim();
    return null;
  }

  static double? _number(Object? value) => switch (value) {
    final num n => n.toDouble(),
    _ => null,
  };

  static String? _text(Object? value) => value is String ? value : null;

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
