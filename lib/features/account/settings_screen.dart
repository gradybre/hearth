import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/shell/launch_target.dart';
import '../../app/sync_controller.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/theme_choice.dart';
import '../../data/adapters/data_export.dart';
import '../../data/auth/auth_gateway.dart';
import '../../data/sync/sync_engine.dart';

/// Everything that is set rather than cooked: who you are, how Hearth looks,
/// who you cook with, and how to leave (spec §5.1, §6.1, §7.4).
///
/// Grouped the way a settings screen is read rather than the order the
/// features were built in. Identity first because it answers "whose app is
/// this"; appearance next because it is the one people come here to poke;
/// the household after, since it is set up once and then forgotten; sync and
/// export below, which are consulted rather than changed; and signing out
/// last, alone, where nothing else can be hit by mistake.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authGatewayProvider).joinHousehold(_code.text);
      if (mounted) {
        _code.clear();
        setState(
          () => _notice =
              'Joined. Their recipes and foods are yours now, and yours are '
              'theirs.',
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'Your recipes stay in the household. You will need your '
              'password to come back.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await ref.read(authGatewayProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthAccount? account = ref.watch(accountProvider).value;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;
    final String email = account?.email ?? '';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings', style: context.text.label),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            HearthSpacing.lg,
            gutter,
            HearthSpacing.xxl,
          ),
          children: <Widget>[
            SettingsSection(
              title: 'Account',
              children: <Widget>[
                if (email.isNotEmpty)
                  SettingsValueRow(
                    icon: Icons.person_outline,
                    title: 'Signed in as',
                    value: email,
                  ),
                // The profile is per-user and private, which is exactly why
                // it sits here rather than anywhere shared (§8.2).
                SettingsNavRow(
                  icon: Icons.restaurant_outlined,
                  title: 'Your food profile',
                  subtitle:
                      'Allergies, dislikes, how you like to eat. Private to '
                      'you.',
                  semanticLabel:
                      'Your food profile. What Hearth reads when it writes '
                      'you a recipe.',
                  onTap: () => context.push('/profile'),
                ),
                // Only where there is an address to send to. An unconfigured
                // build has an account with no email and no backend, and a
                // button that could only ever fail is worse than no button.
                if (email.isNotEmpty) _PasswordReset(email: email),
              ],
            ),
            const SizedBox(height: HearthSpacing.xl),
            const _Appearance(),
            const SizedBox(height: HearthSpacing.xl),
            SettingsSection(
              title: 'Cook together',
              blurb:
                  'Share this code with the other person. They enter it below '
                  'and your libraries become one — including everything '
                  'either of you has already added.',
              children: <Widget>[
                if (account?.shareCode != null)
                  _ShareCode(code: account!.shareCode!),
                Padding(
                  padding: const EdgeInsets.all(HearthSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Join a household',
                        style: context.text.label.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: HearthSpacing.sm),
                      TextField(
                        controller: _code,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.characters,
                        style: context.text.body,
                        onSubmitted: (_) => _join(),
                        decoration: InputDecoration(
                          labelText: 'Their code',
                          hintText: 'ABCD2345',
                          filled: true,
                          fillColor: colors.surfaceSunken,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              HearthRadius.md,
                            ),
                            borderSide: BorderSide(color: colors.outline),
                          ),
                        ),
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: HearthSpacing.md),
                        SettingsMessage(text: _error!, isError: true),
                      ],
                      if (_notice != null) ...<Widget>[
                        const SizedBox(height: HearthSpacing.md),
                        SettingsMessage(text: _notice!, isError: false),
                      ],
                      const SizedBox(height: HearthSpacing.md),
                      SizedBox(
                        height: HearthTouch.minTarget,
                        child: FilledButton(
                          onPressed: _busy ? null : _join,
                          child: Text(_busy ? 'Just a moment…' : 'Join'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.xl),
            const _SyncPanel(),
            const SizedBox(height: HearthSpacing.xl),
            const _YourData(),
            const SizedBox(height: HearthSpacing.xl),
            // Last and on its own. Nothing sits under it to be hit by
            // mistake, and nothing above it is destructive.
            SettingsGroup(
              children: <Widget>[
                SettingsActionRow(
                  icon: Icons.logout,
                  title: 'Sign out',
                  subtitle: 'Your recipes stay in the household.',
                  isDestructive: true,
                  onTap: _signOut,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── The pieces a settings screen is made of ──────────────────────────────────

/// A titled group of related settings.
///
/// The header sits outside the card, the way a native settings screen puts it
/// — so the card reads as one object and the label as the name of that object
/// rather than as its first row.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    this.blurb,
    super.key,
  });

  final String title;

  /// A sentence under the header, for a group that needs explaining before it
  /// is touched rather than after.
  final String? blurb;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: HearthSpacing.xs),
          // A heading for a screen reader too, so the sections can be jumped
          // between rather than read through (spec §6.3).
          child: Semantics(
            header: true,
            // A node of its own, not an annotation folded into whatever
            // encloses it. Without this the header, the blurb and every row
            // under it collapse into a single unreadable announcement — which
            // is what a settings screen must never sound like (spec §6.3).
            container: true,
            child: Text(title, style: context.text.sectionHeader),
          ),
        ),
        if (blurb case final String blurb) ...<Widget>[
          const SizedBox(height: HearthSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: HearthSpacing.xs),
            child: Text(
              blurb,
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: HearthSpacing.sm),
        SettingsGroup(children: children),
      ],
    );
  }
}

