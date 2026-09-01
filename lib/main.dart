import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/bootstrap.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme/hearth_theme.dart';
import 'data/adapters/shared_content.dart';
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
    // Something shared from another app. Listened for here rather than in a
    // screen because a share extension runs while Hearth is closed: by the
    // time anything is on screen the payload is already waiting, and the app
    // has to go and meet it.
    ref.listen<AsyncValue<SharedContent>>(sharedContentProvider, (
      AsyncValue<SharedContent>? _,
      AsyncValue<SharedContent> next,
    ) {
      if (next.value case final SharedContent shared) _open(shared);
    });

    // An unconfigured build goes straight in. Hearth is offline-first and
    // usable alone (spec §5.1), so "no backend" means "no sync yet", not a
    // locked door.
    if (!ref.watch(supabaseReadyProvider)) return _routed();

    // Watched, not merely created: the controller registers its triggers in
    // build, so nothing would ever drain the queue if no one listened.
    ref.watch(syncControllerProvider);

    final AsyncValue<HearthAccount?> account = ref.watch(accountProvider);

    // Only ever spinner before the first answer. Once the account is known,
    // a re-emission must not swap the sign-in screen out for a spinner and
    // back: that destroys its State, taking the typed email and the error
    // message with it — so a failed sign-in would silently wipe the form
    // instead of saying what went wrong.
    if (account.isLoading && !account.hasValue) return _plain(const _Waiting());

    // An error here is a session that could not be resolved, so the way
    // forward is to sign in again rather than to sit on a spinner.
    return account.value == null ? _plain(const SignInScreen()) : _routed();
  }

  /// Takes a share to the import screen, which reviews before it saves.
  ///
  /// Nothing arrives in the library on the strength of a share alone
  /// (CLAUDE.md rule 4) — this is a faster way to the same review screen, not
  /// a way around it. Dropped on the floor while signed out, because there is
  /// no household to import into yet and the payload would be waiting again
  /// on the next launch anyway.
  void _open(SharedContent shared) {
    final bool signedIn =
        !ref.read(supabaseReadyProvider) ||
        ref.read(accountProvider).value != null;
    if (!signedIn) return;
    _router.push('/recipe/import', extra: shared);
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
