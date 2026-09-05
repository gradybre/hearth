import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/bootstrap.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/shell/launch_target.dart';
import 'app/theme/hearth_theme.dart';
import 'app/theme/theme_choice.dart';
import 'data/adapters/shared_content.dart';
import 'data/auth/auth_gateway.dart';
import 'features/account/sign_in_screen.dart';

Future<void> main() async {
  final Boot boot = await bootstrap();
  runApp(
    ProviderScope(
      overrides: [
        supabaseReadyProvider.overrideWithValue(boot.connected),
        // The database bootstrap already opened to read the theme out of, so
        // the app goes on using that one rather than opening a second.
        databaseProvider.overrideWithValue(boot.database),
        // And the answer it found, so the first frame is painted in the theme
        // that was asked for instead of the device's (spec §6.1).
        launchThemeChoiceProvider.overrideWithValue(boot.theme),
        // Same again for where the app opens (spec §6.2). The router is built
        // with a starting route, so this one has to be in hand even earlier —
        // a value that arrived late would show the home screen and then
        // replace it, which is a flash nobody could mistake for anything else.
        bootLaunchTargetProvider.overrideWithValue(boot.launchTarget),
      ],
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
  ///
  /// The starting route is read once, here, rather than watched: changing where
  /// Hearth opens is a statement about the *next* launch, and moving the user
  /// off the screen they are looking at because they touched a settings row
  /// would be a surprise, not a preference.
  late final GoRouter _router = buildRouter(
    initialLocation:
        (ref.read(bootLaunchTargetProvider) ?? LaunchTarget.home).path,
  );

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

    // The user's own light/dark choice (spec §6.1). Already in hand: bootstrap
    // read it off the device before the first frame, so there is nothing to
    // wait for and nothing to flash. Still loading can only mean a build that
    // did not come through main(), where following the device is the only
    // honest thing to show.
    final ThemeMode themeMode =
        (ref.watch(themeChoiceProvider).value ?? ThemeChoice.system).mode;

    // An unconfigured build goes straight in. Hearth is offline-first and
    // usable alone (spec §5.1), so "no backend" means "no sync yet", not a
    // locked door.
    if (!ref.watch(supabaseReadyProvider)) return _routed(themeMode);

    // Watched, not merely created: the controller registers its triggers in
    // build, so nothing would ever drain the queue if no one listened.
    ref.watch(syncControllerProvider);

    final AsyncValue<HearthAccount?> account = ref.watch(accountProvider);

    // Only ever spinner before the first answer. Once the account is known,
    // a re-emission must not swap the sign-in screen out for a spinner and
    // back: that destroys its State, taking the typed email and the error
    // message with it — so a failed sign-in would silently wipe the form
    // instead of saying what went wrong.
    if (account.isLoading && !account.hasValue) {
      return _plain(const _Waiting(), themeMode);
    }

    // An error here is a session that could not be resolved, so the way
    // forward is to sign in again rather than to sit on a spinner.
    return account.value == null
        ? _plain(const SignInScreen(), themeMode)
        : _routed(themeMode);
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

  Widget _routed(ThemeMode themeMode) => MaterialApp.router(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    theme: HearthTheme.light(),
    darkTheme: HearthTheme.dark(),
    // Light ships first, dark is defined from day one, and which one you get
    // is now the user's own choice — defaulting to the device (spec §6.1).
    themeMode: themeMode,
    routerConfig: _router,
  );

  /// The same theme, for the screens that sit outside the router.
  Widget _plain(Widget home, ThemeMode themeMode) => MaterialApp(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    theme: HearthTheme.light(),
    darkTheme: HearthTheme.dark(),
    themeMode: themeMode,
    home: home,
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
