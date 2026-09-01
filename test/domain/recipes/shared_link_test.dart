import 'package:hearth/domain/recipes/shared_link.dart';
import 'package:test/test.dart';

/// What a shared link is worth, before a round trip is spent finding out.
///
/// The Instagram entry is not a precaution — fetching a reel URL without a
/// session returns 200 OK, ~600 KB of JavaScript, no Open Graph tags, and
/// `<title>Instagram</title>`. There is no caption in the response to read.
void main() {
  group('links a server can read', () {
    test('an ordinary recipe page is readable', () {
      final SharedLink link = SharedLink.of(
        'https://www.seriouseats.com/braised-short-ribs-recipe',
      );

      expect(link.isReadable, isTrue);
      expect(link.unreadableBecause, isNull);
    });

    test('so is a creator\'s own blog, which is where a DM link goes', () {
      expect(
        SharedLink.of('https://halfbakedharvest.com/x/').isReadable,
        isTrue,
      );
    });
  });

  group('links behind a login wall', () {
    test('an Instagram reel says what to do instead', () {
      final SharedLink link = SharedLink.of(
        'https://www.instagram.com/reel/C8QltHYyPqe/',
      );

      expect(link.isReadable, isFalse);
      expect(link.unreadableBecause, contains('Screenshot the caption'));
    });

    test('a post, a share link, and the bare host are all the same site', () {
      for (final String url in <String>[
        'https://instagram.com/p/C8QltHYyPqe/',
        'https://www.instagram.com/reel/C8QltHYyPqe/?igsh=abc123',
        'https://l.instagram.com/reel/C8QltHYyPqe/',
      ]) {
        expect(SharedLink.of(url).isReadable, isFalse, reason: url);
      }
    });

    test('TikTok answers the same way for the same reason', () {
      expect(
        SharedLink.of('https://www.tiktok.com/@cook/video/7300').isReadable,
        isFalse,
      );
    });

    test('a site that merely mentions one is not one', () {
      // Substring matching would have caught this, which is why the host is
      // compared as a host and not searched for.
      expect(
        SharedLink.of('https://instagram.com.recipes.example/x').isReadable,
        isTrue,
      );
      expect(SharedLink.of('https://notinstagram.com/x').isReadable, isTrue);
    });
  });

  group('what is not a link at all', () {
    test('shared recipe text is empty rather than broken', () {
      // A DM pasted in as text is the good case, not a failure — it goes
      // straight to the extractor. It just is not a link.
      final SharedLink link = SharedLink.of(
        '2 lb ground beef\n1 tbsp soy sauce\nBrown the beef...',
      );

      expect(link.isEmpty, isTrue);
      expect(link.isReadable, isFalse);
    });

    test('nothing here throws, whatever arrives', () {
      for (final String raw in <String>[
        '',
        '   ',
        'not a url',
        'ftp://example.com/x',
        'instagram.com/reel/abc',
        '://',
        'hearth://shared',
      ]) {
        expect(SharedLink.of(raw).isEmpty, isTrue, reason: raw);
      }
    });
  });
}
