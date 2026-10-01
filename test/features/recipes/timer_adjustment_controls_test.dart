import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/cook_timers.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/local/cook_timer_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/timer_bar.dart';

import '../../support/app_harness.dart';
import '../../support/fake_kitchen.dart';
import '../../support/fixtures.dart';

enum _State { running, paused, finished }

class _Fixture {
  _Fixture(this.db, this.store, this.container, this.alerts, this.now);
  final HearthDatabase db;
  final _FailingStore store;
  final ProviderContainer container;
  final _Alerts alerts;
  final DateTime now;
  CookTimersNotifier get control => container.read(cookTimersProvider.notifier);
  List<CookTimer> get timers => container.read(cookTimersProvider).value!;
}

class _FailingStore extends CookTimerStore {
  _FailingStore(super.db);
  bool failUpdate = false;
  @override
  Future<bool> updateExisting(CookTimer timer) {
    if (failUpdate) throw Exception('Write failed');
    return super.updateExisting(timer);
  }
}

class _Alerts extends FakeTimerAlerts {
  bool failSchedule = false;
  bool failCancel = false;
  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw Exception('Cancel failed');
    await super.cancel(id);
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (failSchedule) throw Exception('Alert failed');
    await super.schedule(id: id, title: title, body: body, at: at);
  }
}

Finder _action(String name) =>
    find.byKey(ValueKey<String>('timer-$name-pasta'));
Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is TextField && widget.decoration?.labelText == label,
);

Future<_Fixture> _pump(
  WidgetTester tester, {
  bool cooking = false,
  _State state = _State.running,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = scale == 1
      ? const Size(390, 844)
      : const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
  );
  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  final _FailingStore store = _FailingStore(db);
  final _Alerts alerts = _Alerts();
  await store.upsert(
    CookTimer(
      id: 'pasta',
      label: 'Simmer the pasta',
      stepId: 'pasta-step',
      stepNumber: 2,
      duration: const Duration(minutes: 10),
      startedAt: now.subtract(
        Duration(minutes: state == _State.finished ? 12 : 2),
      ),
      elapsedWhenPaused: state == _State.paused
          ? const Duration(minutes: 2)
          : null,
    ),
    recipeTitle: 'Pasta supper',
  );
  final ProviderContainer container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      cookTimerStoreProvider.overrideWithValue(store),
      cookTimersProvider.overrideWith(() => CookTimersNotifier(now: () => now)),
      timerAlertsProvider.overrideWithValue(alerts),
      screenKeeperProvider.overrideWithValue(FakeScreenKeeper()),
      cookSessionStoreProvider.overrideWithValue(FakeCookSessionStore()),
      cookShowAllStepsProvider.overrideWith(FakeCookStepView.new),
    ],
  );
  await container.read(cookTimersProvider.future);
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? HearthTheme.dark()
            : HearthTheme.light(),
        home: cooking
            ? CookAlongScreen(
                recipe: aRecipe(
                  title: 'Pasta supper',
                  steps: <RecipeStep>[aStep('Simmer the pasta until tender.')],
                ),
              )
            : const Scaffold(
                body: Center(child: Text('Kitchen')),
                bottomNavigationBar: CookTimerBar(),
              ),
      ),
    ),
  );
  await pumpFrames(tester);
  if (!cooking) {
    await tester.tap(find.byType(CookTimerBar));
    await pumpFrames(tester, frames: 12);
  }
  return _Fixture(db, store, container, alerts, now);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder.hitTestable());
  await pumpFrames(tester, frames: 12);
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await _reveal(tester, _field(label));
  await tester.enterText(_field(label), text);
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  bool focused() {
    final BuildContext? current = FocusManager.instance.primaryFocus?.context;
    if (current == null) return false;
    final Element element = tester.element(target);
    if (current == element) return true;
    bool found = false;
    (current as Element).visitAncestorElements((Element ancestor) {
      found = ancestor == element;
      return !found;
    });
    return found;
  }

  for (int i = 0; i < 40 && !focused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(focused(), isTrue);
}

