import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../data/adapters/thermostat.dart';
import '../../domain/house/thermostat.dart';

/// The house's thermostat (spec §11).
///
/// Everything about a thermostat is somebody else's cloud, so this screen is
/// mostly about being honest when that cloud is slow, rate-limited, or has
/// stopped accepting Hearth's credential. The four states it can be in are
/// four designs, not a spinner and an error string.
class ThermostatScreen extends ConsumerStatefulWidget {
  const ThermostatScreen({super.key});

  /// How often the thermostat is asked, while this screen is the one in front
  /// of you.
  ///
  /// Google's device ceiling is a hundred requests an hour and two phones
  /// cannot see each other's, so the real budget lives on the server. A minute
  /// is what keeps this screen well inside it while still feeling live.
  static const Duration pollEvery = Duration(minutes: 1);

  /// How long a press waits for another before it is sent.
  ///
  /// Commands are capped at five a minute per device, so one press per tap
  /// would let a few seconds of deciding what temperature you want exhaust the
  /// allowance. A burst of taps is one decision and becomes one command.
  static const Duration settleAfter = Duration(milliseconds: 600);

  /// How often to ask while Google is open in the browser.
  static const Duration whileConnecting = Duration(seconds: 3);

  @override
  ConsumerState<ThermostatScreen> createState() => _ThermostatScreenState();
}

class _ThermostatScreenState extends ConsumerState<ThermostatScreen> {
  ThermostatLink? _link;
  ThermostatState? _shown;
  String? _error;
  bool _needsRelink = false;
  bool _busy = false;
  bool _loadedOnce = false;
  DateTime? _readAt;

  Timer? _poll;
  Timer? _settle;
  ThermostatCommand? _queued;

  /// True between opening Google and the link appearing.
  ///
  /// Nothing comes back through the app — Google redirects the browser to an
  /// Edge Function, which finishes the exchange — so the only way to find out
  /// is to keep asking. The first design had the user copy a code out of the
  /// address bar, and it does not work on a phone: `google.com` is a universal
  /// link claimed by the Google app, so iOS hands the redirect there and the
  /// code is never visible to anybody.
  bool _waiting = false;

  ThermostatGateway? get _gateway => ref.read(thermostatProvider);

  @override
  void initState() {
    super.initState();
    // After the frame: reading a provider during initState is the thing
    // Riverpod refuses, and the first read is a network call besides.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    // Both, and before the controller: a timer that outlives this screen is a
    // request nobody is looking at, spent from an hourly budget somebody else
    // may want — and in a widget test it is a run that hangs rather than fails.
    _poll?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _poll?.cancel();
    // Faster while a consent flow is open in the browser, because the answer
    // arrives out of band and there is nothing else to watch for it. The
    // server serves an unlinked household from its own row without touching
    // Google, so these cost nothing against the device's hourly ceiling.
    _poll = Timer(
      _waiting ? ThermostatScreen.whileConnecting : ThermostatScreen.pollEvery,
      () {
        if (mounted) unawaited(_refresh());
      },
    );
  }

