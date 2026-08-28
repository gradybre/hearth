import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/auth/auth_gateway.dart';

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
