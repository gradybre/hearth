import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    ref.listen(accountProvider, (_, _) => syncSoon());

    // Any local write. Debounced, because a recipe save queues several rows
    // and each one would otherwise start its own run.
    ref.listen(pendingWriteCountProvider, (_, _) => syncSoon());

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
    _running = true;
    state = const SyncStatus.syncing();
    try {
      final SyncResult result = await ref.read(syncEngineProvider).push();
      state = SyncStatus.done(result);
    } on Exception catch (error) {
      state = SyncStatus.failed('$error');
    } finally {
      _running = false;
      ref.invalidate(pendingWriteCountProvider);
    }
  }
}

/// What the last sync did, for anything that wants to say so.
@immutable
class SyncStatus {
  const SyncStatus.idle() : result = null, error = null, isSyncing = false;
  const SyncStatus.syncing() : result = null, error = null, isSyncing = true;
  const SyncStatus.done(this.result) : error = null, isSyncing = false;
  const SyncStatus.failed(this.error) : result = null, isSyncing = false;

  final SyncResult? result;
  final String? error;
  final bool isSyncing;

  /// True when there is something the user would want to know about: writes
  /// that could not be sent, as opposed to writes merely waiting for a
  /// network.
  bool get hasProblem => error != null || (result?.failed ?? 0) > 0;
}
