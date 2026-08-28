import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/placeholder_screen.dart';
import '../features/recipes/recipe_detail_screen.dart';
import '../features/recipes/recipe_editor_screen.dart';
import '../features/recipes/recipe_library_screen.dart';
import 'shell/app_shell.dart';
import 'shell/destinations.dart';

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
GoRouter buildRouter() => GoRouter(
  initialLocation: foodDestinations.first.path,
  routes: <RouteBase>[
    // Listed before the section route: these have two or more segments, so
    // they can never be mistaken for a section.
    GoRoute(
      path: '/recipe/new',
      builder: (BuildContext context, GoRouterState state) =>
          const RecipeEditorScreen(),
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
      path: '/:section',
      redirect: (BuildContext context, GoRouterState state) {
        final String? section = state.pathParameters['section'];
        final bool known = foodDestinations.any(
          (AppDestination d) => d.path == '/$section',
        );
        return known ? null : foodDestinations.first.path;
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

int _indexForPath(String path) {
  final int index = foodDestinations.indexWhere(
    (AppDestination d) => d.path == path,
  );
  return index < 0 ? 0 : index;
}

/// Reads the current section from the router so the shell can rebuild without
/// the page identity changing.
class _ShellHost extends StatelessWidget {
  const _ShellHost();

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final int index = _indexForPath(location);

    return AppShell(
      currentIndex: index,
      onDestinationSelected: (int i) => context.go(foodDestinations[i].path),
      child: IndexedStack(
        index: index,
        children: const <Widget>[
          RecipeLibraryScreen(),
          PlaceholderScreen(
            title: 'Plan',
            description:
                'The week grid, macro targets, and one-tap logging live here.',
            phase: 'Phase 1 · Step 7',
          ),
          PlaceholderScreen(
            title: 'Shopping',
            description:
                'A list built from the week\'s plan, grouped by store and '
                'editable before any export.',
            phase: 'Phase 4',
          ),
          PlaceholderScreen(
            title: 'Foods',
            description:
                'Your household food library. Manual entry first; barcode '
                'scanning arrives in Phase 2.',
            phase: 'Phase 1 · Step 6',
          ),
        ],
      ),
    );
  }
}
