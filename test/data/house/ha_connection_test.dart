import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/house/ha_connection.dart';
import 'package:hearth/data/house/ha_session.dart';
import 'package:hearth/data/house/ha_socket.dart';
import 'package:hearth/domain/house/entity_id.dart';
import 'package:hearth/domain/house/entity_state.dart';

/// A connection's whole life (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
void main() {
  final EntityId door = EntityId.tryParse('binary_sensor.front_door')!;

  /// A session built on a fake socket, driven by the test.
  Future<HaSession> liveSession(
    _Server server, {
    required int generation,
  }) async {
    final Future<HaSession> opening = HaSession.open(
      url: Uri.parse('wss://ha.example.test/api/websocket'),
      token: 'NOT_A_REAL_TOKEN_example',
      opener: (Uri _) async => server.socket,
      generation: generation,
    );
    server.socket.serverSays(<String, Object?>{'type': 'auth_required'});
    await pumpEventQueue();
    server.socket.serverSays(<String, Object?>{'type': 'auth_ok'});
    final HaSession session = await opening;

    // bootstrap(): subscribe, then get_states.
    unawaited(
      pumpEventQueue().then((_) {
        server.socket.answer(1, <String, Object?>{});
        server.socket.answer(2, <String, Object?>{
          'result': <Object?>[server.doorRow],
        });
      }),
    );
    return session;
  }

  group('coming up', () {
    test('reports live with the world it bootstrapped', () async {
      final _Server server = _Server(doorState: 'off');
      final HaConnection connection = HaConnection(
        open: ({required int generation}) =>
            liveSession(server, generation: generation),
        wait: (Duration _) async {},
      );

      await connection.start();
      await pumpEventQueue();

      expect(connection.state.phase, HaConnectionPhase.live);
      expect(connection.state.world[door]!.value, 'off');
      expect(connection.state.world[door]!.isConfident, isTrue);
      await connection.dispose();
    });

    test('and a change afterwards lands in the world', () async {
      final _Server server = _Server(doorState: 'off');
      final HaConnection connection = HaConnection(
        open: ({required int generation}) =>
            liveSession(server, generation: generation),
        wait: (Duration _) async {},
      );
      await connection.start();
      await pumpEventQueue();

      server.socket.serverSays(server.doorChanged('on'));
      await pumpEventQueue();

      expect(connection.state.world[door]!.value, 'on');
      await connection.dispose();
    });
  });

  group('going away', () {
    test('demotes what it holds the moment the socket drops', () async {
      // Not when a replacement fails — between those two moments is when
      // somebody is looking at the screen, and a door that still says
      // "Closed" during an outage is the exact lie §4.2 forbids.
      final _Server server = _Server(doorState: 'off');
      final Completer<void> blockRetry = Completer<void>();
      final HaConnection connection = HaConnection(
        open: ({required int generation}) =>
            liveSession(server, generation: generation),
        wait: (Duration _) => blockRetry.future,
      );
      await connection.start();
      await pumpEventQueue();
      expect(connection.state.world[door]!.isConfident, isTrue);

      server.socket.serverCloses();
      await pumpEventQueue();

      expect(connection.state.phase, HaConnectionPhase.waiting);
      final EntityState held = connection.state.world[door]!;
      expect(held.value, 'off', reason: 'still worth showing');
      expect(held.freshness, Freshness.lastKnown);
      expect(
        held.isConfident,
        isFalse,
        reason: 'a lost connection makes the whole snapshot unverified',
      );

      blockRetry.complete();
      await connection.dispose();
    });

    test('and a refused token stops rather than backing off', () async {
      // §6.1: invalid credentials halt retry. The screen asks for a new token.
      int attempts = 0;
      final HaConnection connection = HaConnection(
        open: ({required int generation}) async {
          attempts++;
          throw const HaSessionException(
            HaSessionFailure.credentialsRejected,
            'no',
          );
        },
        wait: (Duration _) async {},
      );

      await connection.start();
      await pumpEventQueue();

      expect(connection.state.phase, HaConnectionPhase.needsAttention);
      expect(attempts, 1, reason: 'not retried even once');
      await connection.dispose();
    });

    test('and a lost connection is retried', () async {
      int attempts = 0;
      final HaConnection connection = HaConnection(
        open: ({required int generation}) async {
          attempts++;
          if (attempts < 3) {
            throw const HaSessionException(
              HaSessionFailure.connectionLost,
              'gone',
            );
          }
          throw const HaSessionException(
            HaSessionFailure.credentialsRejected,
            'stop here',
          );
        },
        wait: (Duration _) async {},
      );

      await connection.start();
      await pumpEventQueue();

      expect(attempts, 3);
      expect(connection.state.phase, HaConnectionPhase.needsAttention);
      await connection.dispose();
    });
  });

  group('the generation guard', () {
    test('a session that finishes opening after a stop is closed', () async {
      // A live socket nobody references is a socket that keeps receiving.
      final _Server server = _Server(doorState: 'off');
      final Completer<HaSession> slow = Completer<HaSession>();
      final HaConnection connection = HaConnection(
        open: ({required int generation}) => slow.future,
        wait: (Duration _) async {},
      );

      unawaited(connection.start());
      await pumpEventQueue();
      await connection.stop();

      slow.complete(await liveSession(server, generation: 1));
      await pumpEventQueue();

      expect(connection.state.phase, HaConnectionPhase.idle);
      expect(server.socket.closed, isTrue);
      await connection.dispose();
    });

    test('and an event from a superseded socket is ignored', () async {
      final _Server first = _Server(doorState: 'off');
      final _Server second = _Server(doorState: 'off');
      int opened = 0;
      final HaConnection connection = HaConnection(
        open: ({required int generation}) {
          opened++;
          return liveSession(
            opened == 1 ? first : second,
            generation: generation,
          );
        },
        wait: (Duration _) async {},
      );

      await connection.start();
      await pumpEventQueue();

      // A manual retry supersedes the first connection.
      await connection.retryNow();
      await pumpEventQueue();
      expect(opened, 2);

      // The old socket speaks. It must reach nobody.
      first.socket.serverSays(first.doorChanged('on'));
      await pumpEventQueue();

      expect(
        connection.state.world[door]!.value,
        'off',
        reason: 'the superseded socket cannot write into the new world',
      );
      await connection.dispose();
    });

    test('and the number rises rather than toggling', () async {
      // A third attempt must not be mistakable for the first, which a
      // boolean "is current" flag would allow.
      final List<int> generations = <int>[];
      final HaConnection connection = HaConnection(
        open: ({required int generation}) async {
          generations.add(generation);
          throw const HaSessionException(
            HaSessionFailure.credentialsRejected,
            'stop',
          );
        },
        wait: (Duration _) async {},
      );

      await connection.start();
      await connection.start();
      await connection.start();

      expect(generations, <int>[1, 2, 3]);
      await connection.dispose();
    });
  });

  group('stopping', () {
    test('goes idle, and halts the retry loop', () async {
      // §6.1: stop or suspend when backgrounded. A controller that keeps
      // retrying in the background is the unbounded loop that section forbids,
      // with the added insult of doing it while nobody is looking.
      int attempts = 0;
      final Completer<void> heldInBackoff = Completer<void>();
      final HaConnection connection = HaConnection(
        open: ({required int generation}) async {
          attempts++;
          throw const HaSessionException(
            HaSessionFailure.connectionLost,
            'gone',
          );
        },
        // Parks the retry so the test can stop mid-backoff, which is exactly
        // when backgrounding happens in practice.
        wait: (Duration _) => heldInBackoff.future,
      );

      await connection.start();
      await pumpEventQueue();
      expect(attempts, 1);
      expect(connection.state.phase, HaConnectionPhase.waiting);

      await connection.stop();
      heldInBackoff.complete();
      await pumpEventQueue();

      expect(connection.state.phase, HaConnectionPhase.idle);
      expect(
        attempts,
        1,
        reason: 'the parked retry must not fire after stopping',
      );
      await connection.dispose();
    });

    test('and what it was holding is no longer presented as current', () async {
      final _Server server = _Server(doorState: 'off');
      final HaConnection connection = HaConnection(
        open: ({required int generation}) =>
            liveSession(server, generation: generation),
        wait: (Duration _) async {},
      );
      await connection.start();
      await pumpEventQueue();

      await connection.stop();

      expect(connection.state.world[door]!.freshness, Freshness.lastKnown);
      await connection.dispose();
    });
  });
}

/// One fake Home Assistant, with a door in it.
class _Server {
  _Server({required this.doorState});

  final String doorState;
  final _FakeSocket socket = _FakeSocket();

  Map<String, Object?> get doorRow => <String, Object?>{
    'entity_id': 'binary_sensor.front_door',
    'state': doorState,
    'attributes': <String, Object?>{'device_class': 'door'},
    'last_changed': '2026-01-15T12:00:00Z',
    'last_updated': '2026-01-15T12:00:00Z',
  };

  Map<String, Object?> doorChanged(String to) => <String, Object?>{
    'type': 'event',
    'event': <String, Object?>{
      'event_type': 'state_changed',
      'data': <String, Object?>{
        'entity_id': 'binary_sensor.front_door',
        'new_state': <String, Object?>{
          'entity_id': 'binary_sensor.front_door',
          'state': to,
          'attributes': <String, Object?>{'device_class': 'door'},
          'last_changed': '2026-01-15T12:05:00Z',
          'last_updated': '2026-01-15T12:05:00Z',
        },
      },
    },
  };
}

class _FakeSocket implements HaSocket {
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  bool closed = false;

  void serverSays(Map<String, Object?> frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

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
