/// Where Hearth is willing to send a Home Assistant token
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.1).
///
/// Pure Dart, like the rest of `lib/domain/` — no Flutter, no sockets. This
/// file turns a string somebody typed into a *credential destination*, which
/// §5.1 is careful to call it: every accepted endpoint is somewhere a
/// long-lived bearer token will be posted, over and over, unattended.
///
/// So the shape of the whole file follows from one asymmetry. Refusing a good
/// address costs a person thirty seconds and a clearer error; accepting a bad
/// one hands their house keys to whoever owns that name. Wherever a string
/// leaves room for doubt, this refuses and says which doubt — §4.1 needs the
/// setup screen to tell an unsupported scheme from a TLS failure from a bad
/// address, and a nullable answer cannot.
///
/// Two rules here are easy to soften by accident and must not be:
///
///  * **Plain HTTP is a choice the caller makes, never a fallback.** Nothing
///    in this file downgrades a scheme on its own, and the opt-in is about
///    that one scheme — it is not a TLS bypass, which lives nowhere.
///  * **A name is not a network.** `evil.local.example.com` is a public host
///    with the word "local" in it. Only a literal private address, or a name
///    reserved by RFC so it *cannot* be delegated publicly, is decidable from
///    a string. Everything else is [HostLocality.undecidable]: resolution
///    happens elsewhere, later, and this type says so rather than guessing.
library;

import 'package:meta/meta.dart';

/// What the address itself can settle about where the traffic goes.
///
/// Deliberately four answers rather than a boolean. "Not decidably local" and
/// "decidably not local" are different things to say to a person, and neither
/// of them is "local".
enum HostLocality {
  /// A literal loopback, private-range or link-local IP. The string settles it:
  /// no resolver is involved and no public host can claim one.
  privateAddress,

  /// A name reserved by RFC for local use — `localhost` (RFC 6761) and the
  /// mDNS suffix `.local` (RFC 6762). Neither can be delegated in the public
  /// DNS, so the name itself is the evidence.
  reservedLocalName,

  /// A literal IP outside those ranges. Decidably *not* local.
  publicAddress,

  /// An ordinary name. It may resolve to the Pi in the next room or to a
  /// server in another country, and nothing in the string says which.
  undecidable;

  /// Whether the string alone proves the traffic stays on the local network.
  ///
  /// The only gate plain HTTP is allowed through, which is why it is a
  /// whitelist of the two decidable cases rather than "not public".
  bool get isDecidablyLocal =>
      this == privateAddress || this == reservedLocalName;

  /// Classify a host as spelled — no lookups, no arithmetic on the name.
  ///
  /// Anything this cannot read *exactly* as a dotted quad or an IPv6 literal
  /// is treated as a name, including the forms some network stacks quietly
  /// accept: `2130706433`, `0x7f.0.0.1` and `127.1` are all 127.0.0.1 to a
  /// resolver, and decoding them here would mean re-implementing one stack's
  /// quirks and then trusting the answer. Calling them undecidable refuses
  /// plain HTTP, which is the safe direction to be wrong in.
  static HostLocality of(String host) {
    final String lower = host.toLowerCase();
    if (lower.isEmpty) return undecidable;

    if (lower.contains(':')) {
      // Uri hands back IPv6 literals without their brackets, and may carry a
      // zone id (`fe80::1%25eth0`) that says nothing about locality.
      final String address = lower.split('%').first;
      return _isPrivateIpv6(address) ? privateAddress : publicAddress;
    }

    final List<int>? quad = _dottedQuad(lower);
    if (quad != null) {
      return _isPrivateIpv4(quad) ? privateAddress : publicAddress;
    }

    // A trailing dot is the DNS root and changes nothing about the name.
    final String name = lower.endsWith('.')
        ? lower.substring(0, lower.length - 1)
        : lower;
    for (final String suffix in _reservedLocalSuffixes) {
      if (name == suffix || name.endsWith('.$suffix')) return reservedLocalName;
    }
    // Everything else, including a bare label like `homeassistant`: a
    // resolver's search suffix can send that anywhere it likes.
    return undecidable;
  }

