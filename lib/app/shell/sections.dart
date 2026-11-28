import 'package:flutter/material.dart';

import '../../features/plan/log_slot_sheet.dart';
import '../widgets/hearth_marks.dart';
import 'destinations.dart';
import 'unbuilt_screen.dart';

/// The one thing a room offers without being entered (spec §6.2).
///
/// The home screen draws it on the section it leads with, so that logging a
/// meal is one tap from the front door rather than three — and §5.6's whole
/// argument is that every extra tap is a tax paid three times a day.
///
/// Declared here rather than written into the home screen, which is the
/// difference between a registry and a special case. The home screen knows
/// that a section may have an action and how to draw one; it does not know
/// what logging is, or that Nutrition is the room that does it.
///
/// [onTap] is a plain function rather than a closure or a route, because
/// [appSections] is a const list and a tear-off of a top-level function is
/// the only callback that can go in one. A route would not do: the action
/// opens a sheet over wherever you are, and going somewhere first is the
/// tap this exists to save.
@immutable
class SectionAction {
  const SectionAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context) onTap;
}

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
///
/// Sealed into two, because "built" is the difference that everything else
/// turns on and a boolean could not carry it: only a [BuiltSection] has a
/// [BuiltSection.path], so asking an unbuilt room where it goes is a compile
/// error rather than a crash at the first tap.
@immutable
sealed class AppSection {
  const AppSection({
    required this.id,
    required this.label,
    required this.blurb,
    required this.icon,
    this.sketch,
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

  /// A drawing of the room, where one has been made (spec §6.1).
  ///
  /// Null for a room nobody has drawn yet, and the home screen falls back to
  /// [icon] — which is why this is a separate field rather than a replacement
  /// for one. A glyph and a line drawing are not the same thing and the
  /// rooms are not going to get their drawings on the same day.
  final String? sketch;

  /// The section's own tabs, in navigation order. Empty for a section that has
  /// not been built.
  List<AppDestination> get destinations;

  /// Whether there is anything behind the name yet.
  ///
  /// Derived rather than a flag of its own, deliberately: a boolean that says
  /// "available" can disagree with a section that has no screens, and the one
  /// that would be believed is the boolean. This cannot lie.
  bool get isBuilt => destinations.isNotEmpty;

  /// Whether anything is behind the tabs yet.
  ///
  /// [isBuilt] answers a narrower question than it reads as: since spec §11
  /// every room has tabs, so every room is "built" and the word no longer
  /// separates Nutrition from three empty rooms. The launcher and the launch
  /// preference both need that separation — four identical cards, three of
  /// them opening on "Not built yet.", is the wall of promises the home
  /// screen's footer exists to avoid.
  ///
  /// Asked of the screens rather than declared, for the same reason [isBuilt]
  /// is derived: a flag saying "furnished" can disagree with a room whose
  /// every tab draws the placeholder, and the flag is the one that would be
  /// believed. Building one costs a const constructor and `any` stops at the
  /// first real screen.
  bool get isFurnished =>
      destinations.any((AppDestination d) => d.builder() is! UnbuiltScreen);

  /// Spoken as one thought: what the room is, then what is in it (spec §6.3).
  String get semanticLabel => '$label. $blurb';

  /// What the home screen prints on the way into the room it leads with,
  /// and what that control answers to.
  ///
  /// One string for both, deliberately. Speech input matches on a control's
  /// accessible name, and WCAG 2.5.3 asks that the name contain the words
  /// printed on it — so a button reading "Open Nutrition" that answered to
  /// [semanticLabel] could not be pressed by saying what it says.
  String get openLabel => 'Open $label';
}

/// A room you can walk into: it has screens, so it has a way in.
///
/// The registry is the only place either subclass is written, and a section
/// with no destinations is written as a [PlannedSection] — which is what the
/// section registry test holds it to. A const constructor cannot assert that
/// for itself, because a const context may not ask a list how long it is.
final class BuiltSection extends AppSection {
  const BuiltSection({
    required super.id,
    required super.label,
    required super.blurb,
    required super.icon,
    super.sketch,
    required this.destinations,
    this.primaryAction,
  });

  @override
  final List<AppDestination> destinations;

  /// What this room offers from the front door, if anything.
  ///
  /// Null for a room with nothing worth doing from outside it, which is
  /// most of them: an action on every card is a row of buttons, and a row
  /// of buttons has no primary.
  final SectionAction? primaryAction;

  /// Where entering the section lands. Its first tab — Hearth opens on the
  /// recipe library today and this keeps it that way.
  ///
  /// Lives here rather than on [AppSection] so that it cannot be asked of a
  /// room with nothing in it. The constructor's assertion is what makes the
  /// answer exist.
  String get path => destinations.first.path;
}

/// A room the app intends to have. Named, described, and nowhere to go yet.
final class PlannedSection extends AppSection {
  const PlannedSection({
    required super.id,
    required super.label,
    required super.blurb,
    required super.icon,
    super.sketch,
  });

  @override
  List<AppDestination> get destinations => const <AppDestination>[];
}

/// Everything Hearth is, or intends to be.
///
/// Order is the order the home screen lists them in: what is built first, then
/// what is coming. Adding a section here is the whole of adding a section.
///
const List<AppSection> appSections = <AppSection>[
  BuiltSection(
    id: 'nutrition',
    label: 'Nutrition',
    blurb: 'Recipes, meal plans, shopping lists, and nutrition logs.',
    icon: Icons.soup_kitchen_outlined,
    sketch: kPotMark,
    destinations: foodDestinations,
    // The one Hearth is judged on: replacing MacrosFirst for daily logging.
    // From here it is one tap to the meal chooser and a second to the food,
    // without entering the room at all.
    primaryAction: SectionAction(
      label: 'Log food',
      icon: Icons.add,
      onTap: logFoodToday,
    ),
  ),
  // Walkable before they are furnished (spec §11): each has its tabs, and
  // each tab says what will live behind it. `isBuilt` is derived from having
  // destinations, so these now report as built — which is true of the rooms
  // and not of what is in them. The screens are the ones that say so.
  BuiltSection(
    id: 'fitness',
    label: 'Fitness',
    blurb: 'Workouts, sessions, and training records.',
    icon: Icons.fitness_center_outlined,
    destinations: fitnessDestinations,
  ),
  BuiltSection(
    id: 'health',
    label: 'Health',
    blurb: 'Measurements, appointments, and records.',
    icon: Icons.monitor_heart_outlined,
    destinations: healthDestinations,
  ),
  BuiltSection(
    id: 'home',
    label: 'House',
    blurb: 'Thermostat and household controls.',
    icon: Icons.thermostat_outlined,
    sketch: kCottageMark,
    destinations: houseDestinations,
  ),
];

/// The sections you can actually go into.
///
/// Typed as the built ones, not filtered down to them: everything that hands
/// out a way into a room reads this list, and what it gets back is already
/// known to have somewhere to go.
List<BuiltSection> get builtSections =>
    appSections.whereType<BuiltSection>().toList(growable: false);

/// The sections that are named but empty.
List<PlannedSection> get unbuiltSections =>
    appSections.whereType<PlannedSection>().toList(growable: false);

/// Which section a route belongs to, or null for a route outside them all —
/// the home screen and settings, which belong to the app rather than to a room.
BuiltSection? sectionForPath(String path) {
  for (final BuiltSection section in builtSections) {
    if (section.destinations.any((AppDestination d) => d.path == path)) {
      return section;
    }
  }
  return null;
}

/// The section a stored id names, or null if nothing does.
BuiltSection? sectionById(String id) {
  for (final BuiltSection section in builtSections) {
    if (section.id == id) return section;
  }
  return null;
}
