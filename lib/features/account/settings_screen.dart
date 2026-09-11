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
import '../../core/build_info.dart';
import '../../data/adapters/data_export.dart';
import '../../data/auth/auth_gateway.dart';
import '../../data/sync/sync_engine.dart';
import 'settings_kit.dart';

/// Everything that is set rather than cooked, as an index (review §7.8).
///
/// It used to be all of it at once: seven groups, thirteen tickable rows and
/// a sentence under each, which measured 1,920 points on a phone and 6,641 on
/// a small phone at twice the text — thirteen screens, with the way out of
/// the app at the bottom of them. Now each group is one row that *states*
/// where it stands, and the changing happens on the page behind it.
///
/// The order is how a settings screen is read rather than how the features
/// were built: identity first because it answers "whose app is this"; the
/// household next, since it is set up once and then forgotten; the two
/// device choices after that; and sync and export below, which are consulted
/// rather than changed.
///
/// **Sign out stays here**, last and alone. Two taps away would be worse, not
/// better: it is the one thing on this screen somebody needs in a hurry, and
/// it is already isolated so nothing above it can be hit by mistake. Burying
/// a destructive control is not the same as protecting it.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    if (!confirmed) return;
    // Before the sign-out, not after: once the session is gone the providers
    // this reads are rebuilding, and a checkpoint left behind is one nobody
    // will think to clear later. A pass already in flight notices the
    // clearing and abandons rather than writing its checkpoint back.
    //
    // Guarded, because this is a step between the user and the thing they
    // actually asked for. A device that cannot clear its checkpoints must
    // still be able to sign out; the worst case is a stale checkpoint, and
    // staying signed in against someone's wishes is worse than that.
    try {
      await ref.read(syncCheckpointsProvider).forgetEverything();
    } on Object {
      // Deliberately swallowed: see above.
    }
    await ref.read(authGatewayProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final HearthAccount? account = ref.watch(accountProvider).value;
    final String email = account?.email ?? '';

    return SettingsPage(
      title: 'Settings',
      children: <Widget>[
        SettingsGroup(
          children: <Widget>[
            SettingsNavRow(
              icon: Icons.person_outline,
              title: 'Account',
              // The address, when there is one. An unconfigured build has an
              // account with no email and no backend behind it, and the page
              // behind this row says so rather than the row pretending.
              value: email.isEmpty ? 'This device' : email,
              onTap: () => context.push('/settings/account'),
            ),
            SettingsNavRow(
              icon: Icons.people_outline,
              title: 'Cook together',
              value: account?.shareCode == null
                  ? 'Not sharing yet'
                  : 'Your code ${account!.shareCode}',
              onTap: () => context.push('/settings/household'),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.xl),
        SettingsGroup(
          children: <Widget>[
            SettingsNavRow(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              value: ref.watch(themeChoiceProvider).value?.label ?? '',
              onTap: () => context.push('/settings/appearance'),
            ),
            SettingsNavRow(
              icon: Icons.flag_outlined,
              title: 'Opens on',
              value: ref.watch(launchTargetProvider).value?.label ?? '',
              onTap: () => context.push('/settings/start'),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.xl),
        SettingsGroup(
          children: <Widget>[
            SettingsNavRow(
              icon: Icons.cloud_done_outlined,
              title: 'Syncing',
              // The one fact a bug report starts from, on the index rather
              // than a page in: a device that has not been in step since
              // Tuesday should not look like one that synced a minute ago.
              value: switch (ref.watch(lastFullSyncProvider)) {
                AsyncValue<DateTime?>(:final DateTime value) =>
                  'Last full sync ${describeAgo(value)}',
                AsyncValue<DateTime?>(isLoading: true) => '',
                _ => 'No full sync yet',
              },
              onTap: () => context.push('/settings/sync'),
            ),
            SettingsNavRow(
              icon: Icons.download_outlined,
              title: 'Your data',
              value: 'Export everything',
              onTap: () => context.push('/settings/data'),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.xl),
        // Last and on its own. Nothing sits under it to be hit by mistake,
        // and nothing above it is destructive.
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
    );
  }
}

// ── The six pages behind it ──────────────────────────────────────────────────

/// Who you are signed in as, and the two things you can do about it.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthAccount? account = ref.watch(accountProvider).value;
    final String email = account?.email ?? '';

    return SettingsPage(
      title: 'Account',
      children: <Widget>[
        SettingsGroup(
          children: <Widget>[
            SettingsValueRow(
              icon: Icons.person_outline,
              title: 'Signed in as',
              // A build with no backend has an account and no address; saying
              // "this device" is true, and leaving the row out would make the
              // page look broken.
              value: email.isEmpty ? 'This device only' : email,
            ),
            // The profile is per-user and private, which is exactly why it
            // sits here rather than anywhere shared (§8.2).
            SettingsNavRow(
              icon: Icons.restaurant_outlined,
              title: 'Your food profile',
              subtitle:
                  'Allergies, dislikes, how you like to eat. Private to you.',
              semanticLabel:
                  'Your food profile. What Hearth reads when it writes you a '
                  'recipe.',
              onTap: () => context.push('/profile'),
            ),
            // Only where there is an address to send to. A button that could
            // only ever fail is worse than no button.
            if (email.isNotEmpty) _PasswordReset(email: email),
          ],
        ),
      ],
    );
  }
}

/// The share code, and the field that joins somebody else's household.
class HouseholdSettingsScreen extends ConsumerStatefulWidget {
  const HouseholdSettingsScreen({super.key});

  @override
  ConsumerState<HouseholdSettingsScreen> createState() =>
      _HouseholdSettingsState();
}

class _HouseholdSettingsState extends ConsumerState<HouseholdSettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthAccount? account = ref.watch(accountProvider).value;

    return SettingsPage(
      title: 'Cook together',
      // Kept word for word rather than trimmed with the rest of the prose
      // (§6.2.4): joining merges two libraries and cannot be undone here, so
      // it has to be readable before the button rather than after it.
      blurb:
          'Share this code with the other person. They enter it below and '
          'your libraries become one — including everything either of you has '
          'already added.',
      children: <Widget>[
        SettingsGroup(
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
                        borderRadius: BorderRadius.circular(HearthRadius.md),
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
      ],
    );
  }
}

/// Light, dark, or whatever the device is doing.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Appearance',
    children: <Widget>[_ThemeChoiceSection()],
  );
}

/// Which screen Hearth opens on.
class StartSettingsScreen extends StatelessWidget {
  const StartSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Opens on',
    // The half of this page's old prose that survives §6.2.4's cut. It is not
    // narration: it is the answer to "will this change my partner's phone",
    // and the answer is no.
    blurb:
        'Where Hearth starts when you open it. This device only — it does not '
        'move anyone else\'s app.',
    children: <Widget>[_LaunchTargetSection()],
  );
}

