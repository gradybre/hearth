import 'package:hearth/domain/house/ha_endpoint.dart';
import 'package:test/test.dart';

/// Where a bearer token is allowed to go
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.1).
///
/// The adversarial cases come first on purpose. A bug in the pretty-printing
/// of a URL is a cosmetic defect; a bug in the refusals is a long-lived Home
/// Assistant token posted to somebody else's server. So every test below that
/// begins "is refused" is really asserting the same thing: Hearth would rather
/// fail setup than guess a credential destination.
void main() {
  group('an address that could send the token somewhere else is refused', () {
    test('user-info, because the host is not where the eye lands', () {
      // `https://ha.example.com@evil.com` reads as the household server and
      // resolves to evil.com. Refusing the whole shape is the only reading
      // that is safe, since the two cases are indistinguishable to a person.
      expect(
        HaEndpoint.parse('https://user:pass@ha.example.com'),
        isA<HaCredentialsInAddress>().having(
          (HaCredentialsInAddress r) => r.site,
          'site',
          CredentialSite.userInfo,
        ),
      );
      expect(
        HaEndpoint.parse('https://ha.example.com@evil.com'),
        isA<HaCredentialsInAddress>(),
      );
      expect(
        HaEndpoint.parse('https://token@ha.example.com:8123'),
        isA<HaCredentialsInAddress>(),
      );
    });

    test('and a query, which is where a pasted token usually hides', () {
      expect(
        HaEndpoint.parse('https://ha.example.com/?access_token=abc123'),
        isA<HaCredentialsInAddress>().having(
          (HaCredentialsInAddress r) => r.site,
          'site',
          CredentialSite.query,
        ),
      );
      // Not a blocklist of parameter names: any query at all. A base URL needs
      // none, and Hearth cannot tell a secret from a harmless flag.
      expect(
        HaEndpoint.parse('https://ha.example.com/?theme=dark'),
        isA<HaCredentialsInAddress>(),
      );
    });

    test('and a fragment, for the same reason', () {
      expect(
        HaEndpoint.parse('https://ha.example.com/#token=abc123'),
        isA<HaCredentialsInAddress>().having(
          (HaCredentialsInAddress r) => r.site,
          'site',
          CredentialSite.fragment,
        ),
      );
    });

    test('and a backslash, which different parsers disagree about', () {
      // Dart reads the host as ha.example.com here; a browser or another HTTP
      // stack may not. An address whose meaning depends on whose parser reads
      // it is not an address Hearth will send a token to.
      expect(
        HaEndpoint.parse(r'https://ha.example.com\@evil.com'),
        isA<HaMalformedAddress>(),
      );
    });

    test('and any scheme that is not http or https', () {
      for (final String address in <String>[
        'ftp://ha.example.com',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,hello',
      ]) {
        expect(
          HaEndpoint.parse(address),
          isA<HaUnsupportedScheme>(),
          reason: '$address must not become a credential destination',
        );
      }
      // Named back, because §4.1 wants the screen to say which scheme.
      expect(
        HaEndpoint.parse('ftp://ha.example.com'),
        isA<HaUnsupportedScheme>().having(
          (HaUnsupportedScheme r) => r.scheme,
          'scheme',
          'ftp',
        ),
      );
    });

    test('including the websocket schemes, which Hearth derives itself', () {
      // Accepting `wss://` here would let the two halves of the connection be
      // configured apart. The websocket address comes from the HTTP one.
      expect(
        HaEndpoint.parse('wss://ha.example.com'),
        isA<HaUnsupportedScheme>(),
      );
      expect(
        HaEndpoint.parse('ws://192.168.1.10:8123'),
        isA<HaUnsupportedScheme>(),
      );
    });

    test('and an address with no scheme at all, rather than guessing one', () {
      // Guessing https gives a confusing TLS failure on a local Pi; guessing
      // http silently drops the encryption the user never opted out of.
      expect(HaEndpoint.parse('192.168.1.10:8123'), isA<HaMissingScheme>());
      expect(HaEndpoint.parse('homeassistant.local'), isA<HaMissingScheme>());
      expect(HaEndpoint.parse('//ha.example.com'), isA<HaMissingScheme>());
    });

    test('and nothing at all', () {
      expect(HaEndpoint.parse(null), isA<HaBlankAddress>());
      expect(HaEndpoint.parse(''), isA<HaBlankAddress>());
      expect(HaEndpoint.parse('   '), isA<HaBlankAddress>());
    });

    test('and an address with no host to reach', () {
      expect(HaEndpoint.parse('https://'), isA<HaMissingHost>());
      expect(HaEndpoint.parse('https:///api/'), isA<HaMissingHost>());
    });

    test('and a port that is not a port', () {
      expect(
        HaEndpoint.parse('https://ha.example.com:0'),
        isA<HaMalformedAddress>(),
      );
      expect(
        HaEndpoint.parse('https://ha.example.com:99999'),
        isA<HaMalformedAddress>(),
      );
      expect(
        HaEndpoint.parse('https://ha.example.com:-1'),
        isA<HaMalformedAddress>(),
      );
    });

    test('and whitespace inside it, though the ends are tidied', () {
      expect(
        HaEndpoint.parse('https://ha.example .com'),
        isA<HaMalformedAddress>(),
      );
      // A pasted address usually arrives with a trailing newline or space.
      // That is a typing artefact, not an ambiguity.
      expect(
        HaEndpoint.parse('  https://ha.example.com\n'),
        isA<HaEndpointAccepted>(),
      );
    });
  });

  group('plain HTTP is a choice the caller makes, never a fallback', () {
    test('an unencrypted address is refused until someone says so', () {
      final HaEndpointResult result = HaEndpoint.parse(
        'http://192.168.1.10:8123',
      );
      expect(
        result,
        isA<HaPlainHttpNotChosen>(),
        reason: 'the type must never downgrade on its own',
      );
      expect(
        (result as HaPlainHttpNotChosen).locality,
        HostLocality.privateAddress,
        reason: 'the screen has to explain what the choice would mean',
      );
    });

    test('and accepted when they do, on an address the string settles', () {
      final HaEndpointResult result = HaEndpoint.parse(
        'http://192.168.1.10:8123',
        allowPlainHttpOnLocalNetwork: true,
      );
      expect(result, isA<HaEndpointAccepted>());
      final HaEndpoint endpoint = (result as HaEndpointAccepted).endpoint;
      expect(endpoint.usesTls, isFalse);
      expect(endpoint.isDecidablyLocal, isTrue);
      expect(endpoint.webSocketUri.scheme, 'ws');
    });

    test('but that choice does not reach a host merely named "local"', () {
      // The case this whole file exists for. `evil.local.example.com` is an
      // ordinary public name that happens to contain the word, and saying yes
      // to unencrypted local traffic must not say yes to it.
      final HaEndpointResult result = HaEndpoint.parse(
        'http://evil.local.example.com',
        allowPlainHttpOnLocalNetwork: true,
      );
      expect(result, isA<HaPlainHttpNotLocal>());
      expect(
        (result as HaPlainHttpNotLocal).locality,
        HostLocality.undecidable,
      );
    });

    test('nor a public address, however explicit the caller was', () {
      expect(
        HaEndpoint.parse(
          'http://203.0.113.9',
          allowPlainHttpOnLocalNetwork: true,
        ),
        isA<HaPlainHttpNotLocal>().having(
          (HaPlainHttpNotLocal r) => r.locality,
          'locality',
          HostLocality.publicAddress,
        ),
      );
      expect(
        HaEndpoint.parse(
          'http://ha.example.com',
          allowPlainHttpOnLocalNetwork: true,
        ),
        isA<HaPlainHttpNotLocal>(),
      );
    });

    test('nor an address that only a resolver could turn into a local one', () {
      // 2130706433 and 0x7f.0.0.1 are both 127.0.0.1 to some network stacks.
      // Hearth does not do that arithmetic: an address it cannot read as a
      // dotted quad is a name, and a name is undecidable.
      for (final String host in <String>['2130706433', '0x7f.0.0.1', '127.1']) {
        expect(
          HaEndpoint.parse(
            'http://$host:8123',
            allowPlainHttpOnLocalNetwork: true,
          ),
          isA<HaPlainHttpNotLocal>(),
          reason: '$host must not be decoded into a local address',
        );
      }
    });

    test('and saying so does not weaken HTTPS anywhere', () {
      // No blanket TLS bypass: the flag is about one scheme, not about
      // certificate validation, which happens in the transport layer.
      final HaEndpointResult result = HaEndpoint.parse(
        'https://ha.example.com',
        allowPlainHttpOnLocalNetwork: true,
      );
      expect(result, isA<HaEndpointAccepted>());
      expect((result as HaEndpointAccepted).endpoint.usesTls, isTrue);
    });

    test('a remote endpoint is therefore always HTTPS', () {
      // §5.1 stated the other way round, and worth asserting as stated: there
      // is no accepted endpoint that is both unencrypted and not local.
      for (final bool allow in <bool>[false, true]) {
        final HaEndpointResult result = HaEndpoint.parse(
          'http://ha.duckdns.org:8123',
          allowPlainHttpOnLocalNetwork: allow,
        );
        expect(result, isA<HaEndpointRefused>(), reason: 'allow=$allow');
      }
    });
  });

  group('locality is only ever what the string can settle', () {
    test('a literal private or loopback address is decidable', () {
      for (final String host in <String>[
        '192.168.1.10',
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.254',
        '127.0.0.1',
        '169.254.10.1',
      ]) {
        expect(
          HostLocality.of(host),
          HostLocality.privateAddress,
          reason: '$host is inside a private range',
        );
      }
      for (final String host in <String>['::1', 'fd12:3456::1', 'fe80::1']) {
        expect(
          HostLocality.of(host),
          HostLocality.privateAddress,
          reason: host,
        );
      }
    });

    test('and the edges of those ranges are not waved through', () {
      // 172.16/12 is the range that gets implemented as "172.16 to 172.32"
      // by eye. Both neighbours are ordinary public addresses.
      expect(HostLocality.of('172.15.255.255'), HostLocality.publicAddress);
      expect(HostLocality.of('172.32.0.1'), HostLocality.publicAddress);
      expect(HostLocality.of('11.0.0.1'), HostLocality.publicAddress);
      expect(HostLocality.of('192.169.1.1'), HostLocality.publicAddress);
      expect(HostLocality.of('8.8.8.8'), HostLocality.publicAddress);
      expect(HostLocality.of('2606:4700::1111'), HostLocality.publicAddress);
    });

    test('and a name reserved by RFC cannot be a public host', () {
      // `.local` is mDNS (RFC 6762) and `localhost` is loopback (RFC 6761).
      // Neither can be delegated publicly, so the string really does settle it.
      expect(
        HostLocality.of('homeassistant.local'),
        HostLocality.reservedLocalName,
      );
      expect(
        HostLocality.of('HOMEASSISTANT.LOCAL'),
        HostLocality.reservedLocalName,
      );
      expect(
        HostLocality.of('homeassistant.local.'),
        HostLocality.reservedLocalName,
      );
      expect(HostLocality.of('localhost'), HostLocality.reservedLocalName);
    });

    test('but a name that merely contains the word settles nothing', () {
      for (final String host in <String>[
        'evil.local.example.com',
        'local.example.com',
        'localhost.evil.com',
        'my-local-server.com',
        'notlocal',
        'ha.example.com',
        // A bare label reaches wherever the resolver's search suffix points.
        'homeassistant',
      ]) {
        expect(
          HostLocality.of(host),
          HostLocality.undecidable,
          reason: '$host is not decidably local',
        );
      }
    });

    test('and a leading zero makes an octet ambiguous, so it decides nothing', () {
      // `010.0.0.1` is 10.0.0.1 read as decimal and 8.0.0.1 read as octal, and
      // different stacks read it differently. A private-range check a zero can
      // flip is not a check.
      expect(HostLocality.of('010.0.0.1'), HostLocality.undecidable);
      expect(HostLocality.of('192.168.01.1'), HostLocality.undecidable);
      expect(HostLocality.of('192.168.1.256'), HostLocality.undecidable);
      expect(HostLocality.of('192.168.1'), HostLocality.undecidable);
    });

    test('and an IPv6 zone id does not disturb the classification', () {
      // Uri keeps the zone (`fe80::1%25eth0`); it names an interface, not a
      // network, and the prefix in front of it is what decides.
      expect(HostLocality.of('fe80::1%25eth0'), HostLocality.privateAddress);
      expect(
        HaEndpoint.parse(
          'http://[fe80::1%25eth0]:8123',
          allowPlainHttpOnLocalNetwork: true,
        ),
        isA<HaEndpointAccepted>(),
      );
    });

    test('and undecidable means undecidable, not "probably fine"', () {
      expect(HostLocality.undecidable.isDecidablyLocal, isFalse);
      expect(HostLocality.publicAddress.isDecidablyLocal, isFalse);
      expect(HostLocality.privateAddress.isDecidablyLocal, isTrue);
      expect(HostLocality.reservedLocalName.isDecidablyLocal, isTrue);
    });
  });

  group('an accepted endpoint says exactly where to connect', () {
    HaEndpoint accept(String address, {bool allowPlainHttp = false}) {
      final HaEndpointResult result = HaEndpoint.parse(
        address,
        allowPlainHttpOnLocalNetwork: allowPlainHttp,
      );
      expect(result, isA<HaEndpointAccepted>(), reason: 'parsing $address');
      return (result as HaEndpointAccepted).endpoint;
    }

    test('normalized by the URI APIs rather than by string surgery', () {
      final HaEndpoint endpoint = accept('HTTPS://HA.Example.COM:443/');
      expect(endpoint.origin.toString(), 'https://ha.example.com');
      expect(endpoint.restBase.toString(), 'https://ha.example.com/api/');
      expect(
        endpoint.webSocketUri.toString(),
        'wss://ha.example.com/api/websocket',
      );
    });

    test('keeping a port that is not the scheme default', () {
      final HaEndpoint endpoint = accept('https://ha.example.com:8123');
      expect(endpoint.origin.toString(), 'https://ha.example.com:8123');
      expect(endpoint.webSocketUri.port, 8123);
      // ...and dropping one that is.
      expect(
        accept(
          'http://192.168.1.10:80',
          allowPlainHttp: true,
        ).origin.toString(),
        'http://192.168.1.10',
      );
    });

    test('and preserving a reverse proxy prefix instead of discarding it', () {
      // Home Assistant is conventionally at the root, but a proxy can put it
      // under a prefix, and dropping it points every request at the proxy's
      // own front page.
      final HaEndpoint endpoint = accept('https://home.example.com/ha/');
      expect(endpoint.pathPrefix, '/ha');
      expect(endpoint.restBase.toString(), 'https://home.example.com/ha/api/');
      expect(
        endpoint.webSocketUri.toString(),
        'wss://home.example.com/ha/api/websocket',
      );
    });

    test('tidying a prefix without changing which server it means', () {
      expect(accept('https://ha.example.com').pathPrefix, '');
      expect(accept('https://ha.example.com/').pathPrefix, '');
      expect(
        accept('https://ha.example.com/ha//nested///').pathPrefix,
        '/ha/nested',
      );
      expect(accept('https://ha.example.com/a/b/../c').pathPrefix, '/a/c');
    });

    test('so the two halves of the connection cannot disagree', () {
      // One typed address, one server. Deriving the socket address from the
      // HTTP one is what makes that true by construction.
      final HaEndpoint endpoint = accept('https://home.example.com:8123/ha');
      expect(endpoint.webSocketUri.host, endpoint.restBase.host);
      expect(endpoint.webSocketUri.port, endpoint.restBase.port);
      expect(endpoint.webSocketUri.scheme, 'wss');
      expect(endpoint.webSocketUri.path, '/ha/api/websocket');
      expect(endpoint.restBase.path, '/ha/api/');
    });

    test('and the REST base resolves relative paths without losing the prefix', () {
      // The trailing slash is load-bearing: without it `resolve` would eat the
      // last segment and address `/ha/states`, which is not Home Assistant.
      final HaEndpoint endpoint = accept('https://home.example.com/ha');
      expect(
        endpoint.restBase.resolve('states').toString(),
        'https://home.example.com/ha/api/states',
      );
      expect(
        endpoint.restBase.resolve('config').toString(),
        'https://home.example.com/ha/api/config',
      );
    });

    test('and offers the root a person can open in a browser', () {
      // §7's "Open in Home Assistant" fallback, which must carry no token and
      // must respect the same prefix.
      expect(
        accept('https://home.example.com/ha').browserRoot.toString(),
        'https://home.example.com/ha/',
      );
      expect(
        accept('https://ha.example.com').browserRoot.toString(),
        'https://ha.example.com/',
      );
    });

    test('and two spellings of one server are one endpoint', () {
      expect(
        accept('https://ha.example.com:443/'),
        accept('HTTPS://HA.EXAMPLE.COM/'),
      );
      expect(
        accept('https://ha.example.com:443/').hashCode,
        accept('HTTPS://HA.EXAMPLE.COM/').hashCode,
      );
      expect(
        accept('https://ha.example.com/ha'),
        isNot(accept('https://ha.example.com')),
      );
      expect(
        accept('https://ha.example.com:8123'),
        isNot(accept('https://ha.example.com')),
      );
    });
  });

  group('a pair is two ways to the same house', () {
    HaEndpoint accept(String address, {bool allowPlainHttp = false}) {
      final HaEndpointResult result = HaEndpoint.parse(
        address,
        allowPlainHttpOnLocalNetwork: allowPlainHttp,
      );
      expect(result, isA<HaEndpointAccepted>(), reason: 'parsing $address');
      return (result as HaEndpointAccepted).endpoint;
    }

    test('and the local one is tried first', () {
      final HaEndpoint remote = accept('https://home.duckdns.org');
      final HaEndpoint local = accept(
        'http://192.168.1.10:8123',
        allowPlainHttp: true,
      );
      expect(
        HaEndpointPair(primary: remote, alternate: local).attemptOrder,
        <HaEndpoint>[local, remote],
        reason: '§5.1 prefers the local endpoint before the remote one',
      );
      expect(
        HaEndpointPair(primary: local, alternate: remote).attemptOrder,
        <HaEndpoint>[local, remote],
      );
    });

    test('and with no alternate there is only one place to try', () {
      final HaEndpoint only = accept('https://home.duckdns.org');
      expect(HaEndpointPair(primary: only).attemptOrder, <HaEndpoint>[only]);
    });

    test('and one server spelled twice is not two attempts', () {
      final HaEndpoint primary = accept('https://ha.example.com');
      final HaEndpoint alternate = accept('HTTPS://HA.Example.com:443/');
      expect(
        HaEndpointPair(primary: primary, alternate: alternate).attemptOrder,
        <HaEndpoint>[primary],
      );
    });

    test('and neither being local leaves the order the user configured', () {
      final HaEndpoint primary = accept('https://home.duckdns.org');
      final HaEndpoint alternate = accept('https://ha.example.com');
      expect(
        HaEndpointPair(primary: primary, alternate: alternate).attemptOrder,
        <HaEndpoint>[primary, alternate],
      );
    });
  });
}