  static const List<String> _reservedLocalSuffixes = <String>[
    'localhost',
    'local',
  ];

  /// Exactly four base-ten octets, no leading zeros.
  ///
  /// Leading zeros are refused rather than parsed: `010.0.0.1` is 8.0.0.1 to
  /// anything that reads it as octal and 10.0.0.1 to anything that does not,
  /// and a private-range check that can be flipped by a zero is not a check.
  static List<int>? _dottedQuad(String host) {
    final List<String> parts = host.split('.');
    if (parts.length != 4) return null;
    final List<int> octets = <int>[];
    for (final String part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      if (part.length > 1 && part.startsWith('0')) return null;
      if (!_digits.hasMatch(part)) return null;
      final int value = int.parse(part);
      if (value > 255) return null;
      octets.add(value);
    }
    return octets;
  }

  static bool _isPrivateIpv4(List<int> o) =>
      o[0] == 10 || // 10/8
      o[0] == 127 || // loopback
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) || // 172.16/12, both edges
      (o[0] == 192 && o[1] == 168) || // 192.168/16
      (o[0] == 169 && o[1] == 254); // link-local

  static bool _isPrivateIpv6(String address) {
    if (address == '::1') return true; // loopback
    final int? first = int.tryParse(address.split(':').first, radix: 16);
    if (first == null) return false;
    if (first & 0xfe00 == 0xfc00) return true; // fc00::/7, unique local
    if (first & 0xffc0 == 0xfe80) return true; // fe80::/10, link-local
    return false;
  }

  static final RegExp _digits = RegExp(r'^[0-9]+$');
}

/// Which part of an address was carrying something it should not.
enum CredentialSite {
  /// `https://user:pass@host` — the part a person's eye skips.
  userInfo,

  /// `?access_token=…`, and every other query, because Hearth cannot tell.
  query,

  /// `#token=…`.
  fragment,
}

/// The answer to "may Hearth connect here?", with the reason attached.
///
/// Sealed rather than nullable because §4.1 requires setup to distinguish
/// address failure from TLS failure from an unsupported scheme, and a null
/// says only "no". Pattern-match it; the compiler will point at any case a new
/// refusal has not been given words for.
sealed class HaEndpointResult {
  const HaEndpointResult();
}

/// The address is one Hearth is willing to send a token to.
@immutable
final class HaEndpointAccepted extends HaEndpointResult {
  const HaEndpointAccepted(this.endpoint);

  final HaEndpoint endpoint;
}

/// The address is not. Every subtype names a different thing to tell the user.
sealed class HaEndpointRefused extends HaEndpointResult {
  const HaEndpointRefused();
}

/// Nothing was typed.
final class HaBlankAddress extends HaEndpointRefused {
  const HaBlankAddress();
}

/// Not an address at all, or one whose meaning depends on who parses it.
final class HaMalformedAddress extends HaEndpointRefused {
  const HaMalformedAddress();
}

/// An address with no `http://` or `https://` in front of it.
///
/// Separate from [HaMalformedAddress] because the fix is specific and the
/// alternative is worse: picking a scheme for the user means either inventing
/// a TLS requirement the Pi cannot meet, or silently dropping encryption they
/// never chose to drop.
final class HaMissingScheme extends HaEndpointRefused {
  const HaMissingScheme();
}

/// A scheme Hearth will not speak, named so the screen can say which.
final class HaUnsupportedScheme extends HaEndpointRefused {
  const HaUnsupportedScheme(this.scheme);

  /// Exactly as typed, lower-cased by the URI parser.
  final String scheme;
}

/// The address carries something secret-shaped.
final class HaCredentialsInAddress extends HaEndpointRefused {
  const HaCredentialsInAddress(this.site);

  final CredentialSite site;
}

/// A scheme and a path, but nowhere to send them.
final class HaMissingHost extends HaEndpointRefused {
  const HaMissingHost();
}

