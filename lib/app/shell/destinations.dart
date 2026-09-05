import 'package:flutter/material.dart';

import '../../features/foods/food_library_screen.dart';
import '../../features/plan/plan_screen.dart';
import '../../features/recipes/recipe_library_screen.dart';
import '../../features/shopping/shopping_screen.dart';

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
