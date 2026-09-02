import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/remote/photo_storage.dart';

/// Where a photo sits in the bucket (spec §5.2).
void main() {
  group('building a path', () {
    test('recipe id leads, because the policy reads it', () {
      expect(
        RecipePhotoPath.build(
          recipeId: 'recipe-1',
          objectId: 'abc',
          extension: 'jpg',
        ),
        'recipe-1/abc.jpg',
      );
    });

    test('an extension is normalised, dot and case and all', () {
      for (final String raw in <String>['.JPG', 'JPG', 'jpg']) {
        expect(
          RecipePhotoPath.build(recipeId: 'r', objectId: 'o', extension: raw),
          'r/o.jpg',
          reason: raw,
        );
      }
    });

    test('an extension the bucket would refuse becomes jpg', () {
      // The bucket has a mime allowlist; sending something outside it is a
      // guaranteed rejection, and the picker only ever produces images.
      expect(RecipePhotoPath.normaliseExtension('tiff'), 'jpg');
      expect(RecipePhotoPath.normaliseExtension(''), 'jpg');
    });

    test('and heic survives, because a Mac pick can produce one', () {
      expect(RecipePhotoPath.normaliseExtension('HEIC'), 'heic');
    });
  });

  group('reading a path back', () {
    test('round-trips', () {
      final String path = RecipePhotoPath.build(
        recipeId: 'recipe-1',
        objectId: 'abc',
        extension: 'png',
      );

      expect(RecipePhotoPath.recipeIdOf(path), 'recipe-1');
      expect(RecipePhotoPath.contentTypeOf(path), 'image/png');
    });

    test('a path with no folder belongs to no recipe', () {
      // The server-side mirror of this returns null too, and the policy then
      // denies rather than raising.
      expect(RecipePhotoPath.recipeIdOf('loose.jpg'), isNull);
      expect(RecipePhotoPath.recipeIdOf(''), isNull);
    });

    test('a deeper path is refused rather than half-read', () {
      // "a/b/c.jpg" would read as recipe "a" here while the policy reads the
      // same thing — but a path we did not write is one we should not claim.
      expect(RecipePhotoPath.recipeIdOf('a/b/c.jpg'), isNull);
    });

    test('an unknown extension is called a jpeg, not sent as itself', () {
      expect(RecipePhotoPath.contentTypeOf('r/o.tiff'), 'image/jpeg');
    });
  });
}