/// Plain HTTP, and nobody has said this is a local-network connection.
///
/// Carries the locality so the screen can explain what agreeing would mean:
/// the offer only makes sense at all when the address is decidably local.
final class HaPlainHttpNotChosen extends HaEndpointRefused {
  const HaPlainHttpNotChosen(this.locality);

  final HostLocality locality;
}

/// Plain HTTP was chosen, but this address is not one the string proves local.
///
/// The refusal `evil.local.example.com` exists for: an unencrypted request to
/// a public host puts the token on the wire in clear, and "local" in a name is
/// not a network.
final class HaPlainHttpNotLocal extends HaEndpointRefused {
  const HaPlainHttpNotLocal(this.locality);

  final HostLocality locality;
}

/// One validated Home Assistant address, and the URLs derived from it.
///
/// There is no public constructor: an endpoint exists only because
/// [HaEndpoint.parse] accepted it, so holding one is proof that every §5.1
/// check has run. That is what lets the transport layer put a bearer token on
/// a request without re-deciding whether it should.
@immutable
class HaEndpoint {
  const HaEndpoint._({
    required this.origin,
    required this.pathPrefix,
    required this.locality,
  });

  /// Validate a typed address, per §5.1.
  ///
  /// [allowPlainHttpOnLocalNetwork] is the explicit local-network choice, and
  /// nothing else: it never relaxes certificate validation (which is not this
  /// layer's business), and it never makes a non-local address acceptable over
  /// plain HTTP. Default false, so a caller that forgets it gets a refusal
  /// rather than an unencrypted connection.
  static HaEndpointResult parse(
    String? address, {
    bool allowPlainHttpOnLocalNetwork = false,
  }) {
    if (address == null) return const HaBlankAddress();
    // A pasted address usually arrives with a newline or a space around it.
    // That is a typing artefact; whitespace *inside* is an ambiguity.
    final String trimmed = address.trim();
    if (trimmed.isEmpty) return const HaBlankAddress();
    // Backslashes and inner whitespace are where parsers disagree: Dart reads
    // `https://ha.example.com\@evil.com` as ha.example.com with a silly path,
    // while browser-rule parsers read the backslash as a separator. An address
    // whose host depends on whose parser reads it is not one to send a token to.
    if (_ambiguous.hasMatch(trimmed)) return const HaMalformedAddress();

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      // `192.168.1.10:8123` throws because a scheme cannot start with a digit,
      // and "add http:// or https://" is the useful thing to say about it.
      return _schemePrefix.hasMatch(trimmed)
          ? const HaMalformedAddress()
          : const HaMissingScheme();
    }

