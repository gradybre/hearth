import 'package:flutter/material.dart';

/// A top-level destination in the app shell.
///
/// v1 shows only the Food pillar's four sections (spec §6.2), but the shell is
/// pillar-agnostic: adding Watchlist or Date Ideas later (spec §11) means
/// adding entries here, not restructuring navigation.
@immutable
class AppDestination {
  const AppDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.semanticLabel,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Spoken label. Says what the destination *is* and what activating it does,
  /// rather than repeating the visible word (spec §6.3).
  final String semanticLabel;
}

/// The Food pillar's sections, in navigation order (spec §6.2).
const List<AppDestination> foodDestinations = <AppDestination>[
  AppDestination(
    path: '/recipes',
    label: 'Recipes',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    semanticLabel: 'Recipes. Your household recipe library.',
  ),
  AppDestination(
    path: '/plan',
    label: 'Plan',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
    semanticLabel: 'Plan. This week\'s meals and your daily logging.',
  ),
  AppDestination(
    path: '/shopping',
    label: 'Shopping',
    icon: Icons.shopping_basket_outlined,
    selectedIcon: Icons.shopping_basket,
    semanticLabel: 'Shopping. The list built from this week\'s plan.',
  ),
  AppDestination(
    path: '/foods',
    label: 'Foods',
    icon: Icons.egg_outlined,
    selectedIcon: Icons.egg,
    semanticLabel: 'Foods. Your personal and household food library.',
  ),
];
