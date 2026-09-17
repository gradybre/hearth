/// One connection's whole life (`docs/HOME_ASSISTANT_SPEC.md` §6.1).
///
/// The session in `ha_session.dart` is one socket from hello to goodbye. This
/// is what sits above it: opening one, holding the world it produced, applying
/// what changes, noticing when it dies, deciding whether to try again, and —
/// the part that is easy to skip — **not trusting anything the old one said
/// once a new one exists.**
///
/// §6.1: "Reconcile a fresh snapshot after reconnection instead of trusting an
/// old socket's state." A reconnect is not a resumption. The house had however
/// long the outage lasted to change, and events during it went nowhere. So a
/// new session bootstraps from scratch, and everything held from the old one is
/// marked unverified the moment the socket drops rather than the moment a
/// replacement succeeds — because between those two moments is exactly when
/// somebody is looking at the screen wondering why the door still says Closed.
///
/// Time is injected. A controller that sleeps on a real clock can only be
/// tested by waiting, and the reconnect behaviour is the part most worth
/// testing.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../../domain/house/entity_id.dart';
import '../../domain/house/entity_state.dart';
import 'ha_reconnect.dart';
import 'ha_session.dart';

/// Where a connection is right now.
enum HaConnectionPhase {
  /// Never started, or deliberately stopped.
  idle,

  /// Opening a socket, or bootstrapping one.
  connecting,

  /// Up, with a reconciled world.
  live,

  /// Down, and waiting out a backoff before trying again.
  waiting,

  /// Down, and not trying again. The token was refused, or the server is not
  /// one this client can talk to — §6.1 says stop and ask rather than hammer.
  needsAttention,
}

/// A connection's state, as a screen would read it.
@immutable
class HaConnectionState {
  const HaConnectionState({
    required this.phase,
    this.world = const <EntityId, EntityState>{},
    this.trouble,
    this.generation = 0,
  });

  final HaConnectionPhase phase;

  /// Every entity Home Assistant reported, as last known.
  ///
  /// Kept through an outage rather than cleared, because "Last known: closed"
  /// is more use than a blank card — but every reading in it is demoted to
  /// [Freshness.lastKnown] when the socket drops, so nothing can present it as
  /// current. §4.2 is explicit that a lost connection never says an
  /// unqualified "Closed".
  final Map<EntityId, EntityState> world;

  /// Why it is not live, when it is not.
  final HaSessionException? trouble;

  /// Which connection this world came from. A caller holding an older number
  /// is holding something superseded.
  final int generation;

  bool get isLive => phase == HaConnectionPhase.live;

  HaConnectionState copyWith({
    HaConnectionPhase? phase,
    Map<EntityId, EntityState>? world,
    HaSessionException? trouble,
    bool clearTrouble = false,
    int? generation,
  }) => HaConnectionState(
    phase: phase ?? this.phase,
    world: world ?? this.world,
    trouble: clearTrouble ? null : (trouble ?? this.trouble),
    generation: generation ?? this.generation,
  );
}

/// Opens a session. Injected so the controller never holds a URL or a token.
typedef HaSessionOpener = Future<HaSession> Function({required int generation});

/// Waits. Injected so a test does not.
typedef HaWait = Future<void> Function(Duration delay);

/// Owns one Home Assistant connection.
class HaConnection {
  HaConnection({
    required HaSessionOpener open,
    HaWait? wait,
    ReconnectPolicy policy = const ReconnectPolicy(),
  }) : _open = open,
       _wait = wait ?? Future<void>.delayed,
       _policy = policy;

  final HaSessionOpener _open;
  final HaWait _wait;
  ReconnectPolicy _policy;

  /// Rises with every attempt, and never resets.
  ///
  /// The guard that makes a late answer harmless: anything arriving with a
  /// generation below this belongs to a connection nobody is listening to.
  /// Rising rather than toggling means a *third* attempt cannot be mistaken
  /// for the first, which a boolean "is current" flag would allow.
  int _generation = 0;

  HaSession? _session;
  StreamSubscription<HaStateChange>? _watching;
  bool _stopped = false;

  final StreamController<HaConnectionState> _states =
      StreamController<HaConnectionState>.broadcast();

  HaConnectionState _state = const HaConnectionState(
    phase: HaConnectionPhase.idle,
  );

  /// The current state, and every change to it.
  Stream<HaConnectionState> get states => _states.stream;
  HaConnectionState get state => _state;

