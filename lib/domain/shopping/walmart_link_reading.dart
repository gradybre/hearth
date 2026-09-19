/// Structured Walmart product link result and pure canonicalizer
/// (D-WALMART-001, plan P-HEARTH-WALMART-001).
///
/// Pure Dart: no Flutter or package imports. The shaping decision (which
/// candidate strings are accepted, merged or rejected) happens server-side
/// in `supabase/functions/recipe-ai/walmart_link.ts`; this file only knows
/// how to canonicalize a single candidate URL and how to parse the already
/// shaped envelope the server returns.

/// Outcome of attempting to read a Walmart product link from screenshots.
enum WalmartLinkStatus { found, notFound, ambiguous, unreadable }

/// An immutable, already-validated Walmart link result.
///
/// Non-`found` statuses never carry a URL or source: they are either the
/// absence of any signal ([notFound]), more than one distinct plausible
/// product ([ambiguous]), or a candidate that could not be trusted
/// ([unreadable]) because it was cropped, uncertain, malformed, or of an
/// unrecognized shape. Conservatism is the point: any doubt suppresses the
/// link rather than guessing.
final class WalmartLinkReading {
  final WalmartLinkStatus status;
  final String? url;
  final String? source;

  const WalmartLinkReading._(this.status, this.url, this.source);

  /// No link signal was present at all.
  const WalmartLinkReading.notFound()
    : this._(WalmartLinkStatus.notFound, null, null);

  /// Parses the server-shaped envelope `{status, url, source}`.
  ///
  /// A completely absent envelope (`raw == null`) is [notFound]. Anything
  /// present but malformed -- wrong types, an unrecognized status, a URL or
  /// source on a non-`found` status, a `found` status whose URL is not
  /// already exactly canonical, or a `found` status without one of the
  /// four legitimate sources -- is [unreadable] rather than trusted.
  factory WalmartLinkReading.fromJson(Object? raw) {
    if (raw == null) return const WalmartLinkReading.notFound();
    if (raw is! Map) {
      return const WalmartLinkReading._(
        WalmartLinkStatus.unreadable,
        null,
        null,
      );
    }

    final Object? statusRaw = raw['status'];
    final Object? urlRaw = raw['url'];
    final Object? sourceRaw = raw['source'];

    switch (statusRaw) {
      case 'not_found':
        if (urlRaw != null || sourceRaw != null) {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        return const WalmartLinkReading.notFound();

      case 'ambiguous':
        if (urlRaw != null || sourceRaw != null) {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        return const WalmartLinkReading._(
          WalmartLinkStatus.ambiguous,
          null,
          null,
        );

      case 'unreadable':
        if (urlRaw != null || sourceRaw != null) {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        return const WalmartLinkReading._(
          WalmartLinkStatus.unreadable,
          null,
          null,
        );

      case 'found':
        if (urlRaw is! String) {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        final String? canonical = WalmartLinkReading.canonicalUrl(urlRaw);
        // Strict: the server must have already sent an exactly canonical URL.
        if (canonical == null || canonical != urlRaw) {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        if (sourceRaw != 'nutrition' &&
            sourceRaw != 'package' &&
            sourceRaw != 'both' &&
            sourceRaw != 'screenshot') {
          return const WalmartLinkReading._(
            WalmartLinkStatus.unreadable,
            null,
            null,
          );
        }
        return WalmartLinkReading._(
          WalmartLinkStatus.found,
          canonical,
          sourceRaw as String,
        );

      default:
        return const WalmartLinkReading._(
          WalmartLinkStatus.unreadable,
          null,
          null,
        );
    }
  }

  /// Whether this reading has a usable, editable Walmart link.
  bool get hasLink => status == WalmartLinkStatus.found && url != null;

  /// Canonicalizes a single raw candidate string, or returns null if it is
  /// not a strictly valid Walmart product link (per D-WALMART-001).
  ///
  /// Accepts `walmart.com` / `www.walmart.com` / `m.walmart.com`, HTTP or
  /// HTTPS or an omitted scheme, explicit default ports only (80 for HTTP,
  /// 443 for HTTPS), and a path of `/ip/<3-20 ASCII digits>` or
  /// `/ip/<slug>/<3-20 ASCII digits>` with an optional trailing slash.
  /// Query and fragment are ignored once the pre-query part parses safely.
  /// Rejects credentials, non-default ports, unrelated or extra path
  /// segments, interior whitespace, control characters, backslashes,
  /// percent signs, ellipses, scheme-relative URLs, and non-Walmart hosts.
  /// No network access; this is pure string validation.
  static String? canonicalUrl(Object? raw) {
    if (raw is! String) return null;
    if (raw.length > 2048) return null;

    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (_hasForbiddenChars(trimmed)) return null;
    if (trimmed.startsWith('//')) return null; // scheme-relative

    String rest = trimmed;
    final RegExpMatch? schemeMatch = RegExp(r'^([a-zA-Z]+)://')
        .firstMatch(trimmed);
    if (schemeMatch != null) {
      final String scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      rest = trimmed.substring(schemeMatch.end);
    }

    final int qIdx = rest.indexOf('?');
    final int fIdx = rest.indexOf('#');
    int cut = rest.length;
    if (qIdx >= 0 && qIdx < cut) cut = qIdx;
    if (fIdx >= 0 && fIdx < cut) cut = fIdx;
    final String preQuery = rest.substring(0, cut);

    if (preQuery.contains('@')) return null; // credentials

    final int slashIdx = preQuery.indexOf('/');
    if (slashIdx < 0) return null; // numeric-only or path-less input
    final String authority = preQuery.substring(0, slashIdx);
    String path = preQuery.substring(slashIdx);
    if (authority.isEmpty) return null;

    final List<String> authParts = authority.split(':');
    if (authParts.length > 2) return null;
    final String host = authParts[0].toLowerCase();
    if (authParts.length == 2) {
      final String port = authParts[1];
      if (port != '80' && port != '443') return null;
    }

    const Set<String> allowedHosts = <String>{
      'walmart.com',
      'www.walmart.com',
      'm.walmart.com',
    };
    if (!allowedHosts.contains(host)) return null;

    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    if (!path.startsWith('/ip/')) return null;
    final String afterIp = path.substring(4);
    if (afterIp.isEmpty) return null;

    final List<String> segments = afterIp.split('/');
    if (segments.length > 2) return null;
    if (segments.any((String s) => s.isEmpty)) return null;

    final RegExp digits = RegExp(r'^\d{3,20}$');
    final String idCandidate;
    if (segments.length == 1) {
      idCandidate = segments[0];
    } else {
      final String slug = segments[0];
      if (slug == '.' || slug == '..') return null;
      idCandidate = segments[1];
    }
    if (!digits.hasMatch(idCandidate)) return null;

    return 'https://www.walmart.com/ip/$idCandidate';
  }

  static bool _hasForbiddenChars(String s) {
    for (final int rune in s.runes) {
      if (rune <= 0x1F || rune == 0x7F) return true; // control characters
    }
    if (s.contains('\\')) return true;
    if (s.contains('%')) return true;
    if (s.contains('...') || s.contains('\u2026')) return true;
    if (RegExp(r'\s').hasMatch(s)) return true; // interior whitespace
    return false;
  }
}