    if (uri.scheme.isEmpty) return const HaMissingScheme();
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      // Including `ws`/`wss`: the socket address is derived from this one, and
      // accepting it here would let the two halves be configured apart.
      return HaUnsupportedScheme(uri.scheme);
    }
    if (uri.userInfo.isNotEmpty) {
      return const HaCredentialsInAddress(CredentialSite.userInfo);
    }
    // Any query, not a blocklist of parameter names. A base URL needs none,
    // and a blocklist only ever knows the token names somebody thought of.
    if (uri.query.isNotEmpty) {
      return const HaCredentialsInAddress(CredentialSite.query);
    }
    if (uri.fragment.isNotEmpty) {
      return const HaCredentialsInAddress(CredentialSite.fragment);
    }
    if (uri.host.isEmpty) return const HaMissingHost();
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return const HaMalformedAddress();
    }

    final HostLocality locality = HostLocality.of(uri.host);
    if (uri.scheme == 'http') {
      if (!allowPlainHttpOnLocalNetwork) return HaPlainHttpNotChosen(locality);
      if (!locality.isDecidablyLocal) return HaPlainHttpNotLocal(locality);
    }

    return HaEndpointAccepted(
      HaEndpoint._(
        // Rebuilt from parts rather than edited as a string: this is what
        // lower-cases the host, drops a default port and leaves nothing of the
        // original text in the address a request is aimed at.
        origin: Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
        ),
        pathPrefix: _prefixOf(uri),
        locality: locality,
      ),
    );
  }

  /// Scheme, host and non-default port. No path, no credentials, nothing else.
  final Uri origin;

  /// The reverse-proxy prefix, `''` at the root and `/ha` under one.
  ///
  /// Preserved rather than discarded (§5.1): Home Assistant is conventionally
  /// at the origin root, but behind a proxy every request that drops the
  /// prefix lands on the proxy's own front page instead — which answers, with
  /// something that is not Home Assistant.
  final String pathPrefix;

  /// What the address itself settles about where this is. Never a promise that
  /// the host resolves anywhere in particular.
  final HostLocality locality;

  bool get usesTls => origin.scheme == 'https';

  bool get isDecidablyLocal => locality.isDecidablyLocal;

  /// The REST API root, with a trailing slash so [Uri.resolve] works.
  ///
  /// The slash is load-bearing: `resolve` on a path with no trailing slash
  /// replaces the last segment, so `/ha/api` + `states` would address
  /// `/ha/states`, which is the proxy again and not the API.
  Uri get restBase => origin.replace(path: '$pathPrefix/api/');

  /// The WebSocket API, derived from the same origin and prefix.
  ///
  /// Derived rather than configured so the two halves of a connection cannot
  /// disagree about which server they are talking to (§5.1, §6.1).
  Uri get webSocketUri => Uri(
    scheme: usesTls ? 'wss' : 'ws',
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '$pathPrefix/api/websocket',
  );

  /// Where a person's browser should go for §7's "Open in Home Assistant".
  ///
  /// Carries no token by design — that fallback relies on the browser's own
  /// Home Assistant session, and a link with a token in it is a token in a
  /// history file.
  Uri get browserRoot => origin.replace(path: '$pathPrefix/');

  /// Collapse a path to a tidy prefix, keeping which server it means.
  ///
  /// `normalizePath` resolves `..` before anything is kept, so a prefix cannot
  /// be written as a walk out of itself.
  static String _prefixOf(Uri uri) {
    final List<String> segments = uri
        .normalizePath()
        .path
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? '' : '/${segments.join('/')}';
  }

  /// Whitespace anywhere inside, or a backslash anywhere at all.
  static final RegExp _ambiguous = RegExp(r'[\s\\]');

  /// `scheme:` at the start — enough to tell "unparseable" from "no scheme".
  static final RegExp _schemePrefix = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*:');

  @override
  bool operator ==(Object other) =>
      other is HaEndpoint &&
      other.origin == origin &&
      other.pathPrefix == pathPrefix;

  @override
  int get hashCode => Object.hash(origin, pathPrefix);

  @override
  String toString() => browserRoot.toString();
}

/// The two ways into one house (§5.1).
///
/// An optional alternate address for the **same** Home Assistant instance —
/// typically the local one and a remote one. This type does not and cannot
/// check that they are the same server: §5.1 is explicit that a matching
/// location name proves nothing about identity, so that belongs to the
/// connection check, against the server's own answer.
@immutable
class HaEndpointPair {
  const HaEndpointPair({required this.primary, this.alternate});

  final HaEndpoint primary;

  /// Null when the user configured only one address, which is the common case.
  final HaEndpoint? alternate;

  /// Where to try, in order: the local address first (§5.1).
  ///
  /// Local-first because it is the one that works when the internet is down
  /// and the one that does not leave the house. Only a decidably local
  /// endpoint is promoted — an undecidable name might be either, and
  /// reordering on a guess would send the first attempt over the internet
  /// while claiming to prefer the LAN.
  List<HaEndpoint> get attemptOrder {
    final HaEndpoint? other = alternate;
    // One server spelled twice is one attempt, not two.
    if (other == null || other == primary) return <HaEndpoint>[primary];
    if (other.isDecidablyLocal && !primary.isDecidablyLocal) {
      return <HaEndpoint>[other, primary];
    }
    return <HaEndpoint>[primary, other];
  }

  @override
  bool operator ==(Object other) =>
      other is HaEndpointPair &&
      other.primary == primary &&
      other.alternate == alternate;

  @override
  int get hashCode => Object.hash(primary, alternate);
}
