import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/house/ha_session.dart';
import 'package:hearth/data/house/ha_socket.dart';
import 'package:hearth/domain/house/entity_id.dart';
import 'package:hearth/domain/house/entity_state.dart';

/// The handshake and the race (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
void main() {
  // Obviously not a real one.
  const String token = 'NOT_A_REAL_TOKEN_example';

  late _FakeSocket socket;

  Future<HaSocket> opener(Uri url) async => socket;

  Future<HaSession> connect({String withToken = token}) {
    socket = _FakeSocket();
    final Future<HaSession> opening = HaSession.open(
      url: Uri.parse('wss://ha.example.test/api/websocket'),
      token: withToken,
      opener: opener,
      generation: 1,
    );
    socket.serverSays(<String, Object?>{'type': 'auth_required'});
    return opening;
  }

  Map<String, Object?> stateRow(
    String id,
    String state, {
    String? at,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => <String, Object?>{
    'entity_id': id,
    'state': state,
    'attributes': attributes,
    'last_changed': at,
    'last_updated': at,
  };

  Map<String, Object?> changeEvent(
    String id,
    String state, {
    String? at,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => <String, Object?>{
    'type': 'event',
    'event': <String, Object?>{
      'event_type': 'state_changed',
      'data': <String, Object?>{
        'entity_id': id,
        'new_state': stateRow(id, state, at: at, attributes: attributes),
      },
    },
  };

  group('the handshake', () {
    test('answers the challenge and comes up', () async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      expect(socket.sent.single, <String, Object?>{
        'type': 'auth',
        'access_token': token,
      });
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      expect(await opening, isA<HaSession>());
    });

    test('a refused token is not worth retrying', () async {
      // §6.1: invalid credentials halt retry. Nothing about waiting makes a
      // wrong token right, and hammering gets a client banned on some setups.
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_invalid'});

      await expectLater(
        opening,
        throwsA(
          isA<HaSessionException>()
              .having(
                (HaSessionException e) => e.failure,
                'failure',
                HaSessionFailure.credentialsRejected,
              )
              .having(
                (HaSessionException e) => e.isRetryable,
                'retryable',
                isFalse,
              ),
        ),
      );
      expect(
        socket.closed,
        isTrue,
        reason: 'a refused socket is not left open',
      );
    });

    test('and a socket that dies mid-handshake fails at once', () async {
      // Not eventually. Before this was held, a close during the handshake
      // left the attempt waiting for the fifteen-second timeout — which on a
      // phone is fifteen seconds of spinner for a Pi that is switched off.
      // The suite still passed, because it asserted the throw and not the
      // speed, so the regression was invisible until a repository test took
      // exactly fifteen seconds.
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverCloses();

      await expectLater(
        opening.timeout(const Duration(seconds: 1)),
        throwsA(isA<HaSessionException>()),
      );
    });

    test('and a lost connection is', () async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverCloses();

      await expectLater(
        opening,
        throwsA(
          isA<HaSessionException>().having(
            (HaSessionException e) => e.isRetryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    });

    test('and something that is not Home Assistant is refused', () async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'hello_from_something_else'});

      await expectLater(
        opening,
        throwsA(
          isA<HaSessionException>().having(
            (HaSessionException e) => e.failure,
            'failure',
            HaSessionFailure.unsupportedServer,
          ),
        ),
      );
    });

    test('and the token is not kept on the session afterwards', () async {
      // Nothing to redact later if there is nothing there. The session's
      // `toString` is the thing most likely to reach a log.
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      final HaSession session = await opening;
      expect(session.toString(), isNot(contains(token)));
    });
  });

  group('the snapshot and the subscription', () {
    late HaSession session;

    setUp(() async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      session = await opening;
      socket.sent.clear();
    });

    test('subscribes before it asks for the world', () async {
      // The order is the whole point. Snapshot first and any change arriving
      // before the subscription is live is lost — the door reads Closed until
      // somebody opens it again, which could be tomorrow.
      unawaited(session.bootstrap());
      await pumpEventQueue();

      expect(socket.sent.first['type'], 'subscribe_events');
      expect(socket.sent.first['event_type'], 'state_changed');
    });

    test('and an event arriving mid-fetch is not lost', () async {
      // The race itself. The door opens after the subscription is live but
      // before `get_states` comes back.
      final Future<Map<EntityId, EntityState>> booting = session.bootstrap();
      await pumpEventQueue();
      socket.answer(1, <String, Object?>{});

      socket.serverSays(
        changeEvent(
          'binary_sensor.front_door',
          'on',
          at: '2026-01-15T12:00:05Z',
        ),
      );
      await pumpEventQueue();

      socket.answer(2, <String, Object?>{
        'result': <Object?>[
          stateRow(
            'binary_sensor.front_door',
            'off',
            at: '2026-01-15T12:00:00Z',
          ),
        ],
      });

      final Map<EntityId, EntityState> world = await booting;
      expect(
        world[EntityId.tryParse('binary_sensor.front_door')]!.value,
        'on',
        reason: 'the door opened during the fetch and the snapshot is older',
      );
    });

    test('but a stale one does not move a value backwards', () async {
      // `get_states` is a live read, not a frozen one. An event buffered
      // during the fetch may already be reflected in what came back, and
      // replaying it blindly would undo a fresher reading.
      final Future<Map<EntityId, EntityState>> booting = session.bootstrap();
      await pumpEventQueue();
      socket.answer(1, <String, Object?>{});

      socket.serverSays(
        changeEvent(
          'binary_sensor.front_door',
          'off',
          at: '2026-01-15T12:00:00Z',
        ),
      );
      await pumpEventQueue();

      socket.answer(2, <String, Object?>{
        'result': <Object?>[
          stateRow(
            'binary_sensor.front_door',
            'on',
            at: '2026-01-15T12:00:05Z',
          ),
        ],
      });

      final Map<EntityId, EntityState> world = await booting;
      expect(
        world[EntityId.tryParse('binary_sensor.front_door')]!.value,
        'on',
        reason: 'the buffered event predates the snapshot and must not win',
      );
    });

    test('and events after the drain arrive live', () async {
      final Future<Map<EntityId, EntityState>> booting = session.bootstrap();
      await pumpEventQueue();
      socket.answer(1, <String, Object?>{});
      socket.answer(2, <String, Object?>{'result': <Object?>[]});
      await booting;

      final Future<HaStateChange> next = session.changes.first;
      socket.serverSays(changeEvent('light.kitchen', 'on'));
      expect((await next).entity.value, 'light.kitchen');
    });

    test('and a malformed row costs a row, not the bootstrap', () async {
      final Future<Map<EntityId, EntityState>> booting = session.bootstrap();
      await pumpEventQueue();
      socket.answer(1, <String, Object?>{});
      socket.answer(2, <String, Object?>{
        'result': <Object?>[
          'not a row',
          <String, Object?>{'entity_id': 'switch.'},
          <String, Object?>{'no_entity_id_at_all': true},
          stateRow('light.kitchen', 'on'),
        ],
      });

      final Map<EntityId, EntityState> world = await booting;
      expect(world.keys.single.value, 'light.kitchen');
    });
  });

  group('the request ledger', () {
    late HaSession session;

    setUp(() async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      session = await opening;
      socket.sent.clear();
    });

    test('answers go to the request that asked', () async {
      final Future<Map<String, Object?>> first = session.request(
        <String, Object?>{'type': 'a'},
      );
      final Future<Map<String, Object?>> second = session.request(
        <String, Object?>{'type': 'b'},
      );

      // Answered out of order, which a real server will do.
      socket.answer(2, <String, Object?>{'result': 'second'});
      socket.answer(1, <String, Object?>{'result': 'first'});

      expect((await first)['result'], 'first');
      expect((await second)['result'], 'second');
    });

    test(
      'and a closed connection does not leave one waiting for ever',
      () async {
        // A screen waiting for ever is worse than one told.
        final Future<Map<String, Object?>> pending = session.request(
          <String, Object?>{'type': 'a'},
        );
        socket.serverCloses();
        await expectLater(pending, throwsA(isA<HaSessionException>()));
      },
    );

    test('and an unknown frame type is survived, not fatal', () async {
      // Home Assistant adds frame types. A client that dies on one is a
      // client that dies on an upgrade.
      socket.serverSays(<String, Object?>{'type': 'something_new'});
      await pumpEventQueue();

      final Future<Map<String, Object?>> ok = session.request(<String, Object?>{
        'type': 'a',
      });
      socket.answer(1, <String, Object?>{'result': 'still here'});
      expect((await ok)['result'], 'still here');
    });
  });

  group('a superseded session', () {
    test('carries its own generation, so a caller can tell', () async {
      // Reconnecting makes a new session rather than reviving the old one,
      // which is what keeps the generation guard from being subtle.
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      final HaSession first = await opening;

      final Future<HaSession> reopening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      final HaSession second = await reopening;

      expect(first.generation, 1);
      expect(second.generation, 1);
      expect(identical(first, second), isFalse);
    });

    test('and closing it stops its stream rather than leaking one', () async {
      final Future<HaSession> opening = connect();
      await pumpEventQueue();
      socket.serverSays(<String, Object?>{'type': 'auth_ok'});
      final HaSession session = await opening;

      bool done = false;
      session.changes.listen(null, onDone: () => done = true);
      await session.close();
      await pumpEventQueue();

      expect(done, isTrue);
      expect(socket.closed, isTrue);
    });
  });
}

/// A socket with no network in it.
///
/// The race above is only testable because this exists: it runs at full speed,
/// it cannot flake, and the test decides exactly when the server speaks.
class _FakeSocket implements HaSocket {
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  bool closed = false;

  void serverSays(Map<String, Object?> frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  /// Answers the request that went out with [id].
  void answer(int id, Map<String, Object?> body) =>
      serverSays(<String, Object?>{'type': 'result', 'id': id, ...body});

  void serverCloses() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<Map<String, Object?>> get incoming => _incoming.stream;

  @override
  void send(Map<String, Object?> frame) => sent.add(frame);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }
}
