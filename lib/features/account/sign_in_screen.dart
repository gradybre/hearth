import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/auth/auth_gateway.dart';

/// Signing in or creating an account (spec §5.1, §8.3).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final AuthGateway auth = ref.read(authGatewayProvider);
      if (_creating) {
        final HearthAccount? account = await auth.signUp(
          email: _email.text,
          password: _password.text,
        );
        // Null means the project asked for confirmation first. The account
        // exists; saying "check your email" is the truth, and treating it as
        // a failure would send the user round again to make a second one.
        if (account == null && mounted) {
          setState(
            () => _notice =
                'Account created. Check your email to confirm the address, '
                'then sign in.',
          );
        }
      } else {
        await auth.signIn(email: _email.text, password: _password.text);
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

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HearthSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Hearth', style: context.text.recipeTitle),
                  const SizedBox(height: HearthSpacing.sm),
                  Text(
                    _creating
                        ? 'Make an account to cook and plan together.'
                        : 'Welcome back.',
                    style: context.text.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.xl),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    autocorrect: false,
                    style: context.text.body,
                    decoration: _decoration(context, 'Email'),
                  ),
                  const SizedBox(height: HearthSpacing.md),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: <String>[
                      _creating
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: (_) => _submit(),
                    style: context.text.body,
                    decoration: _decoration(context, 'Password'),
                  ),
                  if (_creating) ...<Widget>[
                    const SizedBox(height: HearthSpacing.sm),
                    Text(
                      'At least 12 characters, with upper and lower case and '
                      'a digit.',
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: HearthSpacing.md),
                    _Banner(message: _error!, isError: true),
                  ],
                  if (_notice != null) ...<Widget>[
                    const SizedBox(height: HearthSpacing.md),
                    _Banner(message: _notice!, isError: false),
                  ],
                  const SizedBox(height: HearthSpacing.lg),
                  SizedBox(
                    height: HearthTouch.minTarget,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Just a moment…'
                            : (_creating ? 'Create account' : 'Sign in'),
                      ),
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                            _notice = null;
                          }),
                    child: Text(
                      _creating
                          ? 'I already have an account'
                          : 'Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(BuildContext context, String label) {
    final HearthColors colors = context.colors;
    return InputDecoration(
      labelText: label,
      labelStyle: context.text.label.copyWith(color: colors.textSecondary),
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HearthRadius.md),
        borderSide: BorderSide(color: colors.outline),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          border: Border.all(
            color: isError ? colors.error : colors.outlineStrong,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // An icon as well as the border colour, so the difference
              // between a problem and a note is not colour alone (§6.3).
              Icon(
                isError ? Icons.error_outline : Icons.mark_email_read_outlined,
                size: 18,
                color: isError ? colors.error : colors.textSecondary,
              ),
              const SizedBox(width: HearthSpacing.sm),
              Expanded(child: Text(message, style: context.text.body)),
            ],
          ),
        ),
      ),
    );
  }
}
