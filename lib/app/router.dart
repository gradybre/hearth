import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/account/food_profile_screen.dart';
import '../features/account/household_screen.dart';
import '../features/foods/barcode_scan_screen.dart';
import '../features/foods/food_draft.dart';
import '../features/foods/food_editor_screen.dart';
import '../features/foods/food_library_screen.dart';
import '../features/placeholder_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/recipes/recipe_chat_screen.dart';
import '../features/recipes/recipe_detail_screen.dart';
import '../features/recipes/recipe_editor_screen.dart';
import '../features/recipes/recipe_import_controller.dart';
import '../features/recipes/recipe_import_screen.dart';
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
      path: '/household',
      builder: (BuildContext context, GoRouterState state) =>
          const HouseholdScreen(),
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
      path: '/recipe/import',
      builder: (BuildContext context, GoRouterState state) =>
          const RecipeImportScreen(),
    ),
    GoRoute(
      path: '/recipe/new',
      builder: (BuildContext context, GoRouterState state) =>
          RecipeEditorScreen(
            // An import pushes here with the recipe already read — the review
            // step before anything is written (CLAUDE.md rule 4).
            imported: state.extra is RecipeImportResult
                ? state.extra! as RecipeImportResult
                : null,
          ),
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
      builder: (BuildContext context, GoRouterState state) =>
          FoodEditorScreen(foodId: state.pathParameters['id']),
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
          PlanScreen(),
          PlaceholderScreen(
            title: 'Shopping',
            description:
                'A list built from the week\'s plan, grouped by store and '
                'editable before any export.',
            phase: 'Phase 4',
          ),
          FoodLibraryScreen(),
        ],
      ),
    );
  }
}