/// What sync last did, and a way to ask it again.
class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsPage(title: 'Syncing', children: <Widget>[_SyncPanel()]);
}

/// Taking everything with you.
class DataSettingsScreen extends StatelessWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    title: 'Your data',
    blurb:
        'Everything Hearth holds — your recipes, foods, plans and every meal '
        'you have logged — as one file you keep. Recipe photos are not '
        'included.',
    children: <Widget>[_YourData()],
  );
}

// ── Appearance (spec §6.1, §6.2) ─────────────────────────────────────────────

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

    // A group with no header of its own: the page is called Appearance, and
    // a serif heading repeating that under the title is §6.2.1's complaint
    // about headings of similar strength.
    return SettingsGroup(
      children: <Widget>[
        for (final ThemeChoice choice in ThemeChoice.values)
          SettingsChoiceRow(
            label: choice.label,
            // No sentence under the word. "Light by day, dark when your
            // device says so" explains "Follow the device" to somebody who
            // has just read "Follow the device" (review §6.2.4).
            icon: choice.icon,
            selected: choice == current,
            onTap: () => _choose(choice),
          ),
        if (_unsaved) const SettingsCouldNotSave(),
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

    // The page carries the title and the one sentence worth keeping; see
    // `StartSettingsScreen`.
    return SettingsGroup(
      children: <Widget>[
        for (final LaunchTarget target in LaunchTarget.options)
          SettingsChoiceRow(
            label: target.label,
            icon: target.icon,
            selected: target == current,
            onTap: () => _choose(target),
          ),
        if (_unsaved) const SettingsCouldNotSave(),
      ],
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

    return SettingsGroup(
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
        // The two facts a bug report needs and neither of which was here: when
        // this device and the server were last in step, and which build is
        // asking. Everything above says what the *last attempt* did; a device
        // that has not managed a full pass since Tuesday looks identical to
        // one that synced a minute ago, because the last attempt failed the
        // same way both times.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HearthSpacing.md,
            0,
            HearthSpacing.md,
            HearthSpacing.md,
          ),
          child: Text(
            <String>[
              // Loading is not the same answer as "never", and saying it is
              // would be this panel telling the exact kind of lie it exists
              // to prevent: a device that syncs hourly reporting "no full
              // sync yet" for the frame somebody screenshots. While the
              // answer is still being read, it says nothing about it.
              ?switch (ref.watch(lastFullSyncProvider)) {
                AsyncValue<DateTime?>(:final DateTime value) =>
                  'Last full sync ${describeAgo(value)}',
                AsyncValue<DateTime?>(isLoading: true) => null,
                _ => 'No full sync yet on this device',
              },
              'Hearth ${BuildInfo.appVersion}',
              'data ${BuildInfo.schemaVersion}',
              'export ${BuildInfo.exportFormatVersion}',
            ].join(' · '),
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ),
        SettingsActionRow(
          icon: Icons.sync,
          title: 'Sync now',
          onTap: status.isSyncing
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
        ),
        // Only when there is something to press it for. A write that has
        // stopped trying is otherwise stuck for good, and so is its record: a
        // pull will not overwrite something unsent, which is right, but it
        // leaves two devices quietly disagreeing with no way back. An edit
        // re-issues an upsert; a deletion cannot be re-issued, because the
        // row is already gone from the screen.
        if ((status.result?.stranded ?? 0) > 0)
          SettingsActionRow(
            icon: Icons.refresh,
            title: 'Try the stuck changes again',
            onTap: status.isSyncing
                ? null
                : () async {
                    await ref.read(pendingWriteStoreProvider).retryStranded();
                    await ref.read(syncControllerProvider.notifier).sync();
                  },
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
    // The pull's answer counts too. Push only learns it is offline by
    // attempting a write, and a queue holding nothing but writes waiting out
    // a backoff never enters that loop — so without this, tapping Sync now in
    // a lift reported everything as up to date with a change still unsent.
    if (result.stoppedBecauseOffline ||
        (status.pulled?.stoppedBecauseOffline ?? false)) {
      return '$queued waiting — no connection just now.';
    }
    // Both, when both. A stranded write has stopped being tried, so `failed`
    // goes back to zero on the next pass and it would vanish from the panel
    // if it were reported second — but reporting only the stranded ones told
    // somebody with six fresh failures that the problem was one change.
    if (result.stranded > 0 || result.failed > 0) {
      final int n = result.stranded;
      final String stuck = n == 1
          ? '1 change has stopped trying'
          : '$n changes have stopped trying';
      if (n > 0 && result.failed > 0) {
        return '$stuck, and ${result.failed} more could not be sent. '
            'They are all still saved here.';
      }
      if (n > 0) {
        return '$stuck, after several goes. '
            '${n == 1 ? 'It is' : 'They are'} still saved here.';
      }
      return '${result.failed} could not be sent. They are still saved here.';
    }

    // Before "up to date", because an abandoned pass is neither up to date
    // nor a failure: it started asking for one account and finished under
    // another, so it threw its answers away and will ask again.
    if (status.pulled?.abandonedScope ?? false) {
      return 'The account changed while syncing. Starting again.';
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
  // The words stay: they say what the file holds and what it does not, and
  // that is a hand-off out of the app (CLAUDE.md rule 4). They move up to the
  // page's own blurb so the group underneath is just the action.
  Widget build(BuildContext context) {
    // Watched, not read at the moment of the tap. `_export` needs the
    // household and the user to build a file at all, and on its own page
    // nothing else on screen subscribes to the account — so the first read
    // was the tap's, the answer was still loading, and the button did
    // nothing at all and said nothing about it. Watching resolves it while
    // the page is being looked at, and until it does the row is visibly
    // unavailable rather than quietly inert.
    final HearthAccount? account = ref.watch(accountProvider).value;

    return SettingsGroup(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SettingsActionRow(
              icon: Icons.ios_share,
              title: _busy ? 'Gathering it up…' : 'Export my data',
              onTap: _busy || account == null ? null : _export,
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
}
