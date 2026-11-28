import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/recipe_art.dart';

/// §3 of the artwork brief, as a machine check.
///
/// A drawing that arrives with an opaque background looks fine on the page
/// it was reviewed on and turns into a solid brown square the moment the
/// app tints it — and tinting is what makes one file work in both themes.
/// A drawing with colour in it loses that colour silently. A drawing whose
/// shading is a grey fill rather than hatching flattens into a shape. None
/// of those is visible in a folder of PNGs on a white page, which is where
/// a batch is looked at.
///
/// So every drawing that ships is opened and measured. The cost is a few
/// hundred milliseconds per batch and the thing it catches is a set that
/// has to be sent back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final String id in kArtworkShipped) {
    group(id, () {
      late ui.Image image;
      late Uint8List pixels;

      setUpAll(() async {
        final ByteData bytes = await rootBundle.load(RecipeArt.assetFor(id));
        final ui.Codec codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        image = (await codec.getNextFrame()).image;
        pixels = (await image.toByteData())!.buffer.asUint8List();
      });

      test('is square, and big enough for a hero', () {
        // Drawn at up to 150 points on a three-times display, so anything
        // under 450 pixels is soft where it is largest.
        expect(image.width, image.height, reason: 'not square');
        expect(image.width, greaterThanOrEqualTo(450));
      });

      test('has nothing in its corners', () {
        // The cheapest tell for an opaque background, and the failure that
        // turns a drawing into a brown square.
        final int w = image.width, h = image.height;
        for (final (int x, int y) in <(int, int)>[
          (0, 0),
          (w - 1, 0),
          (0, h - 1),
          (w - 1, h - 1),
        ]) {
          expect(
            pixels[(y * w + x) * 4 + 3],
            0,
            reason: 'the pixel at $x,$y is not transparent',
          );
        }
      });

      test('is mostly nothing, the way line art is', () {
        int clear = 0;
        for (int i = 3; i < pixels.length; i += 4) {
          if (pixels[i] == 0) clear++;
        }
        final double share = clear * 4 / pixels.length;
        expect(
          share,
          greaterThan(0.4),
          reason:
              'only ${(share * 100).round()}% of this is transparent — it is '
              'a filled picture rather than a drawing',
        );
      });

      test('is drawn in one ink, with no colour in it', () {
        // The app throws the colours away and tints what is left, so colour
        // here is work nobody will ever see — and a drawing that depends on
        // it will look wrong once it is gone.
        int coloured = 0;
        int inked = 0;
        for (int i = 0; i < pixels.length; i += 4) {
          if (pixels[i + 3] == 0) continue;
          inked++;
          final int r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
          final int max = r > g ? (r > b ? r : b) : (g > b ? g : b);
          final int min = r < g ? (r < b ? r : b) : (g < b ? g : b);
          if (max - min > 40) coloured++;
        }
        expect(inked, greaterThan(0), reason: 'the drawing is empty');
        expect(
          coloured / inked,
          lessThan(0.02),
          reason: 'there is colour in this drawing',
        );
      });

      test('has soft edges, which is where the grain lives', () {
        // Shading made of hatching and a pen that catches on the paper both
        // show up as partial alpha. A drawing that is only 0 and 255 was
        // drawn with a hard-edged tool and will read as a sticker.
        int soft = 0;
        for (int i = 3; i < pixels.length; i += 4) {
          if (pixels[i] > 0 && pixels[i] < 255) soft++;
        }
        expect(
          soft * 4 / pixels.length,
          greaterThan(0.02),
          reason: 'no partial alpha anywhere — this is not a drawing',
        );
      });
    });
  }
}
