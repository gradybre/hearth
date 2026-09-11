import 'package:flutter/material.dart';

import 'sections.dart';

/// Which screen Hearth opens on (spec §6.2).
///
/// Home is the default, because the home screen is what says the app has more
/// than one room in it. But someone who only ever opens Hearth to log lunch
/// should not have to tap past a menu to do it, so any built section can be
/// named as the landing instead.
///
/// Not an enum, unlike `ThemeChoice` whose shape this otherwise mirrors: the
/// answers are the sections, and the sections are data. Adding Fitness adds its
/// option here with no edit — which is the whole point of §6.2's section
/// registry.
///
/// Deliberately device-local. One person opening straight into Nutrition must
/// not decide where their partner's app opens, and the Mac on the desk is
/// allowed to disagree with the phone in your pocket.
@immutable
class LaunchTarget {
  const LaunchTarget._({
    required this.stored,
    required this.path,
    required this.label,
    required this.icon,
  });

  /// The home screen: every room, and nothing opened for you.
  static const LaunchTarget home = LaunchTarget._(
    stored: 'home',
    path: '/',
    label: 'The home screen',
    icon: Icons.cottage_outlined,
  );

  /// Straight to the day you are in.
  ///
  /// Not a section: a section opens on its first destination, which for
  /// Nutrition is the recipe library. Someone who opens Hearth to log lunch
  /// wants the day, and there was no way to ask for it.
  ///
  /// The path carries no date. `selectedDateProvider` resolves the local
  /// current day when it is built, so what "today" means is decided at launch
  /// rather than written into a preference — a stored `/plan/2026-09-07`
  /// would open on the seventh for ever.
  static const LaunchTarget today = LaunchTarget._(
    stored: 'today',
    path: '/plan',
    label: 'Today',
    icon: Icons.today_outlined,
  );

  /// Straight into a section, skipping the home screen.
  ///
  /// Takes a [BuiltSection], so a room that is only named cannot be handed to
  /// it — the registry has no way to produce one and the type would refuse it.
  factory LaunchTarget.section(BuiltSection section) => LaunchTarget._(
    stored: 'section:${section.id}',
    path: section.path,
    label: section.label,
    icon: section.icon,
  );

  /// Everywhere the app can be told to open, in the order they are offered.
  static List<LaunchTarget> get options => <LaunchTarget>[
    home,
    today,
    for (final BuiltSection section in builtSections)
      LaunchTarget.section(section),
  ];

  /// What goes in the preference row. Prefixed rather than bare, so a section
  /// called `home` could never be mistaken for the home screen.
  final String stored;

  /// The route the app starts at.
  final String path;

  /// What the row says, and all it says.
  ///
  /// Each of these carried a sentence of its own — "The day you are in, ready
  /// to log against" under the word *Today* — which is the word twice (review
  /// §6.2.4). `BuiltSection.blurb` still exists and is still drawn, on the
  /// home screen's cards, where it names a room somebody has not opened.
  final String label;

  /// Carried alongside the label so the chosen option is never distinguished
  /// by colour alone (spec §6.3).
  final IconData icon;

  /// Reads a stored value back.
  ///
  /// Anything unrecognised falls back to [home] — a value written by a newer
  /// build, or a section that has since been taken out. Opening on the home
  /// screen is always a defensible answer; failing to open is not.
  static LaunchTarget parse(String? stored) {
    if (stored == null || stored == home.stored) return home;
    if (stored == today.stored) return today;
    const String prefix = 'section:';
    if (!stored.startsWith(prefix)) return home;
    final BuiltSection? section = sectionById(stored.substring(prefix.length));
    return section == null ? home : LaunchTarget.section(section);
  }

  @override
  bool operator ==(Object other) =>
      other is LaunchTarget && other.stored == stored;

  @override
  int get hashCode => stored.hashCode;

  @override
  String toString() => 'LaunchTarget($stored)';
}