  Future<void> _refresh() async {
    final ThermostatGateway? gateway = _gateway;
    if (gateway == null) {
      setState(() => _loadedOnce = true);
      return;
    }
    try {
      final ThermostatLink link = await gateway.status();
      if (!mounted) return;
      setState(() {
        _link = link;
        // What the thermostat says replaces what we hoped it would say. A
        // pending press is either confirmed by this or quietly corrected —
        // and either way the number on screen is now the device's own.
        _shown = link.state;
        _readAt = DateTime.now();
        _error = null;
        _needsRelink = false;
        _loadedOnce = true;
      });
      if (link.isLinked) {
        _waiting = false;
        _schedulePoll();
      } else if (_waiting) {
        _schedulePoll();
      }
    } on ThermostatException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _needsRelink = failure.needsRelink;
        _loadedOnce = true;
      });
      // A dead credential is not weather. Asking again every minute would
      // spend the budget on a question with a settled answer.
      if (!failure.needsRelink) _schedulePoll();
    }
  }

  /// Shows a press immediately and sends it once the presses stop.
  void _press(ThermostatCommand? command) {
    final ThermostatState? now = _shown;
    if (command == null || now == null) return;

    final String? refusal = now.refuse(command);
    if (refusal != null) {
      setState(() => _error = refusal);
      return;
    }

    setState(() {
      _error = null;
      _shown = switch (command) {
        SetHeat(:final double heatC) => now.withSetpoints(heatC: heatC),
        SetCool(:final double coolC) => now.withSetpoints(coolC: coolC),
        SetRange(:final double heatC, :final double coolC) => now.withSetpoints(
          heatC: heatC,
          coolC: coolC,
        ),
        // A switch that springs back the instant it is flipped reads as
        // broken, and then sits wrong until the next reading a minute later.
        SetMode(:final ThermostatMode mode) => now.copyWith(mode: mode),
        SetEco(:final bool on) => now.copyWith(
          eco: on ? EcoMode.manualEco : EcoMode.off,
        ),
        SetFanTimer(:final bool on) => now.copyWith(fan: FanState(isOn: on)),
      };
      _queued = command;
    });

    _settle?.cancel();
    _settle = Timer(ThermostatScreen.settleAfter, () {
      if (mounted) unawaited(_send());
    });
  }

  Future<void> _send() async {
    final ThermostatCommand? command = _queued;
    final ThermostatGateway? gateway = _gateway;
    if (command == null || gateway == null) return;
    _queued = null;

    try {
      await gateway.send(command);
      if (!mounted) return;
      // Not re-read here: a command plus a read is two requests against a
      // five-a-minute ceiling. The next poll confirms it.
      _schedulePoll();
    } on ThermostatException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _needsRelink = failure.needsRelink;
        // The press is taken back, because the thermostat did not take it.
        _shown = _link?.state;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) await _refresh();
    } on ThermostatException catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _needsRelink = failure.needsRelink;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the consent flow and starts waiting for it to land.
  ///
  /// Not through [_run], because that refreshes on success and a refresh
  /// clears the error — and the one error worth keeping here is "your browser
  /// did not open", which is the only part of this the app can see fail.
  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uri url = await _gateway!.consentUrl();
      // Waiting before launching, and polling from here on: the answer comes
      // back through a redirect to an Edge Function, so the app has nothing to
      // watch except the link appearing.
      setState(() => _waiting = true);
      _schedulePoll();

      // A real browser, not an in-app view: Google refuses embedded webviews
      // for OAuth, and the signed-in Google session is in the real browser
      // anyway.
      final bool opened = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const ThermostatException(
          'Hearth could not open your browser.',
          isRetryable: false,
        );
      }
    } on ThermostatException catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _needsRelink = failure.needsRelink;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Hearth could not open your browser.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() => _run(() => _gateway!.unlink());

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(child: ReadingColumn(child: _body(context, gutter))),
    );
  }

  Widget _body(BuildContext context, double gutter) {
    if (_gateway == null) {
      return CentredMessage(
        gutter: gutter,
        children: <Widget>[
          Text(
            'Thermostat',
            style: context.text.sectionHeader,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'This build has no connection to the house.',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (!_loadedOnce) {
      return CentredMessage(
        gutter: gutter,
        children: <Widget>[
          Text(
            'Asking the thermostat…',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final ThermostatState? state = _shown;
    if (state == null) {
      // Only the server saying so, or a dead credential, means there is
      // nothing connected. Anything else — no signal, a rate limit, a
      // thermostat that did not answer — is a link that exists and could not
      // be read, and offering Connect there invites a fresh consent flow
      // against a link that is perfectly fine.
      final bool reallyUnlinked =
          _needsRelink || (_link != null && !_link!.isLinked);
      return reallyUnlinked
          ? _unlinked(context, gutter)
          : _unreachable(context, gutter);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.all(gutter),
        children: <Widget>[
          if (_error != null) _Message(text: _error!, isError: true),
          _Ambient(state: state, readAt: _readAt),
          const SizedBox(height: HearthSpacing.lg),
          if (state.eco.isOn)
            const _Message(
              text:
                  'Eco is holding the temperature. Turn Eco off to change '
                  'it.',
              isError: false,
            )
          else if (state.mode == ThermostatMode.off)
            const _Message(
              text:
                  'The thermostat is off. Choose Heat, Cool or Heat · Cool '
                  'to set a temperature.',
              isError: false,
            )
          else
            ..._targets(context, state),
          const SizedBox(height: HearthSpacing.lg),
          _Modes(
            state: state,
            onPick: (ThermostatMode m) => _press(SetMode(m)),
          ),
          const SizedBox(height: HearthSpacing.md),
          _Toggle(
            label: 'Eco',
            detail: 'Google’s own saving temperatures.',
            value: state.eco.isOn,
            onChanged: (bool on) => _press(SetEco(on: on)),
          ),
          // Only where the thermostat actually has a fan. A control that
          // could only ever fail is worse than no control (spec §11).
          if (state.hasFan) ...<Widget>[
            const SizedBox(height: HearthSpacing.sm),
            _Toggle(
              label: 'Fan',
              detail: state.fan!.isOn
                  ? 'Running.'
                  : 'Run the fan for fifteen minutes.',
              value: state.fan!.isOn,
              onChanged: (bool on) => _press(
                SetFanTimer(on: on, duration: const Duration(minutes: 15)),
              ),
            ),
          ],
          const SizedBox(height: HearthSpacing.xl),
          _Footer(link: _link, busy: _busy, onDisconnect: _disconnect),
        ],
      ),
    );
  }

  List<Widget> _targets(BuildContext context, ThermostatState state) {
    final bool both = state.mode == ThermostatMode.heatCool;
    return <Widget>[
      if (state.heatC != null)
        _Target(
          label: both ? 'Heat to' : 'Target',
          valueC: state.heatC!,
          busy: _busy,
          onStep: (int by) =>
              _press(by > 0 ? state.warmer(by) : state.cooler(-by)),
        ),
      if (both && state.coolC != null) ...<Widget>[
        const SizedBox(height: HearthSpacing.md),
        _Target(
          label: 'Cool to',
          valueC: state.coolC!,
          busy: _busy,
          onStep: (int by) => _press(
            by > 0
                ? state.warmer(by, heat: false)
                : state.cooler(-by, heat: false),
          ),
        ),
      ],
    ];
  }

  /// Linked, and not readable this minute.
  Widget _unreachable(BuildContext context, double gutter) => CentredMessage(
    gutter: gutter,
    children: <Widget>[
      Text(
        'Thermostat',
        style: context.text.sectionHeader,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: HearthSpacing.sm),
      Text(
        _error ?? 'The thermostat did not answer.',
        style: context.text.body.copyWith(color: context.colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: HearthSpacing.lg),
      SizedBox(
        height: HearthTouch.minTarget,
        child: OutlinedButton(
          onPressed: _busy ? null : () => unawaited(_refresh()),
          child: const Text('Try again'),
        ),
      ),
    ],
  );

  Widget _unlinked(BuildContext context, double gutter) {
    final HearthColors colors = context.colors;
    return ListView(
      padding: EdgeInsets.all(gutter),
      children: <Widget>[
        Text('Thermostat', style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          _needsRelink
              ? 'Google stopped accepting Hearth’s connection. Connect '
                    'again to get the thermostat back.'
              : 'Connect your Google account and Hearth can read and set the '
                    'temperature from here.',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          _Message(text: _error!, isError: true),
        ],
        const SizedBox(height: HearthSpacing.lg),
        SizedBox(
          height: HearthTouch.minTarget,
          child: FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(
              _busy
                  ? 'Just a moment…'
                  : (_waiting ? 'Open Google again' : 'Connect Google Nest'),
            ),
          ),
        ),
        if (_waiting) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          Text(
            'Finish in your browser, then come back. Tick the thermostat in '
            'Google\u2019s device list — it is easy to miss, and without it '
            'there is nothing for Hearth to control.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// What it is, and what the system is doing about it.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.state, this.readAt});

  final ThermostatState state;
  final DateTime? readAt;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final (IconData icon, String word) = switch (state.hvac) {
      HvacStatus.heating => (Icons.local_fire_department_outlined, 'Heating'),
      HvacStatus.cooling => (Icons.ac_unit_outlined, 'Cooling'),
      HvacStatus.off => (Icons.remove, 'Idle'),
      HvacStatus.unknown => (Icons.help_outline, 'Unknown'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(state.label, style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.xs),
        Semantics(
          label: 'It is ${Temp.displayF(state.ambientC)} degrees',
          excludeSemantics: true,
          child: Text(
            '${Temp.displayF(state.ambientC)}°',
            style: context.text.sectionHeader.copyWith(fontSize: 56),
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        // Wrapped rather than a Row: what the system is doing and how humid
        // the house is are two independent phrases, and at three times the
        // text they do not fit on one line of a small phone. Dynamic type is
        // honoured, not capped (spec §6.3).
        Wrap(
          spacing: HearthSpacing.md,
          runSpacing: HearthSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Icon *and* word. What the system is doing is never carried
                // by a colour alone (spec §6.3).
                Icon(icon, size: 18, color: colors.textSecondary),
                const SizedBox(width: HearthSpacing.xs),
                Text(
                  word,
                  style: context.text.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (state.humidityPercent != null)
              Text(
                '${state.humidityPercent!.round()}% humidity',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
        if (readAt != null) ...<Widget>[
          const SizedBox(height: HearthSpacing.xs),
          Text(
            'Updated ${_ago(readAt!)}',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  static String _ago(DateTime at) {
    final Duration since = DateTime.now().difference(at);
    if (since.inMinutes < 1) return 'just now';
    if (since.inMinutes == 1) return 'a minute ago';
    if (since.inHours < 1) return '${since.inMinutes} minutes ago';
    return 'a while ago';
  }
}

/// One setpoint, with the two controls that move it.
class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.valueC,
    required this.busy,
    required this.onStep,
  });

  final String label;
  final double valueC;
  final bool busy;
  final ValueChanged<int> onStep;

  @override
  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final int shown = Temp.displayF(valueC);

    // The label on its own line, always. Sharing a row with a section-header
    // number and two kitchen-sized buttons fits at one text scale and
    // overflows at two — dynamic type is honoured rather than capped
    // (spec §6.3), so the layout gives way instead of the words.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Hidden from a screen reader, because the adjustable below carries
        // the same word as its label. Left in, the row announces itself as
        // "Target, Target, 68 degrees" — the word twice and the number once.
        ExcludeSemantics(
          child: Text(
            label,
            style: context.text.label.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        Row(
          children: <Widget>[
            _Step(
              icon: Icons.remove,
              tooltip: 'Cooler',
              semanticLabel: 'Cooler. ${shown - 1} degrees.',
              onPressed: busy ? null : () => onStep(-1),
            ),
            // The number is the adjustable, so a screen reader's rotor works
            // on it without anybody having to find the two buttons beside it
            // (§6.3).
            Expanded(
              child: Semantics(
                label: label,
                value: '$shown degrees Fahrenheit',
                increasedValue: '${shown + 1} degrees Fahrenheit',
                decreasedValue: '${shown - 1} degrees Fahrenheit',
                onIncrease: busy ? null : () => onStep(1),
                onDecrease: busy ? null : () => onStep(-1),
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.sm,
                  ),
                  child: Text(
                    '$shown°',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: context.text.sectionHeader,
                  ),
                ),
              ),
            ),
            _Step(
              icon: Icons.add,
              tooltip: 'Warmer',
              semanticLabel: 'Warmer. ${shown + 1} degrees.',
              onPressed: busy ? null : () => onStep(1),
            ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: HearthTouch.kitchenTarget,
    height: HearthTouch.kitchenTarget,
    child: Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    ),
  );
}

/// The modes this thermostat actually offers.
class _Modes extends StatelessWidget {
  const _Modes({required this.state, required this.onPick});

  final ThermostatState state;
  final ValueChanged<ThermostatMode> onPick;

  @override
  Widget build(BuildContext context) {
    final List<ThermostatMode> offered = <ThermostatMode>[
      for (final ThermostatMode mode in ThermostatMode.values)
        if (mode != ThermostatMode.unknown &&
            state.availableModes.contains(mode))
          mode,
    ];
    if (offered.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: HearthSpacing.sm,
      runSpacing: HearthSpacing.sm,
      children: <Widget>[
        for (final ThermostatMode mode in offered)
          ChoiceChip(
            label: Text(mode.label),
            selected: state.mode == mode,
            // Selected carries a tick as well as a fill, so the choice is not
            // made by colour alone (spec §6.3).
            avatar: state.mode == mode
                ? const Icon(Icons.check, size: 18)
                : null,
            onSelected: (_) => onPick(mode),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: context.text.label),
    subtitle: Text(
      detail,
      style: context.text.metadata.copyWith(color: context.colors.textMuted),
    ),
    value: value,
    onChanged: onChanged,
  );
}

class _Footer extends StatefulWidget {
  const _Footer({
    required this.link,
    required this.busy,
    required this.onDisconnect,
  });

  final ThermostatLink? link;
  final bool busy;
  final Future<void> Function() onDisconnect;

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  /// Asked once before it happens, inline rather than in a dialog.
  ///
  /// Disconnecting destroys the household's credential and the other phone
  /// loses the thermostat too, which is worth a second press — and a second
  /// press is cheaper than a modal nobody can reach in a widget test.
  bool _sure = false;

  /// And the question expires.
  ///
  /// Left armed, a stray press minutes later destroys the credential with no
  /// second thought asked for — the confirmation would have been spent on a
  /// press nobody remembers making.
  static const Duration _armedFor = Duration(seconds: 5);
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _arm() {
    setState(() => _sure = true);
    _disarm?.cancel();
    _disarm = Timer(_armedFor, () {
      if (mounted) setState(() => _sure = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ThermostatLink? link = widget.link;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (link?.linkedAt != null)
          Text(
            link!.linkedByYou
                ? 'You connected this thermostat.'
                : 'Connected by someone else in the house.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        const SizedBox(height: HearthSpacing.sm),
        SizedBox(
          height: HearthTouch.minTarget,
          child: OutlinedButton(
            onPressed: widget.busy
                ? null
                : () {
                    if (!_sure) {
                      _arm();
                      return;
                    }
                    _disarm?.cancel();
                    unawaited(widget.onDisconnect());
                  },
            child: Text(
              _sure ? 'Really disconnect? Both phones lose it.' : 'Disconnect',
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Never colour alone.
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: isError ? colors.accent : colors.textMuted,
          ),
          const SizedBox(width: HearthSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.body.copyWith(
                color: isError ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
