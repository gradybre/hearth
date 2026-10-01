import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/features/plan/week_view_preference.dart';

class _ControlledStore extends PreferenceStore {
  _ControlledStore(super.db);

  final Completer<String?> initialRead = Completer<String?>();
  final List<String> writes = <String>[];
  Completer<void>? holdWrite;
  bool failWrite = false;
  int reads = 0;

  @override
  Future<String?> read(String key) async {
    expect(key, PreferenceStore.weekContentView);
    return reads++ == 0 ? initialRead.future : super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(value);
    await holdWrite?.future;
    if (failWrite) throw StateError('Storage unavailable');
    await super.write(key, value);
  }
}

void main() {
  late HearthDatabase db;
  setUp(() => db = HearthDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer containerFor(PreferenceStore store) {
    final ProviderContainer container = ProviderContainer(
      overrides: [preferenceStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('first use starts with Meals; unknown saved values do too', () async {
    final _ControlledStore store = _ControlledStore(db);
    final ProviderContainer container = containerFor(store);
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
    store.initialRead.complete('a newer unsupported value');
    await settle();
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
  });

  test('restores Nutrition without writing over the saved choice', () async {
    final _ControlledStore store = _ControlledStore(db);
    final ProviderContainer container = containerFor(store);
    container.read(weekViewPreferenceProvider);
    store.initialRead.complete('nutrition');
    await settle();
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.nutrition,
    );
    expect(store.writes, isEmpty);
  });

  test('an explicit choice wins over a late stored read', () async {
    final _ControlledStore store = _ControlledStore(db);
    final ProviderContainer container = containerFor(store);
    await container
        .read(weekViewPreferenceProvider.notifier)
        .choose(WeekContentView.meals);
    store.initialRead.complete('nutrition');
    await settle();
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
    expect(
      await PreferenceStore(db).read(PreferenceStore.weekContentView),
      'meals',
    );
  });

  test('rapid choices write in order and survive a fresh container', () async {
    final _ControlledStore store = _ControlledStore(db);
    store.initialRead.complete(null);
    store.holdWrite = Completer<void>();
    final ProviderContainer container = containerFor(store);
    final WeekViewPreference preference = container.read(
      weekViewPreferenceProvider.notifier,
    );
    final Future<void> first = preference.choose(WeekContentView.nutrition);
    final Future<void> last = preference.choose(WeekContentView.meals);
    await settle();
    expect(store.writes, <String>['nutrition']);
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
    store.holdWrite!.complete();
    await Future.wait(<Future<void>>[first, last]);
    expect(store.writes, <String>['nutrition', 'meals']);

    final ProviderContainer restarted = containerFor(PreferenceStore(db));
    final Completer<void> restored = Completer<void>();
    restarted.listen(weekViewPreferenceProvider, (_, next) {
      if (!restored.isCompleted) restored.complete();
    });
    await restored.future;
    expect(
      restarted.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
    await restarted
        .read(weekViewPreferenceProvider.notifier)
        .choose(WeekContentView.nutrition);
    final _ControlledStore secondStore = _ControlledStore(db);
    final ProviderContainer secondRestart = containerFor(secondStore);
    secondRestart.read(weekViewPreferenceProvider);
    secondStore.initialRead.complete(
      await PreferenceStore(db).read(PreferenceStore.weekContentView),
    );
    await settle();
    expect(
      secondRestart.read(weekViewPreferenceProvider).view,
      WeekContentView.nutrition,
    );
  });

  test('write failure keeps the chosen view and can be retried', () async {
    final _ControlledStore store = _ControlledStore(db)..failWrite = true;
    store.initialRead.complete(null);
    final ProviderContainer container = containerFor(store);
    final WeekViewPreference preference = container.read(
      weekViewPreferenceProvider.notifier,
    );
    await preference.choose(WeekContentView.nutrition);
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.nutrition,
    );
    expect(
      container.read(weekViewPreferenceProvider).error,
      WeekViewPreferenceError.write,
    );
    store.failWrite = false;
    await preference.retry();
    expect(container.read(weekViewPreferenceProvider).error, isNull);
    expect(
      await PreferenceStore(db).read(PreferenceStore.weekContentView),
      'nutrition',
    );
  });

  test('read failure is recoverable and never blocks Meals', () async {
    await PreferenceStore(db)
        .write(PreferenceStore.weekContentView, 'nutrition');
    final _ControlledStore store = _ControlledStore(db);
    final ProviderContainer container = containerFor(store);
    container.read(weekViewPreferenceProvider);
    store.initialRead.completeError(StateError('Read failed'));
    await settle();
    expect(
      container.read(weekViewPreferenceProvider).error,
      WeekViewPreferenceError.read,
    );
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.meals,
    );
    await container.read(weekViewPreferenceProvider.notifier).retry();
    expect(
      container.read(weekViewPreferenceProvider).view,
      WeekContentView.nutrition,
    );
    expect(container.read(weekViewPreferenceProvider).error, isNull);
  });

  test(
    'disposing during restoration or save does not update dead state',
    () async {
      final _ControlledStore store = _ControlledStore(db);
      store.holdWrite = Completer<void>();
      final ProviderContainer container = ProviderContainer(
        overrides: [preferenceStoreProvider.overrideWithValue(store)],
      );
      final Future<void> save = container
          .read(weekViewPreferenceProvider.notifier)
          .choose(WeekContentView.nutrition);
      container.dispose();
      store.initialRead.complete('meals');
      store.holdWrite!.complete();
      await save;
      expect(
        await PreferenceStore(db).read(PreferenceStore.weekContentView),
        'nutrition',
      );
    },
  );
}
