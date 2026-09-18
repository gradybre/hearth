/// Connecting Hearth to Home Assistant (`docs/HOME_ASSISTANT_SPEC.md` §4.1).
///
/// Two things somebody types, and one of them is a bearer credential for their
/// whole house. So the shape of this screen is decided by §4.1's rules about
/// that, not by what is convenient:
///
///  * **the token is obscured, and revealing it is a deliberate act** — a
///    screen that shows a long-lived token by default shows it to whoever is
///    in the room, and to whoever is looking at the screen share;
///  * **nothing reads the clipboard on its own.** Paste is a button somebody
///    presses. An app that quietly inspects the clipboard on open is reading
///    everything else that has been copied, too;
///  * **no token is ever echoed in an error.** The failures below say what
///    went wrong and never quote what was typed;
///  * **the connection is proved before it replaces a working one**, and
///    cancelling keeps what was already there. Somebody testing a new address
///    should not lose the one that works to find out it was wrong.
///
/// The address example is deliberately a documentation address. §4.1: never
/// prefill a real household URL in source code, because a source file is read
/// by more people than a house has.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/house/ha_credentials.dart';
import '../../domain/house/ha_endpoint.dart';
import '../account/settings_kit.dart';

/// What happened when the connection was tried.
///
/// Deliberately a small closed set rather than a string: §4.1 requires setup to
/// tell address failure from TLS failure from authentication failure, and a
/// screen can only do that if the answer arrives as a kind rather than as prose
/// somebody has to match on.
enum HaSetupOutcome {
  /// Connected, authenticated, and nothing was operated to find out.
  reachable,

  /// Nothing answered at that address.
  unreachable,

  /// Something answered and refused the certificate.
  insecure,

  /// Home Assistant answered and refused the token.
  refused,

  /// Something answered but it was not Home Assistant.
  notHomeAssistant,

  /// The keychain would not hold the token. §4.1: fail clearly rather than
  /// putting a credential somewhere ordinary.
  cannotStore,
}

/// Tries the connection. Injected so this screen can be tested without a house.
typedef HaSetupProbe = Future<HaSetupOutcome> Function(
  HaEndpoint endpoint,
  String token,
);

/// Saves a proved connection.
typedef HaSetupSave = Future<void> Function(HaEndpoint endpoint, String token);

/// The setup screen.
class HaSetupScreen extends StatefulWidget {
  const HaSetupScreen({
    required this.probe,
    required this.save,
    this.existingAddress,
    super.key,
  });

  final HaSetupProbe probe;
  final HaSetupSave save;

  /// What is already configured, if anything. Shown so somebody editing an
  /// address can see what they are changing rather than typing into a blank.
  final String? existingAddress;

  @override
  State<HaSetupScreen> createState() => _HaSetupScreenState();
}

class _HaSetupScreenState extends State<HaSetupScreen> {
  late final TextEditingController _address = TextEditingController(
    text: widget.existingAddress ?? '',
  );
  final TextEditingController _token = TextEditingController();

  /// Off by default, and only ever turned on by a press.
  bool _revealed = false;

  bool _allowPlainHttp = false;
  bool _busy = false;

