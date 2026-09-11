import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/adapters/label_reader.dart';
import '../data/adapters/shared_content.dart';
import '../features/account/food_profile_screen.dart';
import '../features/account/settings_screen.dart';
import '../features/foods/barcode_scan_screen.dart';
import '../features/foods/food_draft.dart';
import '../features/foods/food_editor_screen.dart';
import '../features/foods/menu_import_screen.dart';
import '../features/foods/seasonings_screen.dart';
import '../features/home/home_screen.dart';
import '../features/plan/logging_intent.dart';
import '../features/recipes/default_sweep_screen.dart';
import '../features/recipes/eat_out_screen.dart';
import '../features/recipes/recipe_chat_screen.dart';
import '../features/recipes/recipe_detail_screen.dart';
import '../features/recipes/recipe_draft.dart';
import '../features/recipes/recipe_editor_args.dart';
import '../features/recipes/recipe_editor_screen.dart';
import '../features/recipes/recipe_import_controller.dart';
import '../features/recipes/recipe_import_screen.dart';
import '../features/recipes/repair_screen.dart';
import 'providers.dart';
import 'shell/app_shell.dart';
import 'shell/destinations.dart';
import 'shell/sections.dart';

/// The app's route table.
///
/// **Deliberately not `StatefulShellRoute`.** Every go_router shell variant
/// puts each branch behind a nested [Navigator], and a nested navigator emits
/// a `scopesRoute` semantics node that drops every sibling node from the
/// accessibility tree — which silently hid the whole navigation chrome from
/// screen readers. Accessibility is a non-negotiable (spec §6.3), so the shell
/// holds a plain [IndexedStack] instead.
///
/// Section state still survives tab switches: every section resolves to the
/// same page key, so Flutter reuses one [AppShell] element and the
/// [IndexedStack] keeps all four sections alive.
///
/// Detail screens push onto the root navigator as full-screen routes rather
/// than into a per-section stack — which also keeps the shell out of the way
/// while reading a recipe with messy hands.
///
/// **The home screen sits above the shell as a sibling, not as a parent.** A
/// section is a route swap, not a nested navigator, for the same accessibility
/// reason as above and for a second one: every path the app already uses —
/// `/recipes`, `/plan`, `/recipe/:id`, `/food/:id` — keeps resolving exactly as
/// it did, so a `context.push` from anywhere, and any link that was ever
/// handed out, still lands where it always did. Nesting the sections under
/// `/nutrition/...` would have renamed all of them for no gain the user can
/// see.
///
/// [initialLocation] is where the app opens, which the user chooses in Settings
/// (spec §6.2). It is passed in rather than read here because the answer is on
/// the device and has to be in hand before the router exists — a route decided
/// a frame late is a visible flash of the wrong screen.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  // A path that matches nothing goes home, the same as an unknown section
  // does below. The `/:section` redirect only ever saw single-segment paths,
  // so anything deeper — a stale link, a share carrying a URL Hearth used to
  // understand — landed on go_router's own error page, which is a red screen
  // with nothing on it to tap. Home says where you are and lets you carry on.
  onException: (BuildContext context, GoRouterState state, GoRouter router) =>
      router.go('/'),
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const HomeScreen(),
    ),
    // Everything from here down is listed before `/:section`, and that order
    // is what makes it work: go_router matches in declaration order, so a
    // concrete path wins over the wildcard that would otherwise swallow it.
    // `/household` and `/profile` are single-segment and would match
    // `/:section` exactly — moving either below it would route them into the
    // shell instead, so nothing here is safe to reorder.
    //
    // Settings is an index and six pages behind it (review §7.8). The
    // subpages are two segments, so they cannot collide with `/:section`;
    // `/settings` itself is one and has to stay above it like the rest.
    GoRoute(
      path: '/settings',
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
      routes: <RouteBase>[
        GoRoute(
          path: 'account',
          builder: (BuildContext context, GoRouterState state) =>
              const AccountSettingsScreen(),
        ),
        GoRoute(
          path: 'household',
          builder: (BuildContext context, GoRouterState state) =>
              const HouseholdSettingsScreen(),
        ),
        GoRoute(
          path: 'appearance',
          builder: (BuildContext context, GoRouterState state) =>
              const AppearanceSettingsScreen(),
        ),
        GoRoute(
          path: 'start',
          builder: (BuildContext context, GoRouterState state) =>
              const StartSettingsScreen(),
        ),
        GoRoute(
          path: 'sync',
          builder: (BuildContext context, GoRouterState state) =>
              const SyncSettingsScreen(),
        ),
        GoRoute(
          path: 'data',
          builder: (BuildContext context, GoRouterState state) =>
              const DataSettingsScreen(),
        ),
      ],
    ),
    // The old path, kept working rather than migrated (review §7.8). The
    // screen grew from the household page into the settings page and the
    // route never followed; a link somebody saved is not worth breaking to
    // tidy that up.
    GoRoute(
      path: '/household',
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) =>
          const FoodProfileScreen(),
    ),
    GoRoute(
      path: '/recipe/write',
      builder: (BuildContext context, GoRouterState state) =>
          const RecipeChatScreen(),
    ),
    GoRoute(
      path: '/recipe/repair',
      builder: (BuildContext context, GoRouterState state) =>
          const RepairScreen(),
    ),
    GoRoute(
      path: '/recipe/defaults',
      builder: (BuildContext context, GoRouterState state) =>
          const DefaultSweepScreen(),
    ),
    GoRoute(
      path: '/recipe/import',
      builder: (BuildContext context, GoRouterState state) =>
          // `extra` carries what another app shared, when the screen was
          // opened by a share rather than by tapping Import.
          RecipeImportScreen(
            shared: state.extra is SharedContent
                ? state.extra! as SharedContent
                : null,
          ),
    ),
    GoRoute(
      path: '/food/menu-import',
      builder: (BuildContext context, GoRouterState state) =>
          const MenuImportScreen(),
    ),
    GoRoute(
      path: '/recipe/eat-out',
      builder: (BuildContext context, GoRouterState state) => EatOutScreen(
        // Carried from the log sheet, which knows the day and the slot. The
        // library's own entry point sends nothing, and an ordinary Save is
        // the right ending there (U04).
        intent: state.extra is LoggingIntent
            ? state.extra! as LoggingIntent
            : null,
      ),
    ),
    GoRoute(
      path: '/recipe/new',
      builder: (BuildContext context, GoRouterState state) {
        // One shape that carries all three, and the two bare ones that
        // predate it. The restaurant builder needs to hand over a draft *and*
        // the meal it belongs to, which sniffing a single runtime type
        // cannot express.
        final Object? extra = state.extra;
        final RecipeEditorArgs args = extra is RecipeEditorArgs
            ? extra
            : RecipeEditorArgs(
                // An import pushes here with the recipe already read — the
                // review step before anything is written (CLAUDE.md rule 4).
                imported: extra is RecipeImportResult ? extra : null,
                // A duplicate pushes here with the copy already made, so it
                // is reviewed and renamed before anything is written.
                draft: extra is RecipeDraft ? extra : null,
              );

        return RecipeEditorScreen(
          imported: args.imported,
          draft: args.draft,
          intent: args.intent,
        );
      },
    ),
    GoRoute(
      path: '/recipe/:id',
      builder: (BuildContext context, GoRouterState state) =>
          RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      routes: <RouteBase>[
        GoRoute(
          path: 'edit',
          builder: (BuildContext context, GoRouterState state) =>
              RecipeEditorScreen(recipeId: state.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(
      path: '/food/seasonings',
      builder: (BuildContext context, GoRouterState state) =>
          const SeasoningsScreen(),
    ),
    GoRoute(
      path: '/food/scan',
      builder: (BuildContext context, GoRouterState state) => BarcodeScanScreen(
        // Opened from a recipe ingredient rather than the food library: the
        // scan ends by handing back the food it settled on (spec §5.5).
        pickFood: state.uri.queryParameters['pick'] == '1',
      ),
    ),
    GoRoute(
      path: '/food/new',
      builder: (BuildContext context, GoRouterState state) => FoodEditorScreen(
        // A barcode scan pushes here with the food already filled in — the
        // review step before anything is written (CLAUDE.md rule 4).
        initialDraft: state.extra is FoodDraft
            ? state.extra! as FoodDraft
            : null,
      ),
    ),
    GoRoute(
      path: '/food/:id',
      builder: (BuildContext context, GoRouterState state) => FoodEditorScreen(
        foodId: state.pathParameters['id'],
        // A label read on the way here, merged in on top of the food's own
        // values rather than instead of them — the flagged-ingredient path,
        // where the food has grams and the recipe wants cups.
        initialLabel: state.extra is LabelReading
            ? state.extra! as LabelReading
            : null,
      ),
    ),
    GoRoute(
      path: '/:section',
      redirect: (BuildContext context, GoRouterState state) {
        // Unknown single-segment paths go home now rather than to the recipe
        // library: home is the top of the app, and landing there says where
        // you are instead of quietly putting you somewhere.
        final String? tab = state.pathParameters['section'];
        return sectionForPath('/$tab') == null ? '/' : null;
      },
      // One stable page key for every section: this is what keeps the shell
      // element — and therefore each section's scroll position — alive across
      // tab switches without a nested navigator. The selected index is read
      // from the router inside the shell rather than baked into the page.
      pageBuilder: (BuildContext context, GoRouterState state) =>
          const NoTransitionPage<void>(
            key: ValueKey<String>('app-shell'),
            child: _ShellHost(),
          ),
    ),
  ],
);

/// Reads the current section and tab from the router so the shell can rebuild
/// without the page identity changing.
///
/// Knows nothing about Recipes or Plan by name: it asks which section owns the
/// current path and builds whatever that section says its tabs are. Adding
/// Fitness is a matter of adding it to the registry (spec §6.2).
class _ShellHost extends ConsumerWidget {
  const _ShellHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String location = GoRouterState.of(context).uri.path;
    // Never null in practice — the route above redirects anything unmatched
    // home — but a section that has been taken out should land somewhere real
    // rather than throw.
    final BuiltSection section =
        sectionForPath(location) ?? builtSections.first;
    final List<AppDestination> tabs = section.destinations;
    final int index = tabs.indexWhere((AppDestination d) => d.path == location);

    // Remembered as you move, so leaving the section and coming back lands
    // where you were rather than on its first tab (U08). This is the one
    // place that knows both the section and the destination inside it.
    //
    // After the frame, not during it: writing to a provider while building
    // is the thing Riverpod refuses, and a tab change is a consequence of
    // this build rather than an input to it.
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Still here, before touching `ref`. A frame callback runs after the
        // frame that scheduled it, and a redirect or a fast second tap can
        // unmount this shell in between — at which point reading a provider
        // through a dead element throws, and the app dies on its way
        // somewhere perfectly ordinary.
        if (!context.mounted) return;
        ref
            .read(lastDestinationProvider.notifier)
            .remember(section: section.id, path: location);
      });
    }

    return AppShell(
      section: section,
      currentIndex: index < 0 ? 0 : index,
      onDestinationSelected: (int i) => context.go(tabs[i].path),
      onLeaveSection: () => context.go('/'),
      child: IndexedStack(
        index: index < 0 ? 0 : index,
        children: <Widget>[
          for (final AppDestination tab in tabs) tab.builder(),
        ],
      ),
    );
  }
}
