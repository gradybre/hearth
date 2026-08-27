import 'package:flutter/material.dart';

/// Hearth's colour tokens (spec §6.1).
///
/// Palette discipline is 60/30/10 with two to four colours total: one surface
/// family, one neutral text family, one accent. Everything here is a member of
/// one of those three families or a shade of them — resist adding a fifth hue.
///
/// **Over/under macro states deliberately have no red/green pair.** Colour
/// alone must never carry meaning (spec §6.3), and a traffic-light palette
/// would both break the discipline above and read as the calorie-cop app
/// Hearth is defined against. The state is carried by an icon and a label;
/// [overAccent] only reinforces it.
@immutable
class HearthColors extends ThemeExtension<HearthColors> {
  const HearthColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.outline,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.overAccent,
    required this.progressTrack,
    required this.error,
    required this.onError,
  });

  /// Light: warm paper cream, cocoa text, terracotta accent.
  factory HearthColors.light() => const HearthColors(
    background: Color(0xFFFBF7F0),
    surface: Color(0xFFFFFDF8),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF2EADD),
    outline: Color(0xFFDED2C0),
    outlineStrong: Color(0xFF96836A),
    textPrimary: Color(0xFF2A211A),
    textSecondary: Color(0xFF574538),
    textMuted: Color(0xFF6E5B4B),
    accent: Color(0xFFA8480F),
    accentPressed: Color(0xFF8A3A0B),
    onAccent: Color(0xFFFFFDF8),
    overAccent: Color(0xFF8A3A0B),
    progressTrack: Color(0xFFE8DCC9),
    error: Color(0xFF8A2A17),
    onError: Color(0xFFFFFDF8),
  );

  /// Dark: near-black ground, brightened cream text, lifted accent.
  ///
  /// Deliberately *not* a simple inversion of the light palette. A warm
  /// dark-brown ground with cream text turns muddy in poor kitchen light and
  /// struggles to clear WCAG AA, so the ground drops close to black and keeps
  /// only a trace of warmth. Legibility at arm's length wins over cosiness
  /// here (spec §6.1's kitchen-first rule beating its palette preference).
  factory HearthColors.dark() => const HearthColors(
    background: Color(0xFF141110),
    surface: Color(0xFF1C1815),
    surfaceElevated: Color(0xFF241F1B),
    surfaceSunken: Color(0xFF0F0D0C),
    outline: Color(0xFF3A322B),
    outlineStrong: Color(0xFF7A6B5C),
    textPrimary: Color(0xFFF6EFE4),
    textSecondary: Color(0xFFCDBEAB),
    textMuted: Color(0xFFA89685),
    accent: Color(0xFFEE9B63),
    accentPressed: Color(0xFFF3B183),
    onAccent: Color(0xFF241109),
    overAccent: Color(0xFFF0A878),
    progressTrack: Color(0xFF322A24),
    error: Color(0xFFF2A08F),
    onError: Color(0xFF241109),
  );

  /// The page ground.
  final Color background;

  /// Cards, sheets, list rows.
  final Color surface;

  /// Raised surfaces: dialogs, menus.
  final Color surfaceElevated;

  /// Recessed surfaces: input fields, inactive tabs.
  final Color surfaceSunken;

  /// Hairline dividers and card borders.
  final Color outline;

  /// Borders that need to be seen: focused fields, selected chips.
  final Color outlineStrong;

  /// Body copy, recipe titles, macro numbers.
  final Color textPrimary;

  /// Supporting copy that must still clear AA.
  final Color textSecondary;

  /// Metadata and hints. Large or bold use only — see the contrast test.
  final Color textMuted;

  /// The single accent: actions, progress fill, selection.
  final Color accent;

  final Color accentPressed;

  /// Text and icons drawn on [accent].
  final Color onAccent;

  /// Reinforces an over-target macro state. Never the only signal.
  final Color overAccent;

  /// The unfilled part of a progress bar.
  final Color progressTrack;

  /// Validation failures. A deep brick in light, a lifted coral in dark — both
  /// inside the warm family rather than a fifth hue. As everywhere else, the
  /// message carries the meaning; this only reinforces it (spec §6.3).
  final Color error;

  /// Text and icons drawn on [error].
  final Color onError;

  @override
  HearthColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? outline,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentPressed,
    Color? onAccent,
    Color? overAccent,
    Color? progressTrack,
    Color? error,
    Color? onError,
  }) => HearthColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    outline: outline ?? this.outline,
    outlineStrong: outlineStrong ?? this.outlineStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentPressed: accentPressed ?? this.accentPressed,
    onAccent: onAccent ?? this.onAccent,
    overAccent: overAccent ?? this.overAccent,
    progressTrack: progressTrack ?? this.progressTrack,
    error: error ?? this.error,
    onError: onError ?? this.onError,
  );

  @override
  HearthColors lerp(ThemeExtension<HearthColors>? other, double t) {
    if (other is! HearthColors) return this;
    return HearthColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      overAccent: Color.lerp(overAccent, other.overAccent, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
    );
  }
}

/// WCAG contrast helpers, used by the theme tests and by any widget that has
/// to choose a foreground at runtime.
abstract final class Contrast {
  /// WCAG 2.1 contrast ratio between two opaque colours, 1.0 to 21.0.
  static double ratio(Color foreground, Color background) {
    final double a = foreground.computeLuminance();
    final double b = background.computeLuminance();
    final double lighter = a > b ? a : b;
    final double darker = a > b ? b : a;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// AA for body text.
  static bool meetsAA(Color foreground, Color background) =>
      ratio(foreground, background) >= 4.5;

  /// AA for large text (18pt+, or 14pt+ bold) and for UI component boundaries.
  static bool meetsAALarge(Color foreground, Color background) =>
      ratio(foreground, background) >= 3.0;
}
