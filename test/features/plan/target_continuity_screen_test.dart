import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/target_schedule.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/features/plan/day_screen.dart';
import 'package:hearth/features/plan/macro_targets_sheet.dart';
import 'package:hearth/features/plan/week_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/swept_surfaces.dart' show SweepTools;

final DateTime _week = DateTime(2026, 9, 28);
const MacroTargets _original = MacroTargets(
  kcal: 2100.75,
  proteinG: 162.5,
  carbG: 230.25,
  fatG: 70.125,
  fiberG: null,
  sodiumMg: 0,
  cholesterolMg: 125.5,
);
const MacroTargets _edited = MacroTargets(
  kcal: 1999.125,
  proteinG: 163.25,
  carbG: 240.5,
  fatG: 71.625,
  fiberG: 0,
  sodiumMg: null,
  cholesterolMg: 99.875,
);
const List<String> _labels = <String>[
  'kcal',
  'Protein',
  'Carbs',
  'Fat',
  'Fibre g',
  'Sodium mg',
  'Chol. mg',
];

void main() {
  testWidgets('saving retains the week that the editor opened for', (
    WidgetTester tester,
  ) async {
    final DateTime openingWeek = DateTime(2026, 8, 31);
    final _Session session = await _pump(tester, selected: openingWeek);
    await session.repository.setTargets(openingWeek, _original);
    // Move before the sheet's first frame as well as before Save: capture
    // belongs to opening the sheet, not to a later build of its route.
    session.open(tester);
    session.container.read(selectedDateProvider.notifier).select(_week);
    await pumpFrames(tester, frames: 12);
    expect(find.text('August 31 – September 6, 2026'), findsOneWidget);
    await _tap(tester, 'Save targets');

    expect(
      (await session.database.select(session.database.macroTargets).get())
          .single
          .weekStartDate,
      openingWeek,
    );
    expect(await session.repository.targetsFor(openingWeek), _original);
    expect(await session.repository.targetsFor(_week), isNull);
  });

  testWidgets(
    'new current-week targets carry forward only after reviewed Save',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      await _open(tester, session);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(find.text('September 28 – October 4, 2026'), findsOneWidget);
      expect(find.text('Your daily targets, private to you.'), findsOneWidget);
      expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
      await _enterEdited(tester);
      await _tap(tester, 'Save targets');

      expect(await session.repository.targetsFor(_week), _edited);
      final ResolvedTargets next = await session.repository.targetResolutionFor(
        addDays(_week, 7),
      );
      expect(next.source, TargetSource.ongoing);
      expect(next.targets, _edited);
      expect(
        await session.database.select(session.database.macroTargets).get(),
        isEmpty,
      );
    },
  );

  testWidgets('turning off carry-forward saves only the named week', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await _open(tester, session);
    await _tap(tester, 'Use these targets each new week');
    await _enterEdited(tester);
    await _tap(tester, 'Save targets');

    expect(
      (await session.repository.targetResolutionFor(_week)).source,
      TargetSource.exactWeek,
    );
    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
  });

  testWidgets(
    'opening legacy targets preserves all seven values without opting in',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      await session.repository.setTargets(_week, _original);
      await _open(tester, session);
      await _expectOriginalFields(tester);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await _tap(tester, 'Cancel');

      expect(await session.repository.targetsFor(_week), _original);
      expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
    },
  );

  testWidgets(
    'reviewed enabling updates the legacy row and ongoing values together',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      await session.repository.setTargets(_week, _original);
      await _open(tester, session);
      await _enterEdited(tester);
      await _tap(tester, 'Save targets');

      expect(await session.repository.targetsFor(_week), _edited);
      expect(await session.repository.targetsFor(addDays(_week, 7)), _edited);
      await _open(tester, session);
      expect(
        _ongoingSelection(tester),
        isFalse,
        reason:
            'the existing exact row remains an explicit week-specific choice',
      );
      expect(
        find.text(
          'This week has its own targets. Ongoing targets are enabled.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('ongoing targets default to From this week onward', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await _open(tester, session);
    expect(_ongoingSelection(tester), isTrue);
    await _expectOriginalFields(tester);
    await _enterEdited(tester);
    await _tap(tester, 'Save targets');

    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 14)), _edited);
  });

  testWidgets(
    'This week only makes an exception without changing ongoing targets',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      await session.repository.setOngoingTargets(_week, _original);
      await _open(tester, session);
      await _tap(tester, 'This week only');
      await _enterEdited(tester);
      await _tap(tester, 'Save targets');

      expect(await session.repository.targetsFor(_week), _edited);
      expect(await session.repository.targetsFor(addDays(_week, 7)), _original);
      await _open(tester, session);
      expect(_ongoingSelection(tester), isFalse);
    },
  );

  testWidgets('an existing exception defaults to This week only', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await session.repository.setTargets(_week, _edited);
    await _open(tester, session);
    expect(_ongoingSelection(tester), isFalse);
    await _tap(tester, 'Save targets');

    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 7)), _original);
  });

  testWidgets('an exception can explicitly become From this week onward', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await session.repository.setTargets(_week, _edited);
    await _open(tester, session);
    await _tap(tester, 'From this week onward');
    await _tap(tester, 'Save targets');

    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 7)), _edited);
  });

  for (final int offset in <int>[-7, 7]) {
    testWidgets(
      '${offset < 0 ? 'past' : 'future'} edits stay in their named week',
      (WidgetTester tester) async {
        final DateTime selected = addDays(_week, offset);
        final _Session session = await _pump(tester, selected: selected);
        await session.repository.setOngoingTargets(_week, _original);
        await session.repository.setTargets(selected, _original);
        await _open(tester, session);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.byType(RadioGroup<bool>), findsNothing);
        expect(
          find.text('Stop carrying forward after this week'),
          findsNothing,
        );
        expect(
          find.textContaining('Changes apply to these dates only.'),
          findsOneWidget,
        );
        await _enterEdited(tester);
        await _tap(tester, 'Save targets');

        expect(await session.repository.targetsFor(selected), _edited);
        expect(await session.repository.targetsFor(_week), _original);
        expect(
          await session.repository.targetsFor(addDays(_week, 14)),
          _original,
        );
      },
    );
  }

  testWidgets('Stop keeps this week and future explicit exceptions', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await session.repository.setTargets(addDays(_week, 14), _edited);
    await _open(tester, session);
    await _tap(tester, 'Stop carrying forward after this week');

    expect(await session.repository.targetsFor(_week), _original);
    expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
    expect(await session.repository.targetsFor(addDays(_week, 14)), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 21)), isNull);
    expect(
      (await session.repository.targetResolutionFor(_week))
          .ongoingBoundary!
          .isStopped,
      isTrue,
    );
  });

  testWidgets('Stop cannot discard unsaved target changes', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await _open(tester, session);
    await tester.enterText(_field('kcal'), '1800');
    await _reach(tester, find.text('Stop carrying forward after this week'));
    final TextButton stop = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Stop carrying forward after this week'),
    );
    expect(stop.onPressed, isNull);
    expect(
      find.text('Save your target changes before stopping carry-forward.'),
      findsOneWidget,
    );
    expect(await session.repository.targetsFor(addDays(_week, 7)), _original);
  });

  testWidgets('Monday rollover cannot backdate an ongoing save', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    session.clock.now = DateTime(2026, 10, 4, 23, 59);
    await _open(tester, session);
    await _enterEdited(tester);
    await _reach(tester, find.text('Save targets'));
    session.clock.now = DateTime(2026, 10, 5, 0, 1);
    // No rebuild before tapping the still-visible reviewed action.
    await tester.tap(find.text('Save targets'));
    await pumpFrames(tester, frames: 16);
    expect(find.textContaining('A new week has started.'), findsOneWidget);
    expect(await session.repository.targetsFor(_week), isNull);
    expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
    await _tap(tester, 'Use these targets each new week');
    await _tap(tester, 'Save targets');
    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
  });

  testWidgets('Monday rollover cannot backdate Stop', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await _open(tester, session);
    await _reach(tester, find.text('Stop carrying forward after this week'));
    session.clock.now = DateTime(2026, 10, 5, 0, 1);
    await tester.tap(find.text('Stop carrying forward after this week'));
    await pumpFrames(tester);
    expect(
      (await session.repository.targetResolutionFor(addDays(_week, 7))).source,
      TargetSource.ongoing,
    );
    await _reach(tester, find.textContaining('A new week has started.'));
    expect(find.textContaining('A new week has started.'), findsOneWidget);
  });

  testWidgets('account changes hide the prior values and prevent writing', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await _open(tester, session);
    session.container.read(_accountProvider.notifier).change('other-user');
    await pumpFrames(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('The account changed.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save targets'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Stop carrying forward after this week'), findsNothing);
    expect(await session.repository.targetsFor(_week), _original);
    expect(
      await PlanStore(session.database)
          .targetsFor(userId: 'other-user', date: _week),
      isNull,
    );
  });

  testWidgets('a delayed initial load remains attached to its opening week', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    final Completer<ResolvedTargets> loading = Completer<ResolvedTargets>();
    session.repository.loading = loading;
    await _open(tester, session);
    expect(find.byType(TextField), findsNothing);
    session.container
        .read(selectedDateProvider.notifier)
        .select(addDays(_week, 7));
    loading.complete(
      resolveTargetsForWeek(
        userId: 'test-user',
        date: _week,
        exactWeeks: <ExactWeekTarget>[
          ExactWeekTarget(
            userId: 'test-user',
            weekStart: _week,
            targets: _original,
          ),
        ],
      ),
    );
    await pumpFrames(tester);
    expect(find.text('September 28 – October 4, 2026'), findsOneWidget);
    await _expectOriginalFields(tester);
  });

  testWidgets(
    'a refresh after an empty load cannot overwrite typed values or scope',
    (WidgetTester tester) async {
      final _Session session = await _pump(tester);
      await _open(tester, session);
      await _tap(tester, 'Use these targets each new week');
      await _enterEdited(tester);
      await session.repository.setTargets(_week, _original);
      session.container.invalidate(targetResolutionProvider(_week));
      await pumpFrames(tester);
      await _reach(tester, _field('kcal'));
      expect(
        tester.widget<TextField>(_field('kcal')).controller!.text,
        '1999.125',
      );
      await _reach(tester, find.byType(CheckboxListTile));
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await _tap(tester, 'Save targets');
      expect(await session.repository.targetsFor(_week), _edited);
      expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
    },
  );

  testWidgets('failed loading can be retried before editing', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    session.repository.failRead = true;
    await _open(tester, session);
    expect(
      find.text('Targets could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    session.repository.failRead = false;
    await _tap(tester, 'Retry');
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('a failed save retains every input and can be retried', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await _open(tester, session);
    await _enterEdited(tester);
    session.repository.failWrite = true;
    await _tap(tester, 'Save targets');
    expect(find.textContaining('Targets could not be saved.'), findsOneWidget);
    expect(await session.repository.targetsFor(_week), isNull);
    await _reach(tester, _field('kcal'));
    expect(
      tester.widget<TextField>(_field('kcal')).controller!.text,
      '1999.125',
    );
    session.repository.failWrite = false;
    await _tap(tester, 'Save targets');
    expect(await session.repository.targetsFor(_week), _edited);
    expect(await session.repository.targetsFor(addDays(_week, 7)), _edited);
  });

  testWidgets('invalid input cannot silently become a saved zero', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await _open(tester, session);
    await tester.enterText(_field('kcal'), 'NaN');
    await _tap(tester, 'Save targets');
    expect(
      find.textContaining('Enter a number of zero or more'),
      findsOneWidget,
    );
    expect(await session.repository.targetsFor(_week), isNull);
    await _reach(tester, _field('kcal'));
    expect(tester.widget<TextField>(_field('kcal')).controller!.text, 'NaN');
    await tester.enterText(_field('kcal'), '2000.25');
    await _tap(tester, 'Save targets');
    expect((await session.repository.targetsFor(_week))!.kcal, 2000.25);
  });

  testWidgets('a failed Stop stays recoverable with existing targets intact', (
    WidgetTester tester,
  ) async {
    final _Session session = await _pump(tester);
    await session.repository.setOngoingTargets(_week, _original);
    await _open(tester, session);
    session.repository.failWrite = true;
    await _tap(tester, 'Stop carrying forward after this week');
    await _reach(
      tester,
      find.textContaining('Carry-forward could not be stopped.'),
    );
    expect(
      find.textContaining('Carry-forward could not be stopped.'),
      findsOneWidget,
    );
    expect(await session.repository.targetsFor(addDays(_week, 7)), _original);
    session.repository.failWrite = false;
    await _tap(tester, 'Stop carrying forward after this week');
    expect(await session.repository.targetsFor(_week), _original);
    expect(await session.repository.targetsFor(addDays(_week, 7)), isNull);
  });

  testWidgets(
    'all controls remain reachable at 320 points, 3× text and a keyboard',
    (WidgetTester tester) async {
      final _Session session = await _pump(
        tester,
        size: const Size(320, 740),
        scale: 3,
      );
      await session.repository.setOngoingTargets(_week, _original);
      await _open(tester, session);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      for (final String label in _labels) {
        await _reach(tester, _field(label));
        expect(tester.getSize(_field(label)).width, greaterThan(200));
        expect(tester.takeException(), isNull);
      }
      await _reach(tester, find.text('Save targets'));
      expect(tester.takeException(), isNull);
      await _reach(tester, find.text('Stop carrying forward after this week'));
      expect(tester.takeException(), isNull);
      final SemanticsHandle semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    },
  );

  for (final bool weekScreen in <bool>[false, true]) {
    testWidgets(
      '${weekScreen ? 'Week' : 'Day'} identifies ongoing values and opens Change',
      (WidgetTester tester) async {
        final _Session session = await _pump(
          tester,
          screen: weekScreen ? const WeekScreen() : const DayScreen(),
        );
        await session.repository.setOngoingTargets(_week, _original);
        session.container.invalidate(targetResolutionProvider);
        await pumpFrames(tester, frames: 12);
        if (weekScreen) await SweepTools(tester).weekContent('Nutrition');
        final Finder action = find.text('Using ongoing targets · Change');
        await tester.scrollUntilVisible(
          action,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(action, findsOneWidget);
        expect(find.textContaining('Same as last week'), findsNothing);
        await tester.tap(action);
        await pumpFrames(tester, frames: 12);
        expect(find.text('Weekly targets'), findsOneWidget);
        expect(find.text('September 28 – October 4, 2026'), findsOneWidget);
      },
    );

    for (final bool differentUser in <bool>[false, true]) {
      testWidgets(
        '${weekScreen ? 'Week' : 'Day'} withholds stale targets from a different ${differentUser ? 'account' : 'week'}',
        (WidgetTester tester) async {
          final String userId = differentUser ? 'other-user' : 'test-user';
          final DateTime date = differentUser ? _week : addDays(_week, -7);
          await _pump(
            tester,
            screen: weekScreen ? const WeekScreen() : const DayScreen(),
            targetResolution: resolveTargetsForWeek(
              userId: userId,
              date: date,
              boundaries: <OngoingTargetBoundary>[
                OngoingTargetBoundary.active(
                  userId: userId,
                  weekStart: date,
                  targets: _original,
                ),
              ],
            ),
          );
          if (weekScreen) await SweepTools(tester).weekContent('Nutrition');
          await tester.scrollUntilVisible(
            find.text('Set targets'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Set targets'), findsOneWidget);
          expect(find.text('Using ongoing targets · Change'), findsNothing);
          expect(find.textContaining('2101'), findsNothing);
        },
      );
    }
  }
}

Finder _field(String label) => find.byKey(ValueKey<String>('target-$label'));
Finder get _editorScroll => find
    .descendant(
      of: find.byKey(const ValueKey<String>('macro-targets-editor')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _reach(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 180, scrollable: _editorScroll);
  await tester.ensureVisible(finder);
  await pumpFrames(tester, frames: 2);
}

Future<void> _tap(WidgetTester tester, String text) async {
  await _reach(tester, find.text(text));
  await tester.tap(find.text(text));
  await pumpFrames(tester, frames: 16);
}

Future<void> _open(WidgetTester tester, _Session session) async {
  session.open(tester);
  await pumpFrames(tester, frames: 12);
}

bool? _ongoingSelection(WidgetTester tester) =>
    tester.widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>)).groupValue;

Future<void> _enterEdited(WidgetTester tester) async {
  const List<String> values = <String>[
    '1999.125',
    '163.25',
    '240.5',
    '71.625',
    '0',
    '',
    '99.875',
  ];
  for (int i = 0; i < values.length; i++) {
    await _reach(tester, _field(_labels[i]));
    await tester.enterText(_field(_labels[i]), values[i]);
  }
}

Future<void> _expectOriginalFields(WidgetTester tester) async {
  const List<String> values = <String>[
    '2100.75',
    '162.5',
    '230.25',
    '70.125',
    '',
    '0',
    '125.5',
  ];
  for (int i = 0; i < values.length; i++) {
    await _reach(tester, _field(_labels[i]));
    expect(
      tester.widget<TextField>(_field(_labels[i])).controller!.text,
      values[i],
    );
  }
}

final _accountProvider = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'test-user';
  void change(String userId) => state = userId;
}

class _Selected extends SelectedDate {
  _Selected(this.initial);
  final DateTime initial;
  @override
  DateTime build() => initial;
}

class _Clock {
  DateTime now = DateTime(2026, 10, 1);
}

class _Session {
  _Session(this.database, this.repository, this.container, this.clock);
  final HearthDatabase database;
  final _ControlledRepository repository;
  final ProviderContainer container;
  final _Clock clock;
  void open(WidgetTester tester) => unawaited(
    showMacroTargetsSheet(
      tester.element(find.byType(Scaffold).first),
      clock: () => clock.now,
    ),
  );
}

class _ControlledRepository extends PlanRepository {
  _ControlledRepository(HearthDatabase db, _Clock clock)
    : super(
        database: db,
        store: PlanStore(db),
        queue: PendingWriteStore(db),
        userId: 'test-user',
        clock: () => clock.now,
      );
  bool failRead = false;
  bool failWrite = false;
  Completer<ResolvedTargets>? loading;
  @override
  Future<ResolvedTargets> targetResolutionFor(DateTime date) async {
    if (failRead) throw StateError('test read failure');
    if (loading != null) return loading!.future;
    return super.targetResolutionFor(date);
  }

  @override
  Future<void> setTargets(DateTime date, MacroTargets targets) async {
    if (failWrite) throw StateError('test write failure');
    await super.setTargets(date, targets);
  }

  @override
  Future<void> setOngoingTargets(DateTime date, MacroTargets targets) async {
    if (failWrite) throw StateError('test write failure');
    await super.setOngoingTargets(date, targets);
  }

  @override
  Future<void> stopOngoingTargets(DateTime date) async {
    if (failWrite) throw StateError('test write failure');
    await super.stopOngoingTargets(date);
  }
}

Future<_Session> _pump(
  WidgetTester tester, {
  DateTime? selected,
  Size size = const Size(390, 1100),
  double scale = 1,
  Widget screen = const SizedBox(),
  ResolvedTargets? targetResolution,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  final _Clock clock = _Clock();
  final _ControlledRepository repository = _ControlledRepository(db, clock);
  final ProviderContainer container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith(
        (Ref ref) => ref.watch(_accountProvider),
      ),
      selectedDateProvider.overrideWith(() => _Selected(selected ?? _week)),
      planRepositoryProvider.overrideWith((Ref ref) {
        final String userId = ref.watch(currentUserIdProvider);
        return userId == 'test-user'
            ? repository
            : PlanRepository(
                database: db,
                store: PlanStore(db),
                queue: PendingWriteStore(db),
                userId: userId,
                clock: () => clock.now,
              );
      }),
      planChangesProvider.overrideWith((Ref ref) => const Stream<void>.empty()),
      targetChangesProvider.overrideWith(
        (Ref ref) => const Stream<int>.empty(),
      ),
      if (targetResolution != null)
        dayTargetResolutionProvider.overrideWith(
          (Ref ref) async => targetResolution,
        ),
      dayEntriesProvider.overrideWith((Ref ref) async => <MealPlanEntry>[]),
      weekEntriesProvider.overrideWith(
        (Ref ref) async => <DateTime, List<MealPlanEntry>>{},
      ),
      recipeLibraryProvider.overrideWith(
        (Ref ref) => Stream<List<Recipe>>.value(<Recipe>[]),
      ),
      foodLibraryProvider.overrideWith(
        (Ref ref) => Stream<List<Food>>.value(<Food>[]),
      ),
      bootDaySummaryExpandedProvider.overrideWithValue(false),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: HearthTheme.light(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await pumpFrames(tester, frames: 8);
  return _Session(db, repository, container, clock);
}