  /// What to tell somebody. Never carries the token.
  String? _problem;
  String? _good;

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    // Only here, only on a press. Nothing on this screen reads the clipboard
    // by itself — an app that inspects it on open is reading whatever else
    // somebody copied.
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _problem = 'There is nothing to paste.');
      return;
    }
    setState(() {
      _token.text = text;
      _problem = null;
    });
  }

  Future<void> _connect() async {
    final HaEndpointResult parsed = HaEndpoint.parse(
      _address.text.trim(),
      allowPlainHttpOnLocalNetwork: _allowPlainHttp,
    );

    switch (parsed) {
      case HaEndpointRefused():
        setState(() {
          _problem = _addressProblem(parsed);
          _good = null;
        });
        return;
      case HaEndpointAccepted(:final HaEndpoint endpoint):
        if (_token.text.trim().isEmpty) {
          setState(() {
            _problem =
                'Hearth needs the token from your Home Assistant '
                'profile to connect.';
            _good = null;
          });
          return;
        }

        setState(() {
          _busy = true;
          _problem = null;
          _good = null;
        });

        final HaSetupOutcome outcome = await widget.probe(
          endpoint,
          _token.text.trim(),
        );
        if (!mounted) return;

        if (outcome != HaSetupOutcome.reachable) {
          setState(() {
            _busy = false;
            _problem = _outcomeProblem(outcome);
          });
          return;
        }

        // Proved, and only now saved. §4.1: validate before replacing a
        // working connection.
        try {
          await widget.save(endpoint, _token.text.trim());
        } on HaCredentialException catch (failure) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            // The store's own sentence, which is written to carry nothing from
            // the platform error.
            _problem = failure.message;
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _busy = false;
          _good = 'Hearth is connected to Home Assistant.';
        });
    }
  }

  /// A sentence for each way an address can be wrong.
  ///
  /// One per refusal, because "that address will not work" tells somebody
  /// nothing about which part of it to change.
  static String _addressProblem(HaEndpointRefused refusal) => switch (refusal) {
    HaBlankAddress() => 'Enter the address of your Home Assistant.',
    HaMissingScheme() =>
      'Start the address with https:// — or http:// if this is on your own '
          'network.',
    HaUnsupportedScheme(:final String scheme) =>
      'Hearth cannot use a $scheme address. Use https:// or http://.',
    HaCredentialsInAddress() =>
      'Leave the sign-in details out of the address. Hearth uses the token '
          'below.',
    HaMissingHost() => 'That address has no server in it.',
    HaPlainHttpNotChosen() =>
      'That address is not encrypted. Tick the box below if it is on your own '
          'network.',
    HaPlainHttpNotLocal() =>
      'Hearth will only use an unencrypted address on your own network, and '
          'that one is not. Use https:// instead.',
    HaMalformedAddress() => 'That does not look like a web address.',
  };

  static String _outcomeProblem(HaSetupOutcome outcome) => switch (outcome) {
    HaSetupOutcome.unreachable =>
      'Nothing answered at that address. Check that Home Assistant is running '
          'and that this device is on the same network — or connected to your '
          'VPN, if the address is a remote one.',
    HaSetupOutcome.insecure =>
      'That server\'s security certificate was refused. Hearth will not send '
          'your token to it.',
    HaSetupOutcome.refused =>
      'Home Assistant did not accept that token. Create a new one in your '
          'Home Assistant profile and paste it here.',
    HaSetupOutcome.notHomeAssistant =>
      'Something answered at that address, but it was not Home Assistant.',
    HaSetupOutcome.cannotStore =>
      'Hearth could not store the token securely on this device. It has not '
          'been saved anywhere else.',
    HaSetupOutcome.reachable => '',
  };

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return SettingsPage(
      title: 'Home Assistant',
      blurb:
          'Hearth reads your devices from Home Assistant on your own network. '
          'Home Assistant keeps doing the pairing, the accounts and the '
          'automations; Hearth just gives you a way to see and use them.',
      children: <Widget>[
        Text(
          'Where it is',
          style: context.text.sectionHeader.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: HearthSpacing.sm),
        SettingsGroup(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: context.text.body,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      // A documentation address, never a real one — a source file is
                      // read by more people than a house has.
                      hintText: 'http://homeassistant.local:8123',
                      helperText:
                          'The same address you use in a browser at home. A remote '
                          'address must start with https://.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  _PlainHttpChoice(
                    value: _allowPlainHttp,
                    onChanged: (bool on) =>
                        setState(() => _allowPlainHttp = on),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.lg),
        Text(
          'The token',
          style: context.text.sectionHeader.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: HearthSpacing.sm),
        SettingsGroup(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'In Home Assistant, open your profile, scroll to Long-lived '
                    'access tokens, and create one named for this device. Paste it '
                    'here — Hearth keeps it in this device\'s keychain and never '
                    'sends it anywhere but your Home Assistant.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.md),
                  Semantics(
                    label: 'Home Assistant token',
                    textField: true,
                    obscured: !_revealed,
                    child: TextField(
                      controller: _token,
                      obscureText: !_revealed,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLines: 1,
                      style: context.text.body,
                      decoration: InputDecoration(
                        labelText: 'Long-lived access token',
                        suffixIcon: IconButton(
                          // Revealing is a deliberate act. A token shown by default
                          // is shown to the room and to the screen share.
                          onPressed: () =>
                              setState(() => _revealed = !_revealed),
                          icon: Icon(
                            _revealed ? Icons.visibility_off : Icons.visibility,
                          ),
                          tooltip: _revealed
                              ? 'Hide the token'
                              : 'Show the token',
                          constraints: const BoxConstraints(
                            minWidth: HearthTouch.minTarget,
                            minHeight: HearthTouch.minTarget,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _paste,
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Paste the token'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_problem case final String problem) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          SettingsMessage(text: problem, isError: true),
        ],
        if (_good case final String good) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          SettingsMessage(text: good, isError: false),
        ],
        const SizedBox(height: HearthSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
          child: FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? 'Connecting…' : 'Connect'),
          ),
        ),
      ],
    );
  }
}

/// The unencrypted-address choice.
///
/// A deliberate tick rather than something Hearth decides: §5.1 allows plain
/// HTTP only as an explicit local-network choice, and the sentence says what
/// it costs rather than only what it enables.
class _PlainHttpChoice extends StatelessWidget {
  const _PlainHttpChoice({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Checkbox(
              value: value,
              onChanged: (bool? on) => onChanged(on ?? false),
            ),
            Expanded(
              child: Text(
                'This address is on my own network, and I understand it is '
                'not encrypted.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
