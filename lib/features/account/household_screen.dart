import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/sync_controller.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/data_export.dart';
import '../../data/auth/auth_gateway.dart';
import '../../data/sync/sync_engine.dart';

/// The household: who you are, who can join, and how to leave (spec §5.1).
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
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

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Household', style: context.text.label),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            if (account != null && account.email.isNotEmpty) ...<Widget>[
              Text('Signed in as', style: context.text.metadata),
              const SizedBox(height: HearthSpacing.xxs),
              Text(account.email, style: context.text.body),
              const SizedBox(height: HearthSpacing.xl),
            ],
            // The profile is per-user and private, which is exactly why it
            // sits on this screen rather than anywhere shared (§8.2).
            Semantics(
              button: true,
              label:
                  'Your food profile. What Hearth reads when it writes you '
                  'a recipe.',
              onTap: () => context.push('/profile'),
              excludeSemantics: true,
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(HearthRadius.md),
                child: InkWell(
                  onTap: () => context.push('/profile'),
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(HearthRadius.md),
                      border: Border.all(color: colors.outline),
                    ),
                    padding: const EdgeInsets.all(HearthSpacing.md),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Your food profile',
                                style: context.text.ingredient,
                              ),
                              const SizedBox(height: HearthSpacing.xxs),
                              Text(
                                'Allergies, dislikes, how you like to eat. '
                                'Private to you.',
                                style: context.text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: colors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.xl),
            Text('Cook together', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'Share this code with the other person. They enter it below and '
              'your libraries become one — including everything either of you '
              'has already added.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: HearthSpacing.md),
            if (account?.shareCode != null)
              _ShareCode(code: account!.shareCode!),
            const SizedBox(height: HearthSpacing.xl),
            Text('Join a household', style: context.text.sectionHeader),
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
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              _Message(text: _error!, isError: true),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              _Message(text: _notice!, isError: false),
            ],
            const SizedBox(height: HearthSpacing.md),
            SizedBox(
              height: HearthTouch.minTarget,
              child: FilledButton(
                onPressed: _busy ? null : _join,
                child: Text(_busy ? 'Just a moment…' : 'Join'),
              ),
            ),
            const SizedBox(height: HearthSpacing.xl),
            const _SyncPanel(),
            const SizedBox(height: HearthSpacing.xl),
            const _YourData(),
            const SizedBox(height: HearthSpacing.xxl),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The code, big enough to read aloud across a kitchen.
class _ShareCode extends StatelessWidget {
  const _ShareCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      label: 'Your household code is ${code.split('').join(' ')}',
      excludeSemantics: true,
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
              Expanded(
                child: Text(
                  code,
                  style: context.text.recipeTitle.copyWith(
                    // The alphabet already omits I, L, O, 0 and 1; the wide
                    // letter spacing is for reading it out loud.
                    letterSpacing: 4,
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

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Syncing', style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              status.hasProblem
                  ? Icons.error_outline
                  : status.isSyncing
                  ? Icons.sync
                  : Icons.cloud_done_outlined,
              size: 18,
              color: status.hasProblem ? colors.error : colors.textSecondary,
            ),
            const SizedBox(width: HearthSpacing.sm),
            Expanded(
              child: Text(
                _describe(status, queued),
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.sm),
        TextButton.icon(
          onPressed: status.isSyncing
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('Sync now'),
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

/// Taking everything with you (spec §7.4).
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
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Your data', style: context.text.sectionHeader),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          'Everything Hearth holds — your recipes, foods, plans and every '
          'meal you have logged — as one file you keep. Recipe photos are '
          'not included.',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (_error case final String error) ...<Widget>[
          const SizedBox(height: HearthSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, size: 18, color: colors.error),
              const SizedBox(width: HearthSpacing.sm),
              Expanded(
                child: Text(
                  error,
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: HearthSpacing.md),
        SizedBox(
          height: HearthTouch.minTarget,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(_busy ? 'Gathering it up…' : 'Export my data'),
          ),
        ),
      ],
    );
  }
}
