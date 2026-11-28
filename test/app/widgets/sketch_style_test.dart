import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/sketch_style.dart';

/// How much craft a sketch is drawn with (spec §6.1, §6.3).
///
/// The whole decision is one number in and a value out, which is why it is
/// here rather than buried in a paint method: a condition inside `paint` is
/// a condition nothing can test, and the failure it hides — hatching on a
/// forty-point thumbnail — looks like a smudge rather than like a bug.
void main() {
  group('a thumbnail is drawn plainly', () {
    for (final double size in <double>[20, 36, 40, 48, 64, 71.9]) {
      test('at $size points', () {
        final SketchStyle style = SketchStyle.forSize(size);
        expect(style, SketchStyle.plain);
        expect(style.hatch, isFalse, reason: 'hatching at $size is a smudge');
        expect(style.brokenInk, isFalse, reason: 'a dotted line at $size');
      });
    }
  });

  group('and a picture is drawn with everything', () {
    for (final double size in <double>[72, 96, 150, 400]) {
      test('at $size points', () {
        final SketchStyle style = SketchStyle.forSize(size);
        expect(style, SketchStyle.engraved);
        expect(style.hatch, isTrue);
        expect(style.brokenInk, isTrue);
      });
    }
  });

  test('the wash lightens when hatching takes over the shading', () {
    // Two kinds of shadow on one shape is a smudge. The flat wash was
    // carrying the whole of it before; now it is only the ground under the
    // lines.
    expect(
      SketchStyle.engraved.washAlpha,
      lessThan(SketchStyle.plain.washAlpha),
    );
  });

  group('the ink wanders, and stays where it was put', () {
    test('it never leaves the paper or doubles the ink', () {
      // Alpha outside 0 to 1 is a crash in release and a clamp in debug;
      // either way the drawing is not what anybody drew.
      for (int seed = 0; seed < 8; seed++) {
        for (int i = 0; i <= 40; i++) {
          final double ink = SketchStyle.inkAt(i / 40, seed);
          expect(
            ink,
            inInclusiveRange(0, 1),
            reason: 'seed $seed at ${i / 40}',
          );
        }
      }
    });

    test('it is seeded, not random', () {
      // A drawing that shimmered on every repaint would be worse than one
      // drawn flat, and a list of recipes repaints on every scroll frame.
      for (int seed = 0; seed < 4; seed++) {
        expect(
          <double>[
            for (int i = 0; i <= 10; i++) SketchStyle.inkAt(i / 10, seed),
          ],
          <double>[
            for (int i = 0; i <= 10; i++) SketchStyle.inkAt(i / 10, seed),
          ],
        );
      }
    });

    test('and two shapes in one drawing are not inked alike', () {
      // Same wave on every stroke reads as a pattern rather than as ink.
      final List<double> first = <double>[
        for (int i = 0; i <= 10; i++) SketchStyle.inkAt(i / 10, 0),
      ];
      final List<double> second = <double>[
        for (int i = 0; i <= 10; i++) SketchStyle.inkAt(i / 10, 1),
      ];
      expect(first, isNot(second));
    });

    test('it is never so thin the line disappears', () {
      // Broken ink is a line that varies, not a dotted one. Below about
      // half strength a 2pt stroke on cream stops being a line.
      for (int seed = 0; seed < 8; seed++) {
        for (int i = 0; i <= 40; i++) {
          expect(SketchStyle.inkAt(i / 40, seed), greaterThan(0.5));
        }
      }
    });
  });
}
