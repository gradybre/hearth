import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/house/ha_credentials.dart';
import 'package:hearth/data/house/ha_repository.dart';
import 'package:hearth/data/house/ha_socket.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/domain/house/ha_endpoint.dart';

/// One place that knows how to reach the house
/// (`docs/HOME_ASSISTANT_SPEC.md` §5.1, §5.2).
void main() {
  // Obviously not a real one.
  const String token = 'NOT_A_REAL_TOKEN_example_long_lived';
  const HaCredentialScope scope = HaCredentialScope(
    userId: 'user-a',
    householdId: 'house-1',
    connectionId: 'conn-1',
  );

  late HearthDatabase db;
  late PreferenceStore preferences;
  late _Vault vault;
  late _Server server;

  HaRepository repositoryFor({HaCredentialScope which = scope}) => HaRepository(
    preferences: preferences,
    credentials: HaCredentialStore(vault: vault),
    scope: which,
    opener: (Uri _) async => server.socket,
  );

  HaEndpoint endpointOf(String address, {bool plain = false}) =>
      (HaEndpoint.parse(
        address,
        allowPlainHttpOnLocalNetwork: plain,
      ) as HaEndpointAccepted).endpoint;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    preferences = PreferenceStore(db);
    vault = _Vault();
    server = _Server();
  });

  tearDown(() => db.close());

  group('a saved connection comes back', () {
    test('as the same address it went in as', () async {
      // The round trip is the thing most likely to be quietly wrong, because
      // nothing fails loudly when it is — the connection simply reports itself
      // unconfigured after a restart.
      final HaRepository repository = repositoryFor();
      await repository.save(endpointOf('https://ha.example.test'), token);

      final HaEndpoint? back = await repository.endpoint();
      expect(back, isNotNull);
      expect(back!.origin.toString(), 'https://ha.example.test');
      expect(
        back.webSocketUri.toString(),
        'wss://ha.example.test/api/websocket',
      );
    });

    test('and a proxy prefix survives exactly once', () async {
      // `restBase` already carries `/api/`. Storing that and re-parsing it
      // would put the prefix in twice and address `/ha/api/api/`.
      final HaRepository repository = repositoryFor();
      await repository.save(endpointOf('https://home.example.test/ha'), token);

      final HaEndpoint back = (await repository.endpoint())!;
      expect(back.restBase.toString(), 'https://home.example.test/ha/api/');
    });

    test('and an unencrypted local address is still readable afterwards', () async {
      // The trap: plain HTTP needs an explicit opt-in to parse, so an address
      // saved with one and re-read without it is refused — and a working local
      // connection silently becomes "not configured" on the next launch.
      final HaRepository repository = repositoryFor();
      await repository.save(
        endpointOf('http://192.168.1.10:8123', plain: true),
        token,
      );

      expect(await repository.endpoint(), isNotNull);
      expect(await repository.isConfigured, isTrue);
    });
  });

  group('nothing above it handles a token', () {
    test('there is no way to read one back', () async {
      // The reason this class exists. A feature that can read the credential
      // is a feature that can log it.
      final HaRepository repository = repositoryFor();
      await repository.save(endpointOf('https://ha.example.test'), token);

      expect(
        repository.toString(),
        isNot(contains(token)),
        reason: 'and it is not on the object either',
      );
    });

    test('and a saved token is in the keychain, not the preferences', () async {
      final HaRepository repository = repositoryFor();
      await repository.save(endpointOf('https://ha.example.test'), token);

      expect(vault.values.values, contains(token));
      final String stored = (await preferences.read(
        'house.ha.endpoint/user-a/house-1/conn-1',
      ))!;
      expect(stored, isNot(contains(token)));
    });
  });

  group('a connection belongs to one context', () {
    test('so another person on this phone has none', () async {
      await repositoryFor().save(endpointOf('https://ha.example.test'), token);

      const HaCredentialScope other = HaCredentialScope(
        userId: 'user-b',
        householdId: 'house-1',
        connectionId: 'conn-1',
      );
      expect(await repositoryFor(which: other).isConfigured, isFalse);
    });
  });

  group('disconnecting', () {
    test(
      'takes the credential first, so an unreachable Pi is no obstacle',
      () async {
        // §4.1: disconnecting must still clear local access when the Pi cannot
        // be reached. Nothing here contacts it.
        final HaRepository repository = repositoryFor();
        await repository.save(endpointOf('https://ha.example.test'), token);

        await repository.forget();

        expect(await repository.isConfigured, isFalse);
        expect(vault.values, isEmpty);
        expect(
          await preferences.read('house.ha.endpoint/user-a/house-1/conn-1'),
          isNull,
        );
      },
    );
  });

  group('probing says which thing went wrong', () {
    test('a refused token is told apart from an unreachable server', () async {
      final HaRepository repository = repositoryFor();

      server.answerWith = 'auth_invalid';
      expect(
        await repository.probe(endpointOf('https://ha.example.test'), token),
        HaProbeOutcome.refused,
      );

      server = _Server()..answerWith = 'close';
      expect(
        await repositoryFor().probe(
          endpointOf('https://ha.example.test'),
          token,
        ),
        HaProbeOutcome.unreachable,
      );
    });

    test(
      'and something that is not Home Assistant is its own answer',
      () async {
        server.answerWith = 'garbage';
        expect(
          await repositoryFor().probe(
            endpointOf('https://ha.example.test'),
            token,
          ),
          HaProbeOutcome.notHomeAssistant,
        );
      },
    );

    test('and a good one operates nothing to find out', () async {
      // §4.1: test connectivity and authentication without operating devices.
      server.answerWith = 'ok';
      expect(
        await repositoryFor().probe(
          endpointOf('https://ha.example.test'),
          token,
        ),
        HaProbeOutcome.reachable,
      );

      final Iterable<String> types = server.socket.sent.map(
        (Map<String, Object?> f) => f['type'] as String? ?? '',
      );
      expect(
        types,
        isNot(contains('call_service')),
        reason: 'nothing was switched, dimmed or asked to move',
      );
      expect(types, contains('get_states'));
    });

    test('and the socket is closed afterwards either way', () async {
      server.answerWith = 'auth_invalid';
      await repositoryFor().probe(endpointOf('https://ha.example.test'), token);
      expect(server.socket.closed, isTrue);
    });
  });

  group('connecting', () {
    test('is null when nothing is configured', () async {
      expect(await repositoryFor().connect(), isNull);
    });

    test('and null when the address is there but the token is gone', () async {
      // The half-configured case: a keychain wiped by a restore, an address
      // left behind. Reporting configured here would produce a connection
      // that can only fail authentication for ever.
      final HaRepository repository = repositoryFor();
      await repository.save(endpointOf('https://ha.example.test'), token);
      vault.values.clear();

      expect(await repository.isConfigured, isFalse);
      expect(await repository.connect(), isNull);
    });
  });
}

