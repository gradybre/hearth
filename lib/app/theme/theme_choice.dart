import 'package:flutter/material.dart';

/// Which theme the user asked for (spec §6.1).
///
/// Three states rather than a switch, because "follow the device" is a real
/// answer and not the same as "light": a phone on a sunset schedule should be
/// allowed to carry Hearth with it, and a person who wants cream at midnight
/// should be allowed to say so and be believed.
///
/// Deliberately device-local. Nothing here is a household decision — the phone
/// in your hand and the Mac on the desk are allowed to disagree.
enum ThemeChoice {
  system(
    label: 'Follow the device',
    blurb: 'Light by day, dark when your device says so.',
    icon: Icons.brightness_auto_outlined,
  ),
  light(
    label: 'Light',
    blurb: 'Paper cream, whatever the device is doing.',
    icon: Icons.light_mode_outlined,
  ),
  dark(
    label: 'Dark',
    blurb: 'Low light, whatever the device is doing.',
    icon: Icons.dark_mode_outlined,
  );

  const ThemeChoice({
    required this.label,
    required this.blurb,
    required this.icon,
  });

  final String label;
  final String blurb;

  /// Carried alongside the label so the chosen option is never distinguished
  /// by colour alone (spec §6.3).
  final IconData icon;

  ThemeMode get mode => switch (this) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };

  /// What goes in the preference row — the enum name, so a stored value stays
  /// legible to anyone reading the local database.
  String get stored => name;

  /// Reads a stored value back.
  ///
  /// Anything unrecognised falls back to [system]: a value written by a newer
  /// build, or a row edited by hand, must not be able to leave the app with no
  /// theme at all.
  static ThemeChoice parse(String? stored) => ThemeChoice.values.firstWhere(
    (ThemeChoice choice) => choice.stored == stored,
    orElse: () => ThemeChoice.system,
  );
}
