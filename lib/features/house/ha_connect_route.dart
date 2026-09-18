/// The setup screen, wired to the real connection (spec §11).
///
/// `HaSetupScreen` takes a probe and a save as functions so it can be tested
/// without a house. This is the one place that supplies the real ones, and it
/// is deliberately thin: everything it does is translate between the
/// repository's answers and the screen's, so that neither has to know about
/// the other.
///
/// The translation is not ceremony. `HaProbeOutcome` is what the data layer
/// found; `HaSetupOutcome` is what a screen can say. Keeping them apart means
/// the repository can grow a failure the screen has no sentence for yet, and
/// the compiler will say so rather than a user meeting an empty message.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/house/ha_credentials.dart';
import '../../data/house/ha_repository.dart';
import '../../domain/house/ha_endpoint.dart';
import 'ha_setup_screen.dart';

/// Opens the setup screen against this installation's repository.
class HaConnectRoute extends ConsumerWidget {
  const HaConnectRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HaRepository repository = ref.watch(haRepositoryProvider);

    return FutureBuilder<HaEndpoint?>(
      // So somebody editing an address sees what they are changing rather
      // than typing into a blank field.
      future: repository.endpoint(),
      builder: (BuildContext context, AsyncSnapshot<HaEndpoint?> existing) =>
          HaSetupScreen(
            existingAddress: existing.data?.origin.toString(),
            probe: (HaEndpoint endpoint, String token) async =>
                _asSetupOutcome(await repository.probe(endpoint, token)),
            save: (HaEndpoint endpoint, String token) async {
              await repository.save(endpoint, token);
              // The screen reads this next time it is opened, and the House
              // section reads it to decide what to draw.
              ref.invalidate(haConfiguredProvider);
            },
          ),
    );
  }

  /// What the data layer found, in words the screen has.
  ///
  /// Exhaustive rather than defaulted: a new failure in the repository should
  /// break this switch at compile time, not arrive in front of somebody as a
  /// blank message. `cannotStore` has no counterpart here because it is not a
  /// probe result — it comes out of `save` as an exception, which the screen
  /// catches separately.
  static HaSetupOutcome _asSetupOutcome(HaProbeOutcome found) =>
      switch (found) {
        HaProbeOutcome.reachable => HaSetupOutcome.reachable,
        HaProbeOutcome.unreachable => HaSetupOutcome.unreachable,
        HaProbeOutcome.insecure => HaSetupOutcome.insecure,
        HaProbeOutcome.refused => HaSetupOutcome.refused,
        HaProbeOutcome.notHomeAssistant => HaSetupOutcome.notHomeAssistant,
      };
}

/// What the House section shows where the devices will go.
///
/// Not the dashboard yet — discovery and selection are the next piece. What it
/// does do is tell the truth about where the connection stands, because a tab
/// that draws an empty list for both "no connection" and "no devices chosen"
/// teaches somebody that the app is broken.
class HaDevicesScreen extends ConsumerWidget {
  const HaDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> configured = ref.watch(haConfiguredProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      // Scrolls, and is centred only when there is room to centre in.
      // Without this the column simply runs off the bottom at large text —
      // 542 points of it at 3x on a 390-point phone, which the a11y sweep
      // caught before this shipped. §6.3: dynamic type is honoured, and a
      // Center inside a fixed body honours nothing.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints room) =>
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: room.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: switch (configured) {
                        AsyncData<bool>(value: final bool yes) when yes =>
                          const Text(
                            'Connected to Home Assistant. Choosing which devices to show is '
                            'the next thing being built.',
                            textAlign: TextAlign.center,
                          ),
                        AsyncData<bool>() => _NotConnected(
                          onConnect: () => _openSetup(context),
                        ),
                        AsyncError<bool>() => const Text(
                          'Hearth could not read this device\'s Home Assistant settings.',
                          textAlign: TextAlign.center,
                        ),
                        _ => const CircularProgressIndicator(),
                      },
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  static void _openSetup(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const HaConnectRoute(),
    ),
  );
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const Text(
        'Hearth can show the door sensors, plugs and lights that your Home '
        'Assistant already knows about. It keeps doing the pairing and the '
        'automations; this is just a way to see and use them.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: onConnect,
        child: const Text('Connect Home Assistant'),
      ),
    ],
  );
}

/// Exported so the credential scope is reachable from a settings screen later
/// without that screen importing the data layer directly.
typedef HaScope = HaCredentialScope;
