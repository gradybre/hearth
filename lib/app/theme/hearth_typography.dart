import 'package:flutter/material.dart';

/// Hearth's type tokens (spec §6.1).
///
/// A serif with character for titles, a quiet humanist sans for body and data.
/// Both are bundled variable fonts, so weight is driven by an explicit
/// [FontVariation] on the `wght` axis rather than relying on synthetic
/// weights — and Fraunces' optical-size axis is tracked to the actual size, so
/// a 32pt title and a 20pt header are drawn with the right letterforms rather
/// than one scaled copy.
///
/// Every numeric style carries [FontFeature.tabularFigures]. Macro columns
/// have to align, and a live "142 g protein left" readout must not jitter as
/// digits change.
abstract final class HearthTypography {
  static const String serif = 'Fraunces';
  static const String sans = 'SourceSans3';

  /// Fraunces' softness axis. ~50 rounds the sharp corners a little, reading
  /// like ink spread on paper — a recipe box rather than a spreadsheet.
  static const double _softness = 50;

  /// Fraunces' "wonk" axis stays at 0: the wonky letterforms are charming in a
  /// specimen and a legibility cost at arm's length in a kitchen.
  static const double _wonk = 0;

  static List<FontVariation> _serifAxes(double weight, double opticalSize) =>
      <FontVariation>[
        FontVariation('wght', weight),
        FontVariation('opsz', opticalSize),
        const FontVariation('SOFT', _softness),
        const FontVariation('WONK', _wonk),
      ];

  static List<FontVariation> _sansAxes(double weight) => <FontVariation>[
    FontVariation('wght', weight),
  ];

  /// Serif headers are drawn a step lighter in dark mode.
  ///
  /// Light text on a dark ground blooms — the same weight that reads as
  /// confident on cream reads as heavy and slightly smeared inverted.
  static double serifHeaderWeight({required bool isDark}) => isDark ? 500 : 600;

  static TextStyle recipeTitle({required bool isDark}) {
    final double weight = serifHeaderWeight(isDark: isDark);
    return TextStyle(
      fontFamily: serif,
      fontSize: 32,
      height: 1.1,
      fontWeight: isDark ? FontWeight.w500 : FontWeight.w600,
      fontVariations: _serifAxes(weight, 32),
    );
  }

  static TextStyle sectionHeader({required bool isDark}) {
    final double weight = serifHeaderWeight(isDark: isDark);
    return TextStyle(
      fontFamily: serif,
      fontSize: 20,
      height: 1.2,
      fontWeight: isDark ? FontWeight.w500 : FontWeight.w600,
      fontVariations: _serifAxes(weight, 20),
    );
  }

  /// Directions, notes, and general prose.
  static TextStyle body() => TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: _sansAxes(400),
  );

  /// An ingredient line. Same size as body, but its numbers must align down
  /// the list, so it takes tabular figures.
  static TextStyle ingredient() => TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: _sansAxes(400),
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The large macro number on the day view.
  static TextStyle macroReadout() => TextStyle(
    fontFamily: sans,
    fontSize: 36,
    height: 1.0,
    fontWeight: FontWeight.w400,
    fontVariations: _sansAxes(400),
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Labels under macro numbers, timestamps, source badges.
  static TextStyle metadata() => TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
    fontVariations: _sansAxes(500),
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Buttons and interactive labels.
  static TextStyle label() => TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: _sansAxes(600),
  );

  /// A Material [TextTheme] so stock widgets inherit the same type.
  static TextTheme materialTextTheme({required bool isDark}) {
    final TextStyle bodyStyle = body();
    return TextTheme(
      displayLarge: recipeTitle(isDark: isDark),
      headlineMedium: recipeTitle(isDark: isDark),
      titleLarge: sectionHeader(isDark: isDark),
      titleMedium: sectionHeader(isDark: isDark).copyWith(fontSize: 17),
      bodyLarge: bodyStyle,
      bodyMedium: bodyStyle,
      bodySmall: metadata().copyWith(fontSize: 13),
      labelLarge: label(),
      labelMedium: metadata(),
      labelSmall: metadata(),
    );
  }
}

/// Named type roles, reachable from any widget via `Theme.of(context)`.
@immutable
class HearthTextStyles extends ThemeExtension<HearthTextStyles> {
  const HearthTextStyles({
    required this.recipeTitle,
    required this.sectionHeader,
    required this.body,
    required this.ingredient,
    required this.macroReadout,
    required this.metadata,
    required this.label,
  });

  factory HearthTextStyles.of({required bool isDark}) => HearthTextStyles(
    recipeTitle: HearthTypography.recipeTitle(isDark: isDark),
    sectionHeader: HearthTypography.sectionHeader(isDark: isDark),
    body: HearthTypography.body(),
    ingredient: HearthTypography.ingredient(),
    macroReadout: HearthTypography.macroReadout(),
    metadata: HearthTypography.metadata(),
    label: HearthTypography.label(),
  );

  final TextStyle recipeTitle;
  final TextStyle sectionHeader;
  final TextStyle body;
  final TextStyle ingredient;
  final TextStyle macroReadout;
  final TextStyle metadata;
  final TextStyle label;

  @override
  HearthTextStyles copyWith({
    TextStyle? recipeTitle,
    TextStyle? sectionHeader,
    TextStyle? body,
    TextStyle? ingredient,
    TextStyle? macroReadout,
    TextStyle? metadata,
    TextStyle? label,
  }) => HearthTextStyles(
    recipeTitle: recipeTitle ?? this.recipeTitle,
    sectionHeader: sectionHeader ?? this.sectionHeader,
    body: body ?? this.body,
    ingredient: ingredient ?? this.ingredient,
    macroReadout: macroReadout ?? this.macroReadout,
    metadata: metadata ?? this.metadata,
    label: label ?? this.label,
  );

  @override
  HearthTextStyles lerp(ThemeExtension<HearthTextStyles>? other, double t) {
    if (other is! HearthTextStyles) return this;
    return HearthTextStyles(
      recipeTitle: TextStyle.lerp(recipeTitle, other.recipeTitle, t)!,
      sectionHeader: TextStyle.lerp(sectionHeader, other.sectionHeader, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      ingredient: TextStyle.lerp(ingredient, other.ingredient, t)!,
      macroReadout: TextStyle.lerp(macroReadout, other.macroReadout, t)!,
      metadata: TextStyle.lerp(metadata, other.metadata, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
    );
  }
}