/// The card the rows of a section sit in, hairlines between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      // So a row's ink and highlight stay inside the rounded corner.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: colors.outline),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row that states something rather than doing something.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      label: '$title $value',
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: colors.textMuted),
            const SizedBox(width: HearthSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.xxs),
                  Text(value, style: context.text.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that goes somewhere.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// What activating this says out loud. Says what the destination *is*
  /// rather than repeating the visible word (spec §6.3).
  final String? semanticLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SettingsTappableRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    semanticLabel: semanticLabel,
    trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
    onTap: onTap,
  );
}

/// A row that does something here and now.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.semanticLabel,
    this.isDestructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? semanticLabel;

  /// Draws the row in the error tone. Never the only signal: the row keeps
  /// its own icon and its words say what it does (spec §6.3).
  final bool isDestructive;

  /// Null while the action is already running. The row goes quiet and stops
  /// answering rather than pretending — a second tap on an export in flight
  /// builds the file twice.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _SettingsTappableRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    semanticLabel: semanticLabel,
    tone: isDestructive ? context.colors.error : null,
    onTap: onTap,
  );
}

class _SettingsTappableRow extends StatelessWidget {
  const _SettingsTappableRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.semanticLabel,
    this.trailing,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? semanticLabel;
  final Widget? trailing;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool enabled = onTap != null;
    // Muted rather than merely paler: a row that cannot be activated is also
    // reported as disabled to a screen reader, so the dimming is a second
    // signal and never the only one (spec §6.3).
    final Color foreground = enabled
        ? (tone ?? colors.textPrimary)
        : colors.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? <String?>[title, subtitle].nonNulls.join('. '),
      onTap: onTap,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 20,
                    color: enabled
                        ? (tone ?? colors.textSecondary)
                        : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: context.text.body.copyWith(color: foreground),
                        ),
                        if (subtitle case final String subtitle) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            subtitle,
                            style: context.text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing case final Widget trailing) ...<Widget>[
                    const SizedBox(width: HearthSpacing.sm),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of feedback, spoken as well as shown.
class SettingsMessage extends StatelessWidget {
  const SettingsMessage({required this.text, required this.isError, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // An icon as well as the colour, so a problem and a note are not
          // told apart by hue alone (spec §6.3).
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: isError ? colors.error : colors.textSecondary,
          ),
          const SizedBox(width: HearthSpacing.sm),
          Expanded(child: Text(text, style: context.text.body)),
        ],
      ),
    );
  }
}

// ── Appearance (spec §6.1, §6.2) ─────────────────────────────────────────────

/// How Hearth looks, and where it opens.
///
/// Two groups rather than one list: they are both answers to "how is this
/// device set up", but a theme and a landing screen are not alternatives to
/// each other, and seven tickable rows in a single card would read as one
/// question with seven wrong answers.
class _Appearance extends StatelessWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _ThemeChoiceSection(),
      // Closer than the gap between top-level sections: these two belong
      // together, and the spacing is what says so.
      SizedBox(height: HearthSpacing.lg),
      _LaunchTargetSection(),
    ],
  );
}

/// Light, dark, or whatever the device is doing.
///
/// Three rows rather than a segmented control: three labels side by side stop
/// fitting the moment dynamic type is turned up, and honouring type is not
/// optional (spec §6.3). A list of options with a check against the chosen
/// one grows downwards instead, which it can always afford to do.
class _ThemeChoiceSection extends ConsumerStatefulWidget {
  const _ThemeChoiceSection();

  @override
  ConsumerState<_ThemeChoiceSection> createState() => _ThemeChoiceState();
}

class _ThemeChoiceState extends ConsumerState<_ThemeChoiceSection> {
  /// Set when a choice could not be written and was taken back. The tick moves
  /// back on its own; without a word here the tap would simply look as though
  /// it had not happened.
  bool _unsaved = false;

