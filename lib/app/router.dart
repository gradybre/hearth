import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/placeholder_screen.dart';
import '../features/recipes/type_specimen_screen.dart';
import 'shell/app_shell.dart';
import 'shell/destinations.dart';

/// The app's route table.
///
/// A single stateful shell wraps the pillar's sections so switching tabs keeps
/// each section's scroll position and navigation stack — important when you're
/// mid-way through a recipe and glance at the plan.
GoRouter buildRouter() => GoRouter(
  initialLocation: foodDestinations.first.path,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder:
          (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell shell,
          ) => AppShell(
            currentIndex: shell.currentIndex,
            onDestinationSelected: (int index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            ),
            child: shell,
          ),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/recipes',
              builder: (BuildContext context, GoRouterState state) =>
                  const TypeSpecimenScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/plan',
              builder: (BuildContext context, GoRouterState state) =>
                  const PlaceholderScreen(
                    title: 'Plan',
                    description:
                        'The week grid, macro targets, and one-tap logging '
                        'live here.',
                    phase: 'Phase 1 · Step 7',
                  ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/shopping',
              builder: (BuildContext context, GoRouterState state) =>
                  const PlaceholderScreen(
                    title: 'Shopping',
                    description:
                        'A list built from the week\'s plan, grouped by store '
                        'and editable before any export.',
                    phase: 'Phase 4',
                  ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/foods',
              builder: (BuildContext context, GoRouterState state) =>
                  const PlaceholderScreen(
                    title: 'Foods',
                    description:
                        'Your household food library. Manual entry first; '
                        'barcode scanning arrives in Phase 2.',
                    phase: 'Phase 1 · Step 6',
                  ),
            ),
          ],
        ),
      ],
    ),
  ],
);