  void _publish(HaConnectionState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Connects, and keeps connecting until told to stop.
  ///
  /// Returns when the connection is live or has given up — not when it closes.
  Future<void> start() async {
    _stopped = false;
    _policy = _policy.restarted;
    await _attempt();
  }

  /// A person pressed Retry.
  ///
  /// Distinct from [start] only in intent, but the intent matters: §6.1 wants a
  /// manual retry beside the automatic one, and somebody who has just plugged
  /// the Pi back in should not wait out a backoff they cannot see.
  Future<void> retryNow() => start();

  Future<void> _attempt() async {
    if (_stopped) return;

    final int mine = ++_generation;
    _publish(
      _state.copyWith(
        phase: HaConnectionPhase.connecting,
        clearTrouble: true,
        generation: mine,
      ),
    );

    try {
      final HaSession session = await _open(generation: mine);
      // Opening is not instant, and a stop or a newer attempt can land during
      // it. Either way this session is already obsolete and must be closed
      // rather than adopted — a live socket nobody references is a socket that
      // keeps receiving.
      if (_stopped || mine != _generation) {
        await session.close();
        return;
      }

      final Map<EntityId, EntityState> world = await session.bootstrap();
      if (_stopped || mine != _generation) {
        await session.close();
        return;
      }

      _session = session;
      _policy = _policy.restarted;
      _watching = session.changes.listen(
        (HaStateChange change) {
          // The generation guard again, on the hot path. A frame from a
          // superseded socket reaching a newer world is exactly the stale
          // callback §5.2 asks to be ignored.
          if (mine != _generation) return;
          _publish(
            _state.copyWith(
              world: <EntityId, EntityState>{
                ..._state.world,
                change.entity: change.state,
              },
            ),
          );
        },
        onDone: () {
          if (mine == _generation) unawaited(_lost(_disconnected));
        },
        onError: (Object _) {
          if (mine == _generation) unawaited(_lost(_disconnected));
        },
      );

      _publish(
        _state.copyWith(
          phase: HaConnectionPhase.live,
          world: world,
          clearTrouble: true,
          generation: mine,
        ),
      );
    } on HaSessionException catch (failure) {
      if (_stopped || mine != _generation) return;
      await _lost(failure);
    }
  }

  static const HaSessionException _disconnected = HaSessionException(
    HaSessionFailure.connectionLost,
    'The connection to Home Assistant ended.',
  );

  /// The connection went away, or never came up.
  Future<void> _lost(HaSessionException failure) async {
    await _teardown();
    if (_stopped) return;

    // Everything held is now unverified. Demoted at the moment the socket
    // drops rather than when a replacement fails, because between those two
    // moments is when somebody is looking at the screen — and a door that
    // still says "Closed" during an outage is the exact lie §4.2 forbids.
    final Map<EntityId, EntityState> stale = <EntityId, EntityState>{
      for (final MapEntry<EntityId, EntityState> e in _state.world.entries)
        e.key: e.value.staleNow(),
    };

    final ReconnectDecision decision = _policy.after(failure);
    _policy = _policy.then(decision);

    switch (decision) {
      case StopRetrying():
        _publish(
          _state.copyWith(
            phase: HaConnectionPhase.needsAttention,
            world: stale,
            trouble: failure,
          ),
        );
      case RetryAfter(:final Duration delay):
        _publish(
          _state.copyWith(
            phase: HaConnectionPhase.waiting,
            world: stale,
            trouble: failure,
          ),
        );
        // Detached, deliberately. Awaiting the backoff here would make it part
        // of whatever chain asked to connect — so `start()` would not return
        // until every retry had run, and a screen calling it would hang for
        // the length of the outage rather than being told "waiting" and
        // getting on with drawing that.
        unawaited(_retryAfter(delay, _generation));
    }
  }

  /// Waits out a backoff, then tries again — unless something moved on.
  ///
  /// [waitingFor] is the generation this retry belongs to. A manual retry or a
  /// stop during the backoff bumps the number, and this one then does nothing:
  /// without that, a parked retry firing after `stop()` would reconnect a
  /// connection somebody deliberately ended, and two attempts could run at
  /// once after a Retry tap.
  Future<void> _retryAfter(Duration delay, int waitingFor) async {
    await _wait(delay);
    if (_stopped || waitingFor != _generation) return;
    await _attempt();
  }

  Future<void> _teardown() async {
    final StreamSubscription<HaStateChange>? watching = _watching;
    final HaSession? session = _session;
    _watching = null;
    _session = null;
    await watching?.cancel();
    await session?.close();
  }

  /// Stops, and stays stopped.
  ///
  /// Used when the screen goes away and when the app is backgrounded (§6.1:
  /// "Stop or suspend it when backgrounded; refresh on return"). Bumping the
  /// generation is what makes an attempt already in flight harmless.
  Future<void> stop() async {
    _stopped = true;
    _generation++;
    await _teardown();
    _publish(
      _state.copyWith(
        phase: HaConnectionPhase.idle,
        world: <EntityId, EntityState>{
          for (final MapEntry<EntityId, EntityState> e in _state.world.entries)
            e.key: e.value.staleNow(),
        },
      ),
    );
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }
}