void main() {
  testWidgets('a finished timer announces which timer is up', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pump(tester, cooking: true, state: _State.finished);
    expect(
      find.bySemanticsLabel('Simmer the pasta timer is up'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Time is up')),
      isSemantics(label: 'Simmer the pasta timer is up', isLiveRegion: true),
    );
    semantics.dispose();
  });

  for (final bool cooking in <bool>[false, true]) {
    for (final _State state in _State.values) {
      testWidgets(
        '${cooking ? 'Cook' : 'Tray'} adjusts an existing ${state.name} timer',
        (WidgetTester tester) async {
          final _Fixture fixture = await _pump(
            tester,
            cooking: cooking,
            state: state,
          );
          final Duration before = fixture.timers.single.remainingAt(
            fixture.now,
          );
          await _tap(tester, _action('add-1'));
          await _tap(tester, _action('add-5'));
          expect(
            fixture.timers.single.remainingAt(fixture.now),
            before + const Duration(minutes: 6),
          );
          expect(fixture.timers.single.isPaused, state == _State.paused);
          await _tap(tester, _action('set'));
          await _enter(tester, 'Minutes', '2');
          await _enter(tester, 'Seconds', '15');
          await _tap(tester, find.text('Save time'));
          expect(
            fixture.timers.single.remainingAt(fixture.now),
            const Duration(minutes: 2, seconds: 15),
          );
          expect(fixture.timers.single.isPaused, state == _State.paused);
          expect(fixture.timers.single.id, 'pasta');
          final CookTimerRow stored =
              (await fixture.db.select(fixture.db.cookTimers).get()).single;
          expect(stored.recipeTitle, 'Pasta supper');
          expect(stored.stepId, 'pasta-step');
          expect(stored.stepNumber, 2);
          expect(fixture.alerts.cancelled, hasLength(3));
          expect(
            fixture.alerts.scheduled.length,
            state == _State.paused ? 0 : 3,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('invalid or non-finite input does not change the timer', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    final CookTimerRow before =
        (await fixture.db.select(fixture.db.cookTimers).get()).single;
    await _tap(tester, _action('set'));
    for (final (String, String) input in <(String, String)>[
      ('0', '0'),
      ('-1', '0'),
      ('NaN', '0'),
      ('Infinity', '0'),
      ('1.5', '0'),
      ('0', '60'),
      ('999999999999999999999999999', '0'),
    ]) {
      await _enter(tester, 'Minutes', input.$1);
      await _enter(tester, 'Seconds', input.$2);
      await _tap(tester, find.text('Save time'));
      expect(find.text('Save time'), findsOneWidget);
      expect(
        (await fixture.db.select(fixture.db.cookTimers).get()).single,
        before,
      );
    }
    await _tap(tester, find.text('Cancel'));
    expect(fixture.alerts.cancelled, isEmpty);
    expect(fixture.alerts.scheduled, isEmpty);
  });

  testWidgets('a set-time sheet follows a pause made while it was open', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    await _tap(tester, _action('set'));
    await _enter(tester, 'Minutes', '3');
    await _enter(tester, 'Seconds', '0');
    await fixture.control.togglePause(fixture.timers.single);
    await _tap(tester, find.text('Save time'));
    expect(fixture.timers.single.isPaused, isTrue);
    expect(
      fixture.timers.single.remainingAt(fixture.now),
      const Duration(minutes: 3),
    );
    expect(fixture.alerts.scheduled, isEmpty);
  });

  testWidgets('a stopped timer is not recreated by an open set-time sheet', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    await _tap(tester, _action('set'));
    await _enter(tester, 'Minutes', '3');
    await fixture.control.dismiss('pasta');
    await _tap(tester, find.text('Save time'));
    expect(fixture.timers, isEmpty);
    expect(await fixture.db.select(fixture.db.cookTimers).get(), isEmpty);
    expect(find.text('This timer has already been stopped.'), findsOneWidget);
  });

  testWidgets('alert retry keeps a saved addition exactly once', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    fixture.alerts.failSchedule = true;
    await _tap(tester, _action('add-1'));
    expect(fixture.timers.single.duration, const Duration(minutes: 11));
    expect(find.text('Timer saved. Alert update failed.'), findsOneWidget);
    fixture.alerts.failSchedule = false;
    await _tap(tester, find.text('Retry alert'));
    expect(fixture.timers.single.duration, const Duration(minutes: 11));
    expect(fixture.alerts.scheduled, <String>['pasta']);
  });

  testWidgets('failed storage is explained and can be retried once', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    fixture.store.failUpdate = true;
    await _tap(tester, _action('add-1'));
    expect(fixture.timers.single.duration, const Duration(minutes: 10));
    expect(
      find.text('The timer could not be saved. Please try again.'),
      findsOneWidget,
    );
    fixture.store.failUpdate = false;
    await _tap(tester, _action('add-1'));
    expect(fixture.timers.single.duration, const Duration(minutes: 11));
  });

  testWidgets('keyboard can add time and submit minutes and seconds', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = await _pump(tester);
    await _tabTo(tester, _action('add-1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect(fixture.timers.single.duration, const Duration(minutes: 11));
    await _tabTo(tester, _action('set'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    await _enter(tester, 'Minutes', '1');
    await _enter(tester, 'Seconds', '30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, frames: 12);
    expect(
      fixture.timers.single.remainingAt(fixture.now),
      const Duration(seconds: 90),
    );
  });

  for (final bool cooking in <bool>[false, true]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets(
        '${cooking ? 'Cook' : 'Tray'} controls and keyboard fit 320×568/3× ${brightness.name}',
        (WidgetTester tester) async {
          final _Fixture fixture = await _pump(
            tester,
            cooking: cooking,
            scale: 3,
            brightness: brightness,
          );
          for (final String name in <String>[
            'pause',
            'stop',
            'add-1',
            'add-5',
            'set',
          ]) {
            final Finder action = _action(name);
            await _reveal(tester, action);
            expect(action.hitTestable(), findsOneWidget);
            final Size size = tester.getSize(action);
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          }
          await _tap(tester, _action('set'));
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pump();
          await _enter(tester, 'Minutes', '2');
          await _enter(tester, 'Seconds', '30');
          await _tap(tester, find.text('Save time'));
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pump();
          expect(
            fixture.timers.single.remainingAt(fixture.now),
            const Duration(seconds: 150),
          );
          expect(tester.takeException(), isNull);
          fixture.alerts.failSchedule = true;
          await _tap(tester, _action('add-1'));
          expect(find.text('Retry alert'), findsOneWidget);
          expect(find.text('Retry alert').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          fixture.alerts.failSchedule = false;
          await _tap(tester, find.text('Retry alert'));
          expect(fixture.timers.single.duration, const Duration(seconds: 210));
          expect(tester.takeException(), isNull);
          fixture.alerts.failCancel = true;
          await _tap(tester, _action('stop'));
          expect(fixture.timers, isEmpty);
          expect(find.text('Retry alert').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          fixture.alerts.failCancel = false;
          await _tap(tester, find.text('Retry alert'));
          expect(await fixture.db.select(fixture.db.cookTimers).get(), isEmpty);
        },
      );
    }
  }
}