  Future<void> _choose(ThemeChoice choice) async {
    setState(() => _unsaved = false);
    try {
      await ref.read(themeChoiceProvider.notifier).choose(choice);
    } on Object {
      if (mounted) setState(() => _unsaved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Until the stored choice is read, the device is what is actually on
    // screen — so that is what the list should show as chosen.
    final ThemeChoice current =
        ref.watch(themeChoiceProvider).value ?? ThemeChoice.system;

    return SettingsSection(
      title: 'Appearance',
      children: <Widget>[
        for (final ThemeChoice choice in ThemeChoice.values)
          SettingsChoiceRow(
            label: choice.label,
            blurb: choice.blurb,
            icon: choice.icon,
            selected: choice == current,
            onTap: () => _choose(choice),
          ),
        if (_unsaved) const _CouldNotSave(),
      ],
    );
  }
}

/// Which screen Hearth opens on (spec §6.2).
///
/// The options are the home screen plus every built section, read off the
/// section registry — so a pillar added later offers itself here without this
/// screen being touched.
class _LaunchTargetSection extends ConsumerStatefulWidget {
  const _LaunchTargetSection();

  @override
  ConsumerState<_LaunchTargetSection> createState() => _LaunchTargetState();
}

class _LaunchTargetState extends ConsumerState<_LaunchTargetSection> {
  bool _unsaved = false;

  Future<void> _choose(LaunchTarget target) async {
    setState(() => _unsaved = false);
    try {
      await ref.read(launchTargetProvider.notifier).choose(target);
    } on Object {
      if (mounted) setState(() => _unsaved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Home until the device says otherwise, which is also what an unread
    // preference means.
    final LaunchTarget current =
        ref.watch(launchTargetProvider).value ?? LaunchTarget.home;

    return SettingsSection(
      title: 'Opens on',
      blurb:
          'Where Hearth starts when you open it. This device only — it does '
          'not move anyone else\'s app.',
      children: <Widget>[
        for (final LaunchTarget target in LaunchTarget.options)
          SettingsChoiceRow(
            label: target.label,
            blurb: target.blurb,
            icon: target.icon,
            selected: target == current,
            onTap: () => _choose(target),
          ),
        if (_unsaved) const _CouldNotSave(),
      ],
    );
  }
}

/// What a device that refused the write gets told.
class _CouldNotSave extends StatelessWidget {
  const _CouldNotSave();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(HearthSpacing.md),
    child: SettingsMessage(
      text:
          'That could not be saved on this device, so Hearth has gone back '
          'to the last choice that was.',
      isError: true,
    ),
  );
}

/// One answer in a list of mutually exclusive ones, ticked when it is the one
/// in force.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String blurb;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '$label. $blurb',
      onTap: onTap,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label, style: context.text.body),
                        const SizedBox(height: HearthSpacing.xxs),
                        Text(
                          blurb,
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  // The tick is the signal, not the colour of the row: which
                  // option is chosen must survive being seen in greyscale
                  // (spec §6.3).
                  if (selected)
                    Icon(Icons.check, size: 20, color: colors.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── The password (spec §8.3) ─────────────────────────────────────────────────

/// Asking for a link to set a new password.
///
/// Hearth never handles the password itself — Supabase mints and mails the
/// link, and §8.3 rules out doing any of that here. What this row owns is the
/// asking, and saying where it ends: no `redirectTo` is passed and nothing
/// listens for a recovery session, so the link opens the project's own web
/// page in a browser. The copy says so rather than promising a step in the
/// app that does not exist (spec §8.3).
class _PasswordReset extends ConsumerStatefulWidget {
  const _PasswordReset({required this.email});

  final String email;

  @override
  ConsumerState<_PasswordReset> createState() => _PasswordResetState();
}

class _PasswordResetState extends ConsumerState<_PasswordReset> {
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _send() async {
    if (_busy) return;

    // Asked first because it sends mail to a real inbox: a stray tap on a
    // settings list should not put a password-reset email in front of
    // someone, and the message is the only place the address is confirmed.
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Send a reset link?'),
            content: Text(
              'We will email ${widget.email} a link for setting a new '
              'password. The link opens a web page in your browser — Hearth '
              'cannot set the password itself yet. You stay signed in here '
              'either way.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Send link'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      // Named as the signed-in account's own address, which is the one place
      // in the app that can honestly claim it: a refusal here can say why,
      // because it cannot tell this person anything about themselves they do
      // not already know.
      await ref
          .read(authGatewayProvider)
          .sendPasswordReset(widget.email, ownAddress: true);
      if (mounted) {
        setState(
          () => _notice =
              'On its way to ${widget.email}. The link opens a web page in '
              'your browser — Hearth cannot set the new password itself yet.',
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SettingsActionRow(
        icon: Icons.key_outlined,
        title: _busy ? 'Just a moment…' : 'Reset password',
        subtitle:
            'We email you a link. It is used in a browser, not in '
            'Hearth, and nothing changes until you use it.',
        onTap: _busy ? null : _send,
      ),
      if (_error != null || _notice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HearthSpacing.md,
            0,
            HearthSpacing.md,
            HearthSpacing.md,
          ),
          child: SettingsMessage(
            text: _error ?? _notice!,
            isError: _error != null,
          ),
        ),
    ],
  );
}

// ── Cook together (spec §5.1) ────────────────────────────────────────────────

/// The code, big enough to read aloud across a kitchen.
class _ShareCode extends StatelessWidget {
  const _ShareCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          border: Border.all(color: colors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.lg),
          child: Row(
            children: <Widget>[
              // Around the code alone, never around the row: excluding
              // descendants is what makes the code readable letter by letter,
              // and wrapped any wider it also swallowed the copy button — a
              // screen reader heard the code and had no way to copy it
              // (spec §6.3).
              Expanded(
                child: Semantics(
                  label: 'Your household code is ${code.split('').join(' ')}',
                  container: true,
                  excludeSemantics: true,
                  child: Text(
                    code,
                    style: context.text.recipeTitle.copyWith(
                      // The alphabet already omits I, L, O, 0 and 1; the wide
                      // letter spacing is for reading it out loud.
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy code',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Syncing (spec §7.1) ──────────────────────────────────────────────────────

/// What sync last did, and a way to ask it again.
///
/// A sync that fails quietly is a sync nobody fixes: writes queue up, a
/// partner's recipes never arrive, and the only symptom is an app that seems
/// slightly out of date. Saying so plainly is the difference between a bug
/// someone reports and one they live with.
class _SyncPanel extends ConsumerWidget {
  const _SyncPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final SyncStatus status = ref.watch(syncControllerProvider);
    final int queued = ref.watch(pendingWriteCountProvider).value ?? 0;

    return SettingsSection(
      title: 'Syncing',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(HearthSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                status.hasProblem
                    ? Icons.error_outline
                    : status.isSyncing
                    ? Icons.sync
                    : Icons.cloud_done_outlined,
                size: 20,
                color: status.hasProblem ? colors.error : colors.textSecondary,
              ),
              const SizedBox(width: HearthSpacing.md),
              Expanded(
                child: Text(
                  _describe(status, queued),
                  style: context.text.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SettingsActionRow(
          icon: Icons.sync,
          title: 'Sync now',
          onTap: status.isSyncing
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
        ),
      ],
    );
  }

  static String _describe(SyncStatus status, int queued) {
    if (status.isSyncing) return 'Syncing…';
    if (status.error != null) return 'Last sync failed: ${status.error}';

    final SyncResult? result = status.result;
    if (result == null) {
      return queued == 0
          ? 'Nothing waiting to send.'
          : '$queued waiting to send.';
    }
    if (result.stoppedBecauseOffline) {
      return '$queued waiting — no connection just now.';
    }
    if (result.failed > 0) {
      return '${result.failed} could not be sent. They are still saved here.';
    }

    final int pulled = status.pulled?.applied ?? 0;
    return pulled == 0
        ? 'Everything is up to date.'
        : 'Up to date — brought down $pulled '
              '${pulled == 1 ? 'change' : 'changes'}.';
  }
}

// ── Your data (spec §7.4) ────────────────────────────────────────────────────

/// Taking everything with you.
///
/// Cheap insurance and on-brand for a personal tool: the point is that Hearth
/// can be walked away from. It sits just above Sign out, which is where a
/// person who is thinking about leaving will already be looking.
class _YourData extends ConsumerStatefulWidget {
  const _YourData();

  @override
  ConsumerState<_YourData> createState() => _YourDataState();
}

class _YourDataState extends ConsumerState<_YourData> {
  bool _busy = false;
  String? _error;

  Future<void> _export() async {
    final HearthAccount? account = ref.read(accountProvider).value;
    if (account == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ExportedFile file = await ref
          .read(dataExportProvider)
          .build(householdId: account.householdId, userId: account.userId);
      await ref.read(fileShareProvider).share(file);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Your data',
    blurb:
        'Everything Hearth holds — your recipes, foods, plans and every meal '
        'you have logged — as one file you keep. Recipe photos are not '
        'included.',
    children: <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsActionRow(
            icon: Icons.ios_share,
            title: _busy ? 'Gathering it up…' : 'Export my data',
            onTap: _busy ? null : _export,
          ),
          if (_error case final String error)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HearthSpacing.md,
                0,
                HearthSpacing.md,
                HearthSpacing.md,
              ),
              child: SettingsMessage(text: error, isError: true),
            ),
        ],
      ),
    ],
  );
}
