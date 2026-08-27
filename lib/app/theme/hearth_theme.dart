import 'package:flutter/material.dart';

import 'hearth_colors.dart';
import 'hearth_spacing.dart';
import 'hearth_typography.dart';

/// Builds Hearth's [ThemeData] from the colour and type tokens.
///
/// Light and dark are defined together from day one (spec §6.1); light ships
/// first, but nothing here is light-only, so dark can never drift into being
/// an afterthought.
abstract final class HearthTheme {
  static ThemeData light() => _build(HearthColors.light(), Brightness.light);

  static ThemeData dark() => _build(HearthColors.dark(), Brightness.dark);

  static ThemeData _build(HearthColors c, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final TextTheme textTheme = HearthTypography.materialTextTheme(
      isDark: isDark,
    ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.error,
      onError: c.onError,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.outlineStrong,
      outlineVariant: c.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          side: BorderSide(color: c.outline),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.pressed)) return c.accentPressed;
            return c.accent;
          }),
          foregroundColor: WidgetStatePropertyAll<Color>(c.onAccent),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            HearthTypography.label(),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(HearthTouch.minTarget, HearthTouch.minTarget),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HearthRadius.md),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(c.accent),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            HearthTypography.label(),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(HearthTouch.minTarget, HearthTouch.minTarget),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunken,
        hintStyle: HearthTypography.body().copyWith(color: c.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HearthRadius.md),
          borderSide: BorderSide(color: c.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HearthRadius.md),
          borderSide: BorderSide(color: c.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HearthRadius.md),
          borderSide: BorderSide(color: c.outlineStrong, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HearthRadius.md),
          borderSide: BorderSide(color: c.error, width: 2),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        c,
        HearthTextStyles.of(isDark: isDark),
      ],
    );
  }
}

/// Reaches the Hearth tokens from a widget.
extension HearthThemeContext on BuildContext {
  HearthColors get colors => Theme.of(this).extension<HearthColors>()!;

  HearthTextStyles get text => Theme.of(this).extension<HearthTextStyles>()!;
}
