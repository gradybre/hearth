import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/bootstrap.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme/hearth_theme.dart';
import 'data/auth/auth_gateway.dart';
import 'features/account/sign_in_screen.dart';

Future<void> main() async {
  final bool connected = await bootstrap();
  runApp(
    ProviderScope(
      overrides: [supabaseReadyProvider.overrideWithValue(connected)],
      child: const HearthApp(),
    ),
  );
}

class HearthApp extends ConsumerStatefulWidget {
  const HearthApp({super.key});

  @override
  ConsumerState<HearthApp> createState() => _HearthAppState();
}

class _HearthAppState extends ConsumerState<HearthApp> {
  /// Built once and kept. Rebuilding the router on a sign-in would throw away
  /// every pushed route; on a sign-out it would leave the old ones
  /// addressable.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // An unconfigured build goes straight in. Hearth is offline-first and
    // usable alone (spec §5.1), so "no backend" means "no sync yet", not a
    // locked door.
    if (!ref.watch(supabaseReadyProvider)) return _routed();

    return ref
        .watch(accountProvider)
        .when(
          loading: () => _plain(const _Waiting()),
          // A failure here is a session that could not be resolved, so the
          // way forward is to sign in again rather than to sit on a spinner.
          error: (Object error, StackTrace stack) =>
              _plain(const SignInScreen()),
          data: (HearthAccount? account) =>
              account == null ? _plain(const SignInScreen()) : _routed(),
        );
  }

  Widget _routed() => MaterialApp.router(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    theme: HearthTheme.light(),
    darkTheme: HearthTheme.dark(),
    // Light ships first, but dark is defined from day one and follows the OS
    // rather than waiting on an in-app setting (spec §6.1).
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );

  /// The same theme, for the screens that sit outside the router.
  Widget _plain(Widget home) => MaterialApp(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    theme: HearthTheme.light(),
    darkTheme: HearthTheme.dark(),
    themeMode: ThemeMode.system,
    home: home,
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
