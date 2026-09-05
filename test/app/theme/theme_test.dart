import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/hearth_typography.dart';

double _widthOf(TextStyle style, String text) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  group('theme construction', () {
    test('both themes carry the Hearth token extensions', () {
      for (final ThemeData theme in <ThemeData>[
        HearthTheme.light(),
        HearthTheme.dark(),
      ]) {
        expect(theme.extension<HearthColors>(), isNotNull);
        expect(theme.extension<HearthTextStyles>(), isNotNull);
      }
    });

    test('brightness and ground match the palette', () {
      final ThemeData light = HearthTheme.light();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, HearthColors.light().background);

      final ThemeData dark = HearthTheme.dark();
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, HearthColors.dark().background);
    });

    test('no Material surface role falls back to the card colour', () {
      // Unnamed `surfaceContainer*` roles all resolve to `surface`, which is
      // how dialogs, sheets, menus and the nav bar ended up sharing one
      // near-white. Naming them is the fix; this is the guard.
      for (final ThemeData theme in <ThemeData>[
        HearthTheme.light(),
        HearthTheme.dark(),
      ]) {
        final HearthColors c = theme.extension<HearthColors>()!;
        final ColorScheme s = theme.colorScheme;
        expect(
          <Color>{
            s.surfaceContainerLowest,
            s.surfaceContainerLow,
            s.surfaceContainer,
            s.surfaceContainerHigh,
            s.surfaceContainerHighest,
          }.length,
          greaterThan(2),
          reason: 'the container ramp has collapsed onto one colour',
        );
        expect(s.surfaceDim, c.surfaceSunken);
        expect(s.surfaceBright, c.surfaceElevated);
      }
    });

    test('elevation is never dyed with the accent', () {
      // `surfaceTint` falls back to `primary`, which puts a terracotta wash on
      // every elevated Material and on any app bar with content scrolled under
      // it — a 60/30/10 leak nobody asked for.
      for (final ThemeData theme in <ThemeData>[
        HearthTheme.light(),
        HearthTheme.dark(),
      ]) {
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
      }
    });

    test('the chrome that has no colour of its own gets Hearth tokens', () {
      for (final ThemeData theme in <ThemeData>[
        HearthTheme.light(),
        HearthTheme.dark(),
      ]) {
        final HearthColors c = theme.extension<HearthColors>()!;
        expect(theme.appBarTheme.backgroundColor, c.surface);
        expect(theme.dialogTheme.backgroundColor, c.surfaceElevated);
        expect(theme.bottomSheetTheme.modalBackgroundColor, c.surfaceElevated);
        expect(theme.popupMenuTheme.color, c.surfaceElevated);
        expect(theme.navigationBarTheme.backgroundColor, c.surface);
        expect(theme.navigationBarTheme.indicatorColor, c.surfaceSunken);
        expect(theme.navigationRailTheme.backgroundColor, c.surface);
      }
    });

    test('the status bar is told which way round it is', () {
      expect(
        HearthTheme.light().appBarTheme.systemOverlayStyle,
        SystemUiOverlayStyle.dark,
      );
      expect(
        HearthTheme.dark().appBarTheme.systemOverlayStyle,
        SystemUiOverlayStyle.light,
      );
    });

    test(
      'body text inherits the primary text colour, not Material default',
      () {
        final ThemeData light = HearthTheme.light();
        expect(
          light.textTheme.bodyMedium!.color,
          HearthColors.light().textPrimary,
        );
      },
    );
  });

  group('typography tokens', () {
    test('titles are the serif, body and data are the sans', () {
      final HearthTextStyles t = HearthTextStyles.of(isDark: false);
      expect(t.recipeTitle.fontFamily, HearthTypography.serif);
      expect(t.sectionHeader.fontFamily, HearthTypography.serif);
      expect(t.body.fontFamily, HearthTypography.sans);
      expect(t.ingredient.fontFamily, HearthTypography.sans);
      expect(t.macroReadout.fontFamily, HearthTypography.sans);
      expect(t.metadata.fontFamily, HearthTypography.sans);
    });

    test('every numeric style uses tabular figures', () {
      // Macro columns must align, and a live readout must not jitter as its
      // digits change (spec §5.6).
      final HearthTextStyles t = HearthTextStyles.of(isDark: false);
      for (final MapEntry<String, TextStyle> style in <String, TextStyle>{
        'ingredient': t.ingredient,
        'macroReadout': t.macroReadout,
        'metadata': t.metadata,
      }.entries) {
        expect(
          style.value.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '${style.key} carries numbers and must be tabular',
        );
      }
    });

    test('tabular figures actually hold digit widths equal', () {
      final TextStyle style = HearthTypography.macroReadout();
      // '1' is the narrowest digit in most proportional fonts; if the feature
      // were not applied, these would differ.
      expect(_widthOf(style, '1111'), closeTo(_widthOf(style, '8888'), 0.01));
    });

    test('serif headers lighten in dark mode to stop them blooming', () {
      expect(HearthTypography.serifHeaderWeight(isDark: false), 600);
      expect(HearthTypography.serifHeaderWeight(isDark: true), 500);
      expect(
        HearthTextStyles.of(isDark: true).recipeTitle.fontWeight,
        FontWeight.w500,
      );
      expect(
        HearthTextStyles.of(isDark: false).recipeTitle.fontWeight,
        FontWeight.w600,
      );
    });

    test('Fraunces axes are set deliberately', () {
      final TextStyle title = HearthTypography.recipeTitle(isDark: false);
      final Map<String, double> axes = <String, double>{
        for (final FontVariation v in title.fontVariations!) v.axis: v.value,
      };
      expect(axes['SOFT'], 50, reason: 'softened corners, ink-on-paper feel');
      expect(axes['WONK'], 0, reason: 'wonk costs legibility at arm\'s length');
      expect(
        axes['opsz'],
        title.fontSize,
        reason: 'optical size should track the rendered size',
      );
      expect(axes['wght'], 600);
    });

    test('optical size differs between title and section header', () {
      double opsz(TextStyle s) => <String, double>{
        for (final FontVariation v in s.fontVariations!) v.axis: v.value,
      }['opsz']!;

      expect(
        opsz(HearthTypography.recipeTitle(isDark: false)),
        isNot(opsz(HearthTypography.sectionHeader(isDark: false))),
      );
    });
  });

  group('bundled fonts', () {
    test(
      'the two families really are distinct faces, not a shared fallback',
      () {
        // If the bundled fonts failed to load, both styles would fall back to
        // the same default and measure identically — which would make every
        // golden test meaningless.
        const String sample = 'Hearth recipe 12345';
        final double serif = _widthOf(
          HearthTypography.recipeTitle(isDark: false),
          sample,
        );
        final double sans = _widthOf(
          HearthTypography.body().copyWith(fontSize: 32),
          sample,
        );
        expect(serif, isNot(closeTo(sans, 0.5)));
        expect(serif, greaterThan(0));
      },
    );
  });

  // Regression: the FilledButton style resolved only `pressed`, so a disabled
  // button painted full accent — a "Copy" button with nothing selected looked
  // exactly like one ready to fire. Colour is not the only signal (Flutter
  // marks the button disabled for a screen reader either way), but a primary
  // action that looks live and does nothing is a lie on screen.
  testWidgets('a disabled FilledButton does not paint like an enabled one', (
    WidgetTester tester,
  ) async {
    Future<Color?> background({required bool enabled}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HearthTheme.light(),
          home: Scaffold(
            body: FilledButton(
              onPressed: enabled ? () {} : null,
              child: const Text('Copy'),
            ),
          ),
        ),
      );
      final ButtonStyle? style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .themeStyleOf(tester.element(find.byType(FilledButton)));
      return style?.backgroundColor?.resolve(<WidgetState>{
        if (!enabled) WidgetState.disabled,
      });
    }

    expect(
      await background(enabled: false),
      isNot(await background(enabled: true)),
    );
  });
}
