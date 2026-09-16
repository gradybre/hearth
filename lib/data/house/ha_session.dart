/// One conversation with Home Assistant (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
///
/// The handshake, the request ledger, and the one piece of this integration
/// most likely to be got quietly wrong: **the snapshot/subscription race.**
///
/// A client that wants both "everything, now" and "everything that changes
/// from now on" has to ask for them separately, and between the two answers a
/// door can open. Ask for the snapshot first and any change arriving before the
/// subscription is live is simply lost — the door shows Closed until the next
/// time somebody opens it, which could be tomorrow. So the order is fixed:
///
///  1. subscribe, and **buffer** every event that arrives;
///  2. fetch the snapshot;
///  3. drain the buffer over it, applying an event only where it is *not older*
///     than the snapshot's own reading for that entity.
///
/// That last clause is the defined ordering policy §6.1 asks for. It matters
/// because `get_states` is a live read, not a frozen one: an event buffered
/// during the fetch may already be reflected in what came back, and replaying
/// a stale one over a fresher snapshot would move a value backwards.
///
/// Everything here is testable against a fake [HaSocket] at full speed. A race
/// that can only be reproduced against a real server is a race nobody tests.
library;

import 'dart:async';

import '../../domain/house/entity_id.dart';
import '../../domain/house/entity_state.dart';
import 'ha_socket.dart';

/// Why a session ended, when it was not asked to.
enum HaSessionFailure {
  /// The token was refused. §6.1: invalid credentials halt retry and prompt
  /// reconnection — retrying a rejected token only burns the server's patience
  /// and, on some setups, gets the client banned.
  credentialsRejected,

  /// The server said something this client could not follow.
  unsupportedServer,

  /// The connection went away. This one is worth retrying.
  connectionLost,
}

/// Raised when a session cannot continue.
class HaSessionException implements Exception {
  const HaSessionException(this.failure, this.message);

  final HaSessionFailure failure;
  final String message;

  /// Whether a bounded retry makes sense. False for a rejected token, because
  /// nothing about waiting makes a wrong token right.
  bool get isRetryable => failure == HaSessionFailure.connectionLost;

  @override
  String toString() => 'HaSessionException(${failure.name}): $message';
}

/// A live conversation with one Home Assistant instance.
///
/// One session is one socket and one generation. Reconnecting makes a *new*
/// session rather than reviving this one — which is what makes the generation
/// guard trivial instead of subtle: a frame from an old socket reaches an
/// object nobody is listening to any more, and the alternative (one long-lived
/// object with a counter) is where stale-callback bugs live.
class HaSession {
  HaSession._(this._socket, this._generation);

