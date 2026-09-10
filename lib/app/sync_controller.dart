import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_gateway.dart';

import '../data/sync/photo_sync.dart';
import '../data/sync/sync_engine.dart';
import 'providers.dart';
import 'sync_gate.dart';

/// When the queue gets drained (spec §7.1).
///
/// Three triggers, each for a moment the user would expect their data to have
/// caught up: signing in, coming back to the app, and finishing a local write.
/// There is no polling timer — a phone that syncs on a schedule spends battery
/// asking a question whose answer has not changed.
class SyncController extends Notifier<SyncStatus> with WidgetsBindingObserver {
  Timer? _debounce;
  final SyncGate _gate = SyncGate();

  /// Whether anyone is signed in, tracked from the account listener rather
  /// than read back from the provider: reading it here answered null even
  /// just after a sign-in, and a sync that quietly does nothing is worse than
  /// one that fails loudly.
  bool _signedIn = false;

  @override
  SyncStatus build() {
    if (!ref.watch(supabaseReadyProvider)) return const SyncStatus.idle();

    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _debounce?.cancel();
      _backoff?.cancel();
    });

    // Signing in, or out: a fresh session means the queue may belong to
    // someone who can now actually push it.
    ref.listen(accountProvider, (_, AsyncValue<HearthAccount?> next) {
      _signedIn = next.value != null;
      if (_signedIn) syncSoon();
    });

    // Any local write. Debounced, because a recipe save queues several rows
    // and each one would otherwise start its own run.
    //
    // Nothing here may invalidate this provider: it is a Drift stream that
    // already re-emits when the queue changes, and refreshing it by hand
    // would retrigger this very listener — a sync loop that never stops and
    // never notices, because each run looks perfectly ordinary on its own.
    ref.listen(pendingWriteCountProvider, (_, _) => syncSoon());

    // A photo added here is a local write too, and deserves the same nudge.
    // Same shape and same warning as above — a Drift stream, never invalidated
    // by hand. The attempt counter this listener reacts to is also what stops
    // it looping: a photo that keeps failing drops out of the candidate query
    // after five goes, so the retries terminate rather than trickle for ever.
    ref.listen(pendingPhotoWorkProvider, (_, _) => syncSoon());

    return const SyncStatus.idle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncSoon();
  }

  /// Asks for a sync shortly. Repeated calls collapse into one.
  void syncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), sync);
  }

  /// Comes back when the queue's own backoff says it is worth asking again.
  ///
  /// #22 gave a refused write a wait — 2s, 30s, 5m, 30m, 2h — and gave
  /// nothing a reason to return when the wait was over. Every other trigger
  /// here is somebody doing something: signing in, writing, resuming, tapping
  /// Sync now. A write sitting out two hours does none of those, so on a
  /// phone left on a counter it simply sat there.
  ///
  /// One timer for the *soonest* moment anything is due, re-set after each
  /// pass. Not a poll: it asks the queue when to come back and then comes
  /// back once, which is the distinction the class comment above draws
  /// between this and a schedule that spends battery asking a question whose
  /// answer has not changed.
  Future<void> _wakeWhenDue() async {
    _backoff?.cancel();
    final DateTime? due = await ref
        .read(pendingWriteStoreProvider)
        .nextAttemptDue();
    if (due == null) return;

    // A floor, because a moment already past would fire immediately and a
    // pass that fails the same way each time would then spin.
    final Duration wait = due.difference(DateTime.now().toUtc());
    _backoff = Timer(
      wait < const Duration(seconds: 1) ? const Duration(seconds: 1) : wait,
      sync,
    );
  }

  Timer? _backoff;

  Future<void> sync() async {
    if (!ref.read(supabaseReadyProvider)) return;

    // Nothing to sync as nobody. Worse than pointless: RLS answers a
    // signed-out pull with an empty result rather than an error, which looks
    // exactly like "the server has nothing new" — so the watermark would move
    // forward over records this device had never seen, and they would never
    // be asked for again.
    if (!_signedIn) return;

    // Turned away rather than dropped: the gate remembers, and says so at the
    // end of the pass that was already running.
    if (!_gate.start()) return;
    state = const SyncStatus.syncing();
    try {
      // Push before pull, always. Sending what this device did before
      // accepting what another device did means a local change can never be
      // silently overwritten by a server copy that predates it.
      final SyncResult result = await ref.read(syncEngineProvider).push();

      // The library first — recipes and foods are what a meal plan entry
      // points at, and an entry whose recipe has not arrived yet shows as a
      // gap until the next run.
      final PullResult library = await ref.read(librarySyncProvider).pull();
      final PullResult records = await ref.read(recordSyncProvider).pull();

      // Photos last. A missing picture blocks neither cooking nor logging, and
      // the recipe row has to have reached the server before the storage
      // policy will admit an object underneath it.
      if (ref.read(photoSyncProvider) case final PhotoSync photos) {
        await photos.push();
        await photos.pull();
      }

      final bool abandoned = library.abandonedScope || records.abandonedScope;

      // The one moment this device and the server are known to agree: the
      // queue drained, both halves of the pull came down, and nothing was
      // abandoned or cut short by a lost connection. Recorded here rather
      // than per table, because "each table is up to some date or other" is
      // not an answer to "when was I last in step?".
      if (!abandoned &&
          result.isFullyDrained &&
          !result.stoppedBecauseOffline &&
          !library.stoppedBecauseOffline &&
          !records.stoppedBecauseOffline) {
        try {
          await ref
              .read(syncCheckpointsProvider)
              .recordFullPass(DateTime.now().toUtc());
        } on Object {
          // Swallowed on purpose, and this is the only place in the pass
          // where that is right: a full disk failing to write a *note about*
          // a sync must not turn the sync that just succeeded into a reported
          // failure. The worst case is a stale line in Settings; the
          // alternative is a red panel over a green pass.
        }
      }

      state = SyncStatus.done(
        result,
        pulled: PullResult(
          applied: library.applied + records.applied,
          skipped: library.skipped + records.skipped,
          stoppedBecauseOffline:
              library.stoppedBecauseOffline || records.stoppedBecauseOffline,
          abandonedScope: abandoned,
        ),
      );

      // An abandoned pass brought down part of nothing and left no
      // checkpoint. Ask again under whoever is signed in now: the sign-in
      // that usually causes this fires its own nudge, but a household
      // changing or a deliberate clearing does not have to.
      if (abandoned) syncSoon();
    } on Object catch (error) {
      // Object, not Exception: a type error from a malformed payload is an
      // Error, and letting it escape would lose the sync silently.
      state = SyncStatus.failed('$error');
    } finally {
      // However the pass ended — drained, refused, or cut off offline — the
      // queue knows whether anything is still waiting and when. Asked here
      // rather than only on success, because a pass that failed is exactly
      // the one that left something waiting.
      unawaited(_wakeWhenDue());

      // Asked again while that was running: honour it once, debounced like
      // any other request rather than called straight through, so a pass that
      // queues its own writes cannot chase its own tail.
      if (_gate.finish()) syncSoon();
    }
  }
}

/// What the last sync did, for anything that wants to say so.
@immutable
class SyncStatus {
  const SyncStatus.idle()
    : result = null,
      pulled = null,
      error = null,
      isSyncing = false;
  const SyncStatus.syncing()
    : result = null,
      pulled = null,
      error = null,
      isSyncing = true;
  const SyncStatus.done(this.result, {this.pulled})
    : error = null,
      isSyncing = false;
  const SyncStatus.failed(this.error)
    : result = null,
      pulled = null,
      isSyncing = false;

  final SyncResult? result;
  final PullResult? pulled;
  final String? error;
  final bool isSyncing;

  /// True when there is something the user would want to know about: writes
  /// that could not be sent, as opposed to writes merely waiting for a
  /// network.
  ///
  /// A stranded write counts even though nothing tried it this pass. It has
  /// stopped being asked, so it will not resolve itself, and going quiet
  /// about it is how it would sit there unnoticed for ever.
  bool get hasProblem =>
      error != null || (result?.failed ?? 0) > 0 || (result?.stranded ?? 0) > 0;
}