/// A keychain with nothing behind it.
class _Vault implements HaSecretVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map<String, String>.of(values);
}

/// A Home Assistant that answers however the test says.
class _Server {
  _Server() {
    socket = _FakeSocket(this);
  }

  late final _FakeSocket socket;

  /// `ok`, `auth_invalid`, `garbage`, or `close`.
  String answerWith = 'ok';

  void greet() {
    switch (answerWith) {
      case 'close':
        socket.serverCloses();
      case 'garbage':
        socket.serverSays(<String, Object?>{'type': 'hello_from_a_router'});
      default:
        socket.serverSays(<String, Object?>{'type': 'auth_required'});
    }
  }

  void afterAuth() {
    switch (answerWith) {
      case 'auth_invalid':
        socket.serverSays(<String, Object?>{'type': 'auth_invalid'});
      default:
        socket.serverSays(<String, Object?>{'type': 'auth_ok'});
    }
  }
}

class _FakeSocket implements HaSocket {
  _FakeSocket(this._server) {
    // Greets when a client actually listens, not when the object is built.
    // Constructing the fake in `setUp` and greeting there fired the microtask
    // before the test body could say what kind of server this was — so every
    // case got the default answer and three tests passed for the wrong reason.
    _incoming = StreamController<Map<String, Object?>>(
      onListen: () => scheduleMicrotask(_server.greet),
    );
  }

  final _Server _server;
  late final StreamController<Map<String, Object?>> _incoming;
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  bool closed = false;

  void serverSays(Map<String, Object?> frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  void serverCloses() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  @override
  void send(Map<String, Object?> frame) {
    sent.add(frame);
    switch (frame['type']) {
      case 'auth':
        scheduleMicrotask(_server.afterAuth);
      case 'subscribe_events':
        scheduleMicrotask(
          () => serverSays(<String, Object?>{
            'type': 'result',
            'id': frame['id'],
          }),
        );
      case 'get_states':
        scheduleMicrotask(
          () => serverSays(<String, Object?>{
            'type': 'result',
            'id': frame['id'],
            'result': <Object?>[],
          }),
        );
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }
}
