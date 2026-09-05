import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    // Material 3 draws a great deal from roles this scheme never named, and
    // every unnamed one silently falls back: each `surfaceContainer*` to
    // `surface`, and `surfaceTint` to `primary`. So dialogs, menus, sheets and
    // the nav bar all collapsed onto the single card colour, and anything
    // Material considered elevated got a wash of terracotta it was never asked
    // for. Both were invisible while `surface` was near-white; on a cream
    // ground they are not. The whole ramp is named here.
    //
    // The ramp runs brightest-to-dimmest in light and the other way in dark,
    // which is Material's own convention and the reason this is written out
    // per brightness rather than shared.
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
      onSurfaceVariant: c.textSecondary,
      surfaceBright: c.surfaceElevated,
      surfaceDim: c.surfaceSunken,
      surfaceContainerLowest: isDark ? c.surfaceSunken : c.surfaceElevated,
      surfaceContainerLow: isDark ? c.background : c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: isDark ? c.surfaceElevated : c.background,
      surfaceContainerHighest: isDark ? c.surfaceElevated : c.surfaceSunken,
      // Elevation in Hearth is carried by a border and a soft shadow, never by
      // dyeing a surface with the accent — that is a 60/30/10 leak.
      surfaceTint: Colors.transparent,
      // Shadows and modal scrims on a cream ground should be brown, not
      // neutral black — and in dark they have to stay the darkest thing in the
      // palette rather than following `textPrimary` up into the cream.
      shadow: isDark ? c.surfaceSunken : c.textPrimary,
      scrim: isDark ? c.surfaceSunken : c.textPrimary,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: c.onAccent,
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
      // The chrome below had no theme at all and was running on Material's
      // defaults. Screens that set an app bar colour by hand were fine;
      // dialogs, sheets, menus and the nav bar were not, and every one of them
      // resolved to the same near-white. Naming them here is also the only
      // lever that reaches the app shell without editing it.
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        // Material's default lifts an app bar's colour as content scrolls
        // under it. With no tint left to lift it just goes flat, so the seam
        // is drawn rather than shaded.
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Stated rather than inferred: the status bar sits directly on this
        // colour, and a theme change should not be able to leave it guessing.
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HearthRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        modalBackgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: c.outlineStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HearthRadius.lg),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.surfaceSunken,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.surfaceSunken,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.progressTrack,
        circularTrackColor: c.progressTrack,
      ),
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
            // Disabled has to be visibly different: a primary action that
            // paints full accent while doing nothing on tap is a lie on
            // screen. It is never the only signal — Flutter also reports the
            // button as disabled to a screen reader (spec §6.3).
            if (states.contains(WidgetState.disabled)) return c.surfaceSunken;
            if (states.contains(WidgetState.pressed)) return c.accentPressed;
            return c.accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) return c.textMuted;
            return c.onAccent;
          }),
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
