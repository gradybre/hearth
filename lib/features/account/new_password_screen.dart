import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/centred_message.dart';
import '../../data/auth/auth_gateway.dart';

/// Setting a new password, on the session a recovery link opened (spec §8.3).
///
/// The only screen a recovery session may reach. That is the point of it: the
/// link signs the user in, so without this the app would open on their meal
/// plan with a session minted by an email — and the thing they came to do
/// would be three taps away in Settings, on a session they cannot use to get
/// back in tomorrow.
///
/// Hearth still never handles the password itself. Supabase mints the link and
/// stores the credential; this collects two strings and hands them over.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  bool _showErrors = false;
  String? _failure;
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The app's own two rules, and no more.
  ///
  /// Length and agreement are worth catching here because catching them saves
  /// a round trip. Everything else — how many kinds of character, whether it
  /// has been breached — is the project's policy to enforce and would only be
  /// a second, quietly disagreeing copy of it if it were written here too.
  String? get _passwordError {
    final String value = _password.text;
    if (value.isEmpty) return 'Choose a password';
    if (value.length < 8) return 'At least 8 characters';
    return null;
  }

  String? get _confirmError =>
      _confirm.text == _password.text ? null : 'These do not match';

  Future<void> _save() async {
    if (_passwordError != null || _confirmError != null) {
      setState(() => _showErrors = true);
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(authGatewayProvider).setPassword(_password.text);
      if (!mounted) return;
      // Shown before the flag drops. Clearing it first would swap this screen
      // for the meal plan the same frame, and "your password is set" would be
      // a message nobody ever saw.
      setState(() => _done = true);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } on Object {
      // An expired or already-used link, a lost connection. All of them end
      // the same way — ask for another link — and none of them should show a
      // developer's sentence to somebody locked out of their account.
      if (mounted) {
        setState(
          () => _failure =
              'That link could not be used. It may have expired or already '
              'been used. Ask for a new one from the sign-in screen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves without setting a password.
  ///
  /// Signs out on the way. A recovery session that is not going to be used for
  /// recovery is not a session anybody asked for, and leaving it standing
  /// would mean a link out of an email had quietly logged somebody in.
  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(authGatewayProvider).signOut();
    } on Object {
      // Already gone, or no connection. Either way the flag below is what
      // decides which screen is shown, and it is dropped regardless.
    }
    ref.read(passwordRecoveryProvider).end();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(child: _done ? _success(context) : _form(context)),
    );
  }

  Widget _success(BuildContext context) => CentredMessage(
    children: <Widget>[
      Icon(Icons.check_circle_outline, color: context.colors.accent),
      const SizedBox(height: HearthSpacing.sm),
      Text(
        'Password set',
        style: context.text.sectionHeader,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: HearthSpacing.sm),
      Text(
        'You are signed in on this device. Use the new password next time.',
        style: context.text.body.copyWith(color: context.colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: HearthSpacing.lg),
      SizedBox(
        height: HearthTouch.minTarget,
        child: FilledButton(
          onPressed: () => ref.read(passwordRecoveryProvider).end(),
          child: const Text('Continue'),
        ),
      ),
    ],
  );

  Widget _form(BuildContext context) {
    final HearthColors colors = context.colors;
    return CentredMessage(
      children: <Widget>[
        Text(
          'Set a new password',
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'This link signed you in so you can change it. Choose the password '
          'you will use from now on.',
          style: context.text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.lg),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.newPassword],
          onChanged: (String _) => setState(() {}),
          style: context.text.body,
          decoration: InputDecoration(
            labelText: 'New password',
            errorText: _showErrors ? _passwordError : null,
          ),
        ),
        const SizedBox(height: HearthSpacing.md),
        TextField(
          controller: _confirm,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.newPassword],
          onChanged: (String _) => setState(() {}),
          onSubmitted: (String _) => _busy ? null : _save(),
          style: context.text.body,
          decoration: InputDecoration(
            labelText: 'Repeat it',
            errorText: _showErrors ? _confirmError : null,
          ),
        ),
        if (_failure case final String message) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // An icon as well as the colour, never colour alone (§6.3).
              Icon(Icons.error_outline, size: 18, color: colors.error),
              const SizedBox(width: HearthSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  style: context.text.metadata.copyWith(color: colors.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: HearthSpacing.lg),
        SizedBox(
          height: HearthTouch.minTarget,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save password'),
          ),
        ),
        const SizedBox(height: HearthSpacing.sm),
        TextButton(
          onPressed: _busy ? null : _cancel,
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
