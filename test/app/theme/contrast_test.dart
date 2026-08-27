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
        expect(
          Contrast.ratio(c.outlineStrong, c.surface),
          greaterThanOrEqualTo(3.0),
          reason: 'outlineStrong must be usable as a focus indicator',
        );
      });
    });
  }

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
