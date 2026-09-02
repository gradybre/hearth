import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_gateway.dart';

import '../data/sync/photo_sync.dart';
import '../data/sync/sync_engine.dart';
import 'providers.dart';

/// When the queue gets drained (spec §7.1).
///
/// Three triggers, each for a moment the user would expect their data to have
/// caught up: signing in, coming back to the app, and finishing a local write.
/// There is no polling timer — a phone that syncs on a schedule spends battery
/// asking a question whose answer has not changed.
class SyncController extends Notifier<SyncStatus> with WidgetsBindingObserver {
  Timer? _debounce;
  bool _running = false;

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

  Future<void> sync() async {
    if (_running || !ref.read(supabaseReadyProvider)) return;

    // Nothing to sync as nobody. Worse than pointless: RLS answers a
    // signed-out pull with an empty result rather than an error, which looks
    // exactly like "the server has nothing new" — so the watermark would move
    // forward over records this device had never seen, and they would never
    // be asked for again.
    if (!_signedIn) return;
    _running = true;
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

      state = SyncStatus.done(
        result,
        pulled: PullResult(
          applied: library.applied + records.applied,
          skipped: library.skipped + records.skipped,
          stoppedBecauseOffline:
              library.stoppedBecauseOffline || records.stoppedBecauseOffline,
        ),
      );
    } on Object catch (error) {
      // Object, not Exception: a type error from a malformed payload is an
      // Error, and letting it escape would lose the sync silently.
      state = SyncStatus.failed('$error');
    } finally {
      _running = false;
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
  bool get hasProblem => error != null || (result?.failed ?? 0) > 0;
}
