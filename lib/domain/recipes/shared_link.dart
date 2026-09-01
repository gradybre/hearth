import 'package:meta/meta.dart';

/// What Hearth can expect to get out of a link somebody shared (spec §5.3).
///
/// Import reads a page by fetching it server-side and handing the visible
/// words to the model. That works for a recipe blog and does not work for
/// Instagram: an unauthenticated fetch of `instagram.com/reel/…` comes back
/// 200 OK with about 600 KB of JavaScript, no Open Graph tags at all, and
/// `<title>Instagram</title>`. The caption is never in the response. TikTok
/// answers the same way for the same reason.
///
/// So this is not a guess about what *might* fail — it is a list of two sites
/// whose behaviour has been checked, kept here rather than in the import
/// screen so that the app can say what is wrong before spending a round trip
/// to find out, and so that the claim can be tested at all.
///
/// The fix is never to try harder. It is to say plainly that a screenshot of
/// the caption works, which it does: reading photographed text is the same
/// path §5.3 already calls the primary migration route.
@immutable
class SharedLink {
  const SharedLink._({required this.url, this.unreadableBecause});

  /// Classifies [raw]. Anything that is not a usable http(s) link comes back
  /// with an empty [url], which callers treat as "there was no link here" —
  /// shared text is a separate thing and is not a failure.
  factory SharedLink.of(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const SharedLink._(url: '');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const SharedLink._(url: '');
    }

    final String host = uri.host.toLowerCase();
    for (final MapEntry<String, String> walled in _loginWalled.entries) {
      if (host == walled.key || host.endsWith('.${walled.key}')) {
        return SharedLink._(
          url: uri.toString(),
          unreadableBecause: walled.value,
        );
      }
    }
    return SharedLink._(url: uri.toString());
  }

  final String url;

  /// Why this link cannot be read, in words worth showing someone, or null
  /// when there is no reason to think it can't.
  final String? unreadableBecause;

  bool get isEmpty => url.isEmpty;

  bool get isReadable => url.isNotEmpty && unreadableBecause == null;

  /// Sites that serve a login wall to anything that is not a signed-in
  /// browser, keyed by host, valued by what to tell the person holding the
  /// phone.
  ///
  /// Deliberately short and deliberately specific. A general "some sites
  /// don't work" would be true of nothing in particular and useful to nobody;
  /// naming the site and the way round it is the whole point.
  static const Map<String, String> _loginWalled = <String, String>{
    'instagram.com':
        "Instagram doesn't let apps read a reel's caption — the page comes "
        'back empty without a login. Screenshot the caption and share that '
        'instead, and Hearth will read the recipe off it.',
    'tiktok.com':
        "TikTok doesn't let apps read a post's caption. Screenshot the "
        'caption and share that instead, and Hearth will read the recipe off '
        'it.',
  };
}
