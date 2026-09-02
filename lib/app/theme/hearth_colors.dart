import 'package:flutter/material.dart';

/// Hearth's colour tokens (spec §6.1).
///
/// Palette discipline is 60/30/10 with two to four colours total: one surface
/// family, one neutral text family, one accent. Everything here is a member of
/// one of those three families or a shade of them — resist adding a fifth hue.
///
/// **Macro states do now carry a green and a red, and the exception is
/// deliberate.** They were both terracotta to begin with — #A8480F against
/// #8A3A0B, which is the same colour to most eyes, and in dark mode the
/// "over" shade was actually the *lighter* of the two. The icon and the label
/// were doing the entire job while the palette pretended to help.
///
/// So [goodAccent] and [overAccent] are a real pair now, chosen as a herb
/// green and a brick red rather than a traffic light: this is a kitchen, not a
/// dashboard, and Hearth is defined against the calorie cop. That is a fifth
/// hue and a sixth; nothing else gets one.
///
/// Colour still never carries meaning alone (spec §6.3), and here that is not
/// a formality. Simulated for deuteranopia the two collapse to nearly the same
/// khaki — about 1.2:1 apart — so the check, the arrow, and the words beside
/// them are the signal, and the colour is what makes it quick.
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
    required this.goodAccent,
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
    goodAccent: Color(0xFF3F5F2E),
    overAccent: Color(0xFFA81F2B),
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
    goodAccent: Color(0xFF8FB86A),
    overAccent: Color(0xFFFF7A7A),
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

  /// A macro sitting where you want it (spec §5.6's `MacroTone.good`).
  ///
  /// The one hue outside the warm family, and it earns the exception: the
  /// palette is built on a single accent, so "normal" and "good" had nothing
  /// to tell them apart. A herb green rather than a signalling green — this
  /// is a kitchen, not a dashboard.
  ///
  /// **Never the only thing saying it** (§6.3). Simulated for deuteranopia,
  /// this and [overAccent] collapse to almost the same khaki — about 1.2:1
  /// apart — so the check, the arrow and the words beside them are not
  /// decoration around the colour, they are the signal, and the colour is the
  /// decoration.
  final Color goodAccent;

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
    Color? goodAccent,
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
    goodAccent: goodAccent ?? this.goodAccent,
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
      goodAccent: Color.lerp(goodAccent, other.goodAccent, t)!,
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