  /// Opens a socket, authenticates, and returns a session ready to bootstrap.
  ///
  /// [token] is used once, here, and is never stored on the session — so a
  /// session object cannot leak a credential into a log line or an error, and
  /// there is nothing to redact later.
  static Future<HaSession> open({
    required Uri url,
    required String token,
    required HaSocketOpener opener,
    required int generation,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final HaSocket socket = await opener(url);
    final HaSession session = HaSession._(socket, generation);
    try {
      await session._authenticate(token).timeout(timeout);
      return session;
    } on TimeoutException {
      await socket.close();
      throw const HaSessionException(
        HaSessionFailure.connectionLost,
        'Home Assistant did not answer in time.',
      );
    } on Object {
      await socket.close();
      rethrow;
    }
  }

  final HaSocket _socket;

  /// Which connection this is. Carried so a caller holding an older session can
  /// tell that what it is about to act on is out of date.
  final int _generation;
  int get generation => _generation;

  StreamSubscription<Map<String, Object?>>? _listening;
  final Map<int, Completer<Map<String, Object?>>> _waiting =
      <int, Completer<Map<String, Object?>>>{};

  /// Home Assistant requires ids to rise, and never to repeat within a
  /// connection.
  int _nextId = 1;

  /// Events held while the snapshot is in flight. Null once draining is done,
  /// which is also how [_onEvent] knows whether to buffer or publish.
  List<Map<String, Object?>>? _buffer;

  final StreamController<HaStateChange> _changes =
      StreamController<HaStateChange>.broadcast();

  /// State changes, after the snapshot has been reconciled.
  Stream<HaStateChange> get changes => _changes.stream;

  bool _closed = false;

  Future<void> _authenticate(String token) async {
    final Completer<void> done = Completer<void>();

    _listening = _socket.incoming.listen(
      (Map<String, Object?> frame) {
        if (done.isCompleted) {
          _onFrame(frame);
          return;
        }
        switch (frame['type']) {
          case 'auth_required':
            // The one place the token is on the wire. Home Assistant wants it
            // unprompted-by-id, outside the request ledger.
            _socket.send(<String, Object?>{
              'type': 'auth',
              'access_token': token,
            });
          case 'auth_ok':
            done.complete();
          case 'auth_invalid':
            done.completeError(
              const HaSessionException(
                HaSessionFailure.credentialsRejected,
                'Home Assistant did not accept this token.',
              ),
            );
          default:
            done.completeError(
              const HaSessionException(
                HaSessionFailure.unsupportedServer,
                'This server did not answer the way Home Assistant does.',
              ),
            );
        }
      },
      onError: (Object error) {
        if (!done.isCompleted) {
          done.completeError(
            const HaSessionException(
              HaSessionFailure.connectionLost,
              'The connection to Home Assistant failed.',
            ),
          );
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.completeError(
            const HaSessionException(
              HaSessionFailure.connectionLost,
              'Home Assistant closed the connection.',
            ),
          );
        }
        _failEveryWaiter();
      },
    );

    return done.future;
  }

  void _onFrame(Map<String, Object?> frame) {
    switch (frame['type']) {
      case 'result':
        final Object? id = frame['id'];
        if (id is! int) return;
        // Resolved by id, so an answer to a superseded request cannot satisfy
        // a newer one (§6.1: "resolve pending requests by ID").
        _waiting.remove(id)?.complete(frame);
      case 'event':
        _onEvent(frame);
      default:
        // An unknown frame type is not an error. Home Assistant adds them, and
        // a client that dies on one is a client that dies on an upgrade.
        return;
    }
  }

  void _onEvent(Map<String, Object?> frame) {
    final HaStateChange? change = HaStateChange.fromEvent(frame);
    if (change == null) return;
    final List<Map<String, Object?>>? buffer = _buffer;
    if (buffer != null) {
      // Still bootstrapping. Hold it — dropping it here is exactly the lost
      // event this ordering exists to prevent.
      buffer.add(frame);
      return;
    }
    if (!_changes.isClosed) _changes.add(change);
  }

  /// Sends a request and waits for its result.
  Future<Map<String, Object?>> request(Map<String, Object?> payload) {
    if (_closed) {
      throw const HaSessionException(
        HaSessionFailure.connectionLost,
        'This connection is closed.',
      );
    }
    final int id = _nextId++;
    final Completer<Map<String, Object?>> answer =
        Completer<Map<String, Object?>>();
    _waiting[id] = answer;
    _socket.send(<String, Object?>{...payload, 'id': id});
    return answer.future;
  }

  /// Subscribes, then snapshots, then reconciles — in that order, which is the
  /// whole point (see the library comment).
  ///
  /// Returns the reconciled state of every entity Home Assistant reported.
  Future<Map<EntityId, EntityState>> bootstrap() async {
    // 1. Subscribe first. From here on, nothing that changes is missed; it is
    //    only delayed.
    _buffer = <Map<String, Object?>>[];
    await request(<String, Object?>{
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });

    // 2. Snapshot. Events arriving during this land in the buffer.
    final Map<String, Object?> result = await request(<String, Object?>{
      'type': 'get_states',
    });

    final Map<EntityId, EntityState> world = <EntityId, EntityState>{};
    final Object? rows = result['result'];
    if (rows is List) {
      for (final Object? row in rows) {
        if (row is! Map<String, Object?>) continue;
        final EntityId? id = EntityId.tryParse(row['entity_id'] as String?);
        if (id == null) continue;
        world[id] = stateFrom(row);
      }
    }

    // 3. Drain, newest-wins. An event buffered during the fetch may already be
    //    reflected in the snapshot — `get_states` is a live read — so applying
    //    it blindly could move a value backwards.
    final List<Map<String, Object?>> held = _buffer ?? const [];
    _buffer = null;
    for (final Map<String, Object?> frame in held) {
      final HaStateChange? change = HaStateChange.fromEvent(frame);
      if (change == null) continue;
      final EntityState? already = world[change.entity];
      if (_isNewer(change.state, already)) world[change.entity] = change.state;
      if (!_changes.isClosed) _changes.add(change);
    }

    return world;
  }

  /// Whether [candidate] should replace [existing].
  ///
  /// Compared on Home Assistant's own `last_updated`, never on arrival time:
  /// arrival time would make a late event look current, which is the mistake
  /// that lets a stale reading overwrite a fresh one. With no timestamp on
  /// either side there is nothing to order by, and the snapshot — the thing
  /// that was definitely asked for most recently — wins.
  static bool _isNewer(EntityState candidate, EntityState? existing) {
    if (existing == null) return true;
    final DateTime? a = candidate.lastUpdated;
    final DateTime? b = existing.lastUpdated;
    if (a == null) return false;
    if (b == null) return true;
    return !a.isBefore(b);
  }

  /// Home Assistant's state shape, as an [EntityState].
  ///
  /// Public and static so the parse is unit-testable with no socket — the seam
  /// `EdgeFunctionRecipeAi.recipeFrom` established in this repo.
  static EntityState stateFrom(Map<String, Object?> row) => EntityState(
    availability: Availability.fromState(row['state'] as String?),
    freshness: Freshness.live,
    raw: row['state'] as String?,
    attributes: switch (row['attributes']) {
      final Map<String, Object?> a => a,
      _ => const <String, Object?>{},
    },
    lastChanged: _time(row['last_changed']),
    lastUpdated: _time(row['last_updated']),
  );

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  void _failEveryWaiter() {
    // A socket that closed with requests outstanding must not leave their
    // futures hanging — a screen waiting forever is worse than one told.
    for (final Completer<Map<String, Object?>> waiter in _waiting.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          const HaSessionException(
            HaSessionFailure.connectionLost,
            'The connection closed before Home Assistant answered.',
          ),
        );
      }
    }
    _waiting.clear();
  }

  /// Ends this session. Anything still in flight fails; nothing is replayed.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failEveryWaiter();
    await _listening?.cancel();
    await _changes.close();
    await _socket.close();
  }
}

/// One entity changing, as Home Assistant reports it.
class HaStateChange {
  const HaStateChange({required this.entity, required this.state});

  final EntityId entity;
  final EntityState state;

  /// Null when the frame is not a usable `state_changed` event.
  ///
  /// §6.1 requires surviving malformed messages and missing attributes, so
  /// every step here can decline rather than throw. A removal — `new_state`
  /// null — is also declined: an entity going away is not a state, and §4.2
  /// wants a removed selection left visibly missing rather than silently
  /// updated to nothing.
  static HaStateChange? fromEvent(Map<String, Object?> frame) {
    final Object? event = frame['event'];
    if (event is! Map<String, Object?>) return null;
    if (event['event_type'] != 'state_changed') return null;

    final Object? data = event['data'];
    if (data is! Map<String, Object?>) return null;

    final EntityId? id = EntityId.tryParse(data['entity_id'] as String?);
    if (id == null) return null;

    final Object? next = data['new_state'];
    if (next is! Map<String, Object?>) return null;

    return HaStateChange(entity: id, state: HaSession.stateFrom(next));
  }
}
