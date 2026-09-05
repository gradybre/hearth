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
    required this.blurb,
    required this.icon,
  });

  /// The home screen: every room, and nothing opened for you.
  static const LaunchTarget home = LaunchTarget._(
    stored: 'home',
    path: '/',
    label: 'The home screen',
    blurb: 'Every section, and you choose where to go.',
    icon: Icons.cottage_outlined,
  );

  /// Straight into a section, skipping the home screen.
  ///
  /// Takes a [BuiltSection], so a room that is only named cannot be handed to
  /// it — the registry has no way to produce one and the type would refuse it.
  factory LaunchTarget.section(BuiltSection section) => LaunchTarget._(
    stored: 'section:${section.id}',
    path: section.path,
    label: section.label,
    blurb: section.blurb,
    icon: section.icon,
  );

  /// Everywhere the app can be told to open, in the order they are offered.
  static List<LaunchTarget> get options => <LaunchTarget>[
    home,
    for (final BuiltSection section in builtSections)
      LaunchTarget.section(section),
  ];

  /// What goes in the preference row. Prefixed rather than bare, so a section
  /// called `home` could never be mistaken for the home screen.
  final String stored;

  /// The route the app starts at.
  final String path;

  final String label;
  final String blurb;

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
