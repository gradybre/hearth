import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_colors.dart';

/// Automated accessibility floor for the palette (spec §6.3, §9.6).
///
/// Contrast is the one accessibility property that can be proven without
/// rendering anything, so it is checked on every token pair the UI actually
/// composes — in both themes. A palette change that dims text below AA fails
/// here rather than in a kitchen.
void main() {
  final Map<String, HearthColors> themes = <String, HearthColors>{
    'light': HearthColors.light(),
    'dark': HearthColors.dark(),
  };

  for (final MapEntry<String, HearthColors> entry in themes.entries) {
    final String name = entry.key;
    final HearthColors c = entry.value;

    group('$name theme', () {
      /// Every ground body text is drawn on.
      final Map<String, Color> grounds = <String, Color>{
        'background': c.background,
        'surface': c.surface,
        'surfaceElevated': c.surfaceElevated,
        'surfaceSunken': c.surfaceSunken,
      };

      test('primary text clears AA on every surface', () {
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.textPrimary, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'textPrimary on ${ground.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('secondary text clears AA on every surface', () {
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.textSecondary, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'textSecondary on ${ground.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('muted text clears at least the large-text floor', () {
        // Muted is documented as large-or-bold use only, so it is held to 3:1
        // rather than 4.5:1 — and the widget layer must honour that.
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.textMuted, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                'textMuted on ${ground.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('accent works as an action colour on the page grounds', () {
        // Accent carries buttons and links: it must clear the UI-component
        // floor against anything it sits on.
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.accent, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: 'accent on ${ground.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      test('text on the accent clears AA', () {
        expect(
          Contrast.ratio(c.onAccent, c.accent),
          greaterThanOrEqualTo(4.5),
          reason:
              'onAccent on accent is '
              '${Contrast.ratio(c.onAccent, c.accent).toStringAsFixed(2)}:1',
        );
      });

      test('the over-target accent is distinguishable from the ground', () {
        expect(
          Contrast.ratio(c.overAccent, c.background),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('progress fill is visible against its track', () {
        expect(
          Contrast.ratio(c.accent, c.progressTrack),
          greaterThanOrEqualTo(3.0),
          reason:
              'accent on progressTrack is '
              '${Contrast.ratio(c.accent, c.progressTrack).toStringAsFixed(2)}'
              ':1',
        );
      });

      test('error text clears AA on every surface', () {
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.error, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'error on ${ground.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        }
        expect(Contrast.ratio(c.onError, c.error), greaterThanOrEqualTo(4.5));
      });

      test('borders are perceivable against their surfaces', () {
        // A focus ring is drawn on whatever the focused control is filled
        // with, and text fields are filled with surfaceSunken — so checking
        // only against `surface` left the one ground it actually lands on
        // untested. Warming the light palette pushed that pair to 2.89:1
        // before this widened.
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.outlineStrong, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                'outlineStrong on ${ground.key} is '
                '${ratio.toStringAsFixed(2)}:1 and must be usable as a focus '
                'indicator',
          );
        }
      });

      test('the accent is legible as button and link text', () {
        // The accent is not only a fill: it is the foreground of every
        // TextButton (see HearthTheme), which is body-sized. The 3:1
        // component floor above is not enough for that job.
        for (final MapEntry<String, Color> ground in grounds.entries) {
          final double ratio = Contrast.ratio(c.accent, ground.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'accent as text on ${ground.key} is '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });
  }

  /// The regression guard for "light mode does not have a cream background —
  /// it is a bright white".
  ///
  /// Every contrast test above passed while the light theme's ground was
  /// 1.07:1 from pure white and its cards were 1.02:1 from it, because
  /// contrast against dark text says nothing about whether a surface is the
  /// warm paper §6.1 asks for. These assertions are the missing half.
  group('light surfaces are paper cream, not white', () {
    final HearthColors c = HearthColors.light();
    final Map<String, Color> surfaces = <String, Color>{
      'background': c.background,
      'surface': c.surface,
      'surfaceElevated': c.surfaceElevated,
      'surfaceSunken': c.surfaceSunken,
    };

    test('no light surface is white or near-white', () {
      const Color white = Color(0xFFFFFFFF);
      for (final MapEntry<String, Color> s in surfaces.entries) {
        expect(
          s.value.r,
          lessThan(1.0),
          reason: '${s.key} has a maxed red channel — that is white, not cream',
        );
        expect(
          Contrast.ratio(s.value, white),
          greaterThanOrEqualTo(1.08),
          reason:
              '${s.key} is ${Contrast.ratio(s.value, white).toStringAsFixed(3)}'
              ':1 from pure white and will read as white on a phone',
        );
      }
    });

    test('every light surface is warm, not neutral', () {
      // Cream is a red-over-blue tilt. Without a floor here a palette can
      // drift to grey while every contrast test stays green.
      for (final MapEntry<String, Color> s in surfaces.entries) {
        final double spread = (s.value.r - s.value.b) * 255;
        expect(
          spread,
          greaterThanOrEqualTo(12),
          reason:
              '${s.key} has a red-to-blue spread of '
              '${spread.toStringAsFixed(0)}/255 — too neutral to read as paper',
        );
      }
    });

    test('a card still reads as a card on the warmed ground', () {
      // Fill alone carries most of this; the border carries the rest. If the
      // ground warms and the card does not move with it, the list flattens
      // into one sheet.
      expect(
        Contrast.ratio(c.surface, c.background),
        greaterThanOrEqualTo(1.08),
        reason:
            'surface on background is '
            '${Contrast.ratio(c.surface, c.background).toStringAsFixed(3)}:1',
      );
      expect(
        Contrast.ratio(c.surfaceSunken, c.background),
        greaterThanOrEqualTo(1.08),
        reason: 'a sunken field must read as recessed from the ground',
      );
    });
  });

  group('dark surfaces stay separable', () {
    final HearthColors c = HearthColors.dark();

    test('the dark ground is still near-black, not a warmed brown', () {
      // Spec §6.1's kitchen-first rule beats its palette preference here, and
      // the light fix must not quietly drag dark towards cosy mud.
      expect(
        Contrast.ratio(c.background, const Color(0xFF000000)),
        lessThan(2),
      );
      expect(Contrast.ratio(c.textPrimary, c.background), greaterThan(12));
    });
  });

  group('Contrast helper', () {
    test('black on white is the maximum ratio', () {
      expect(
        Contrast.ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
    });

    test('a colour against itself is 1:1', () {
      expect(
        Contrast.ratio(const Color(0xFF808080), const Color(0xFF808080)),
        closeTo(1, 1e-9),
      );
    });

    test('order does not matter', () {
      const Color a = Color(0xFF123456);
      const Color b = Color(0xFFEEDDCC);
      expect(Contrast.ratio(a, b), closeTo(Contrast.ratio(b, a), 1e-9));
    });

    test('the AA thresholds are the WCAG ones', () {
      expect(
        Contrast.meetsAA(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        isTrue,
      );
      // 4.478:1 — just under the line, and therefore a failure.
      expect(
        Contrast.meetsAA(const Color(0xFF777777), const Color(0xFFFFFFFF)),
        isFalse,
      );
      expect(
        Contrast.meetsAA(const Color(0xFF949494), const Color(0xFFFFFFFF)),
        isFalse,
      );
      expect(
        Contrast.meetsAALarge(const Color(0xFF949494), const Color(0xFFFFFFFF)),
        isTrue,
      );
    });
  });
}
