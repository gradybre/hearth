import 'package:flutter/material.dart';

import '../../features/foods/food_library_screen.dart';
import '../../features/plan/plan_screen.dart';
import '../../features/recipes/recipe_library_screen.dart';
import '../../features/shopping/shopping_screen.dart';
import 'unbuilt_screen.dart';

/// A tab within a section.
///
/// Carries its own screen, so a section is a self-contained description of
/// itself: the shell builds whatever the current section says its tabs are
/// rather than knowing the Food pillar's four by name (spec §6.2).
@immutable
class AppDestination {
  const AppDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.semanticLabel,
    required this.builder,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Spoken label. Says what the destination *is* and what activating it does,
  /// rather than repeating the visible word (spec §6.3).
  final String semanticLabel;

  /// The screen behind the tab. A builder rather than a widget because these
  /// are `const` declarations and a screen is not, and because the shell keeps
  /// every tab alive in an [IndexedStack] — the element persists, so building
  /// the configuration afresh costs nothing.
  final Widget Function() builder;
}

/// The Nutrition section's tabs, in navigation order (spec §6.2).
const List<AppDestination> foodDestinations = <AppDestination>[
  AppDestination(
    path: '/recipes',
    label: 'Recipes',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    semanticLabel: 'Recipes. Your household recipe library.',
    builder: RecipeLibraryScreen.new,
  ),
  AppDestination(
    path: '/plan',
    label: 'Plan',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
    semanticLabel: 'Plan. This week\'s meals and your daily logging.',
    builder: PlanScreen.new,
  ),
  AppDestination(
    path: '/shopping',
    label: 'Shopping',
    icon: Icons.shopping_basket_outlined,
    selectedIcon: Icons.shopping_basket,
    semanticLabel: 'Shopping. The list built from this week\'s plan.',
    builder: ShoppingScreen.new,
  ),
  AppDestination(
    path: '/foods',
    label: 'Foods',
    icon: Icons.egg_outlined,
    selectedIcon: Icons.egg,
    semanticLabel: 'Foods. Your personal and household food library.',
    builder: FoodLibraryScreen.new,
  ),
];

/// The Fitness section's tabs (spec §11).
///
/// Named and navigable before they are furnished. Each screen says what will
/// live behind it, because an empty list and an unwritten feature look the
/// same and only one of them is worth waiting for.
const List<AppDestination> fitnessDestinations = <AppDestination>[
  AppDestination(
    path: '/training',
    label: 'Today',
    icon: Icons.bolt_outlined,
    selectedIcon: Icons.bolt,
    semanticLabel: 'Today. The session in front of you.',
    builder: _fitnessToday,
  ),
  AppDestination(
    path: '/workouts',
    label: 'Workouts',
    icon: Icons.fitness_center_outlined,
    selectedIcon: Icons.fitness_center,
    semanticLabel: 'Workouts. The sessions you have written.',
    builder: _fitnessWorkouts,
  ),
  AppDestination(
    path: '/training-history',
    label: 'History',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    semanticLabel: 'History. What the weeks actually looked like.',
    builder: _fitnessHistory,
  ),
];

/// The Health section's tabs (spec §11).
const List<AppDestination> healthDestinations = <AppDestination>[
  AppDestination(
    path: '/numbers',
    label: 'Numbers',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
    semanticLabel: 'Numbers. Measurements worth watching over time.',
    builder: _healthNumbers,
  ),
  AppDestination(
    path: '/appointments',
    label: 'Appointments',
    icon: Icons.event_outlined,
    selectedIcon: Icons.event,
    semanticLabel: 'Appointments. What is booked and what is due.',
    builder: _healthAppointments,
  ),
];

/// The house's tabs (spec §11).
const List<AppDestination> houseDestinations = <AppDestination>[
  AppDestination(
    path: '/thermostat',
    label: 'Thermostat',
    icon: Icons.thermostat_outlined,
    selectedIcon: Icons.thermostat,
    semanticLabel: 'Thermostat. What the house is set to.',
    builder: _houseThermostat,
  ),
];

// Top-level functions rather than closures: an `AppDestination` is `const`,
// and a `const` list cannot hold a closure.
Widget _fitnessToday() => const UnbuiltScreen(
  title: 'Today',
  coming: 'The session in front of you, and a way to record it as you go.',
);

Widget _fitnessWorkouts() => const UnbuiltScreen(
  title: 'Workouts',
  coming: 'The sessions you have written, to repeat and adjust.',
);

Widget _fitnessHistory() => const UnbuiltScreen(
  title: 'History',
  coming: 'What the weeks actually looked like, once there are weeks.',
);

Widget _healthNumbers() => const UnbuiltScreen(
  title: 'Numbers',
  coming: 'Measurements worth watching, and what they have done over time.',
);

Widget _healthAppointments() => const UnbuiltScreen(
  title: 'Appointments',
  coming: 'What is booked, what is due, and what came of it.',
);

Widget _houseThermostat() => const UnbuiltScreen(
  title: 'Thermostat',
  coming: 'What the house is set to, and what it is actually doing.',
);
