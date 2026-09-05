import 'package:flutter/material.dart';

import 'destinations.dart';

/// A room in the house (spec §6.2).
///
/// Hearth is one app with several pillars, and a pillar is a *section*: a name,
/// an icon, a sentence saying what it is for, and its own set of tabs. Nutrition
/// is the one that is built; fitness, health and the thermostat are named here
/// so the shape of the app is honest about where it is going.
///
/// The point of the type is that adding a pillar is data, not navigation
/// surgery: give it destinations and screens and it appears on the home screen,
/// gets its own tabs, and becomes something the app can be told to open on.
/// Nothing in the router, the shell or the settings screen needs touching.
@immutable
class AppSection {
  const AppSection({
    required this.id,
    required this.label,
    required this.blurb,
    required this.icon,
    this.destinations = const <AppDestination>[],
  });

  /// Stable across renames — it is what the launch preference stores, so
  /// changing one silently sends a device back to the home screen.
  final String id;

  final String label;

  /// One sentence saying what the section is for. Shown on the home card and
  /// again beside the launch preference, so it has to read as an answer to
  /// "what is in here" both times.
  final String blurb;

  final IconData icon;

  /// The section's own tabs, in navigation order. Empty for a section that has
  /// not been built.
  final List<AppDestination> destinations;

  /// Whether there is anything behind the name yet.
  ///
  /// Derived rather than a flag of its own, deliberately: a boolean that says
  /// "available" can disagree with a section that has no screens, and the one
  /// that would be believed is the boolean. This cannot lie.
  bool get isBuilt => destinations.isNotEmpty;

  /// Where entering the section lands. Its first tab — Hearth opens on the
  /// recipe library today and this keeps it that way.
  ///
  /// Only meaningful when [isBuilt]; nothing offers a way into a section that
  /// has nowhere to go.
  String get path => destinations.first.path;

  /// Spoken as one thought: what the room is, then what is in it (spec §6.3).
  String get semanticLabel => '$label. $blurb';
}

/// Everything Hearth is, or intends to be.
///
/// Order is the order the home screen lists them in: what is built first, then
/// what is coming. Adding a section here is the whole of adding a section.
const List<AppSection> appSections = <AppSection>[
  AppSection(
    id: 'nutrition',
    label: 'Nutrition',
    blurb: 'Recipes, the week\'s plan, the shopping list, and what you ate.',
    icon: Icons.soup_kitchen_outlined,
    destinations: foodDestinations,
  ),
  // Named but not built (spec §11). They carry a full description rather than
  // a bare label so that building one is a matter of handing it destinations —
  // the card it will need is already written.
  AppSection(
    id: 'fitness',
    label: 'Fitness',
    blurb: 'Training, sessions, and what the week actually looked like.',
    icon: Icons.fitness_center_outlined,
  ),
  AppSection(
    id: 'health',
    label: 'Health',
    blurb: 'The numbers worth watching, and appointments worth remembering.',
    icon: Icons.monitor_heart_outlined,
  ),
  AppSection(
    id: 'home',
    label: 'The house',
    blurb: 'The thermostat, and whatever else the house needs asking.',
    icon: Icons.thermostat_outlined,
  ),
];

/// The sections you can actually go into.
List<AppSection> get builtSections =>
    appSections.where((AppSection s) => s.isBuilt).toList(growable: false);

/// The sections that are named but empty.
List<AppSection> get unbuiltSections =>
    appSections.where((AppSection s) => !s.isBuilt).toList(growable: false);

/// Which section a route belongs to, or null for a route outside them all —
/// the home screen and settings, which belong to the app rather than to a room.
AppSection? sectionForPath(String path) {
  for (final AppSection section in builtSections) {
    if (section.destinations.any((AppDestination d) => d.path == path)) {
      return section;
    }
  }
  return null;
}

/// The section a stored id names, or null if nothing does.
AppSection? sectionById(String id) {
  for (final AppSection section in builtSections) {
    if (section.id == id) return section;
  }
  return null;
}
