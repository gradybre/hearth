import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/preference_store.dart';

enum WeekContentView { meals, nutrition }

enum WeekViewPreferenceError { read, write }

class WeekViewPreferenceState {
  const WeekViewPreferenceState({
    this.view = WeekContentView.meals,
    this.error,
  });

  final WeekContentView view;
  final WeekViewPreferenceError? error;
}

/// One device preference, kept alive across Day/Week navigation. Explicit
/// choices supersede an in-flight restore, and writes reach storage in order.
class WeekViewPreference extends Notifier<WeekViewPreferenceState> {
  int _revision = 0;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  WeekViewPreferenceState build() {
    final PreferenceStore store = ref.watch(preferenceStoreProvider);
    final int revision = ++_revision;
    unawaited(_restore(store, revision));
    return const WeekViewPreferenceState();
  }

  Future<void> _restore(PreferenceStore store, int revision) async {
    try {
      final String? saved = await store.read(PreferenceStore.weekContentView);
      if (!ref.mounted || revision != _revision) return;
      state = WeekViewPreferenceState(
        view: saved == WeekContentView.nutrition.name
            ? WeekContentView.nutrition
            : WeekContentView.meals,
      );
    } on Object {
      if (!ref.mounted || revision != _revision) return;
      state = WeekViewPreferenceState(
        view: state.view,
        error: WeekViewPreferenceError.read,
      );
    }
  }

  Future<void> choose(WeekContentView view) {
    final PreferenceStore store = ref.read(preferenceStoreProvider);
    final int revision = ++_revision;
    state = WeekViewPreferenceState(view: view);
    return _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.write(PreferenceStore.weekContentView, view.name);
        if (!ref.mounted || revision != _revision) return;
        state = WeekViewPreferenceState(view: view);
      } on Object {
        if (!ref.mounted || revision != _revision) return;
        state = WeekViewPreferenceState(
          view: view,
          error: WeekViewPreferenceError.write,
        );
      }
    });
  }

  Future<void> retry() => state.error == WeekViewPreferenceError.read
      ? _restore(ref.read(preferenceStoreProvider), ++_revision)
      : choose(state.view);
}
