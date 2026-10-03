import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/widgets/macro_rings.dart';
import 'package:hearth/app/widgets/minor_nutrient_bars.dart';
import 'package:hearth/data/auth/local_auth_gateway.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_contributors.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/day_screen.dart';
import 'package:hearth/features/plan/logged_details_sheet.dart';
import 'package:hearth/features/plan/nutrient_contributors_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

final DateTime _date = DateTime(2026, 9, 30);
const Macros _saved = Macros(
  kcal: 315,
  proteinG: 23,
  carbG: 41,
  fatG: 8.5,
  fiberG: 0,
  cholesterolMg: 10,
);
const MacroTargets _targets = MacroTargets(
  kcal: 2000,
  proteinG: 150,
  carbG: 200,
  fatG: 70,
);

Food _food({String name = 'Current oats', double kcal = 900}) => Food(
  name: name,
  id: 'current-oats',
  householdId: LocalAuthGateway.account.householdId,
  source: FoodSource.manual,
  servingOptions: <ServingOption>[
    aServing(
      id: 'current-serving',
      amount: 100,
      unit: Units.gram,
      macros: Macros(kcal: kcal, proteinG: 90, fiberG: 80),
    ),
  ],
);

List<MealPlanEntry> _entries({
  bool missingSnapshot = false,
  String id = 'frozen-oats',
}) => <MealPlanEntry>[
  MealPlanEntry(
    id: id,
    dayId: PlanRepository.dayIdFor(
      userId: LocalAuthGateway.account.userId,
      date: _date,
    ),
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: 'current-oats',
    // Deliberately different from the saved portion: opening a total must not
    // multiply its already-frozen nutrition by this value or a current food.
    servings: 9,
    isLogged: true,
    loggedAt: _date.add(const Duration(hours: 8)),
    macroSnapshot: missingSnapshot
        ? null
        : MacroSnapshot(
            label: 'Oats as logged',
            macros: _saved,
            servings: 1.5,
            capturedAt: _date.add(const Duration(hours: 8)),
            coverage: NutrientCoverage.ofOne(_saved),
          ),
  ),
  MealPlanEntry(
    id: 'planned-oats',
    dayId: PlanRepository.dayIdFor(
      userId: LocalAuthGateway.account.userId,
      date: _date,
    ),
    slot: MealSlot.dinner,
    refType: PlanRefType.food,
    refId: 'current-oats',
    servings: 1,
  ),
];

final NotifierProvider<_User, String> _userProvider =
    NotifierProvider<_User, String>(_User.new);

class _User extends Notifier<String> {
  @override
  String build() => LocalAuthGateway.account.userId;
  void select(String user) => state = user;
}

final NotifierProvider<_Household, String> _householdProvider =
    NotifierProvider<_Household, String>(_Household.new);

class _Household extends Notifier<String> {
  @override
  String build() => LocalAuthGateway.account.householdId;
  void select(String household) => state = household;
}

enum _LifetimeChange {
  person,
  household,
  repository,
  personAndBack,
  householdAndBack,
}

class _Session {
  const _Session(this.db, this.container);
  final HearthDatabase db;
  final ProviderContainer container;
}

Future<_Session> _open(
  WidgetTester tester, {
  bool expanded = false,
  bool targets = true,
  List<MealPlanEntry>? entries,
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  Stream<List<Food>>? foodStream,
  Map<DateTime, List<MealPlanEntry>> weekEntries =
      const <DateTime, List<MealPlanEntry>>{},
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    size: size,
    textScale: scale,
    brightness: brightness,
    viewPadding: size.width <= 320
        ? const EdgeInsets.only(top: 24, bottom: 34)
        : const EdgeInsets.only(top: 47, bottom: 34),
    launchTarget: LaunchTarget.today,
    selectedDate: _date,
    foods: <Food>[_food()],
    foodStream: foodStream,
    weekEntries: weekEntries,
    readPlanEntriesFromStore: true,
    targets: targets ? _targets : null,
    extraOverrides: <Object>[
      bootDaySummaryExpandedProvider.overrideWithValue(expanded),
      currentUserIdProvider.overrideWith((Ref ref) => ref.watch(_userProvider)),
      currentHouseholdIdProvider.overrideWith(
        (Ref ref) => ref.watch(_householdProvider),
      ),
    ],
  );
  final PlanStore plans = PlanStore(db);
  final List<MealPlanEntry> saved = entries ?? _entries();
  if (saved.isNotEmpty) {
    await plans.ensureDay(
      userId: LocalAuthGateway.account.userId,
      date: _date,
      idFactory: () => saved.first.dayId,
      updatedAt: _date,
    );
    for (final MealPlanEntry entry in saved) {
      await plans.upsertEntry(entry, updatedAt: _date);
    }
  }
  await pumpFrames(tester, frames: 16);
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(DayScreen)),
  );
  container.invalidate(dayEntriesProvider);
  await pumpFrames(tester, frames: 16);
  return _Session(db, container);
}

Finder _total(SupportedNutrient nutrient) => find.byKey(
  ValueKey<String>(
    '${nutrient.minor == null ? 'macro' : 'minor'}-total-${nutrient.name}',
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await pumpFrames(tester, frames: 16);
}

NutrientContributorsScreen _receipt(WidgetTester tester) =>
    tester.widget<NutrientContributorsScreen>(
      find.byType(NutrientContributorsScreen),
    );

void main() {
  for (final bool expanded in <bool>[false, true]) {
    testWidgets(
      '${expanded ? 'expanded' : 'compact'} Day: seven accessible totals open '
      'the matching frozen receipt without including planned meals',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final _Session session = await _open(tester, expanded: expanded);
        final List<MealPlanEntryRow> before = await session.db
            .select(session.db.mealPlanEntries)
            .get();
        for (final SupportedNutrient nutrient in SupportedNutrient.values) {
          final Finder total = _total(nutrient);
          await tester.ensureVisible(total);
          await pumpFrames(tester);
          final SemanticsNode node = tester.getSemantics(total);
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(node.hint, 'Show logged meals contributing to this total');
          expect(tester.getSize(total).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(total).height, greaterThanOrEqualTo(48));
          await _tap(tester, total);
          final DailyNutrientContributors receipt = _receipt(tester)
              .contributors;
          expect(receipt.nutrient, nutrient);
          expect(receipt.date, _date);
          expect(
            receipt.entries.map((MealPlanEntry entry) => entry.id),
            <String>['frozen-oats'],
          );
          expect(receipt.knownTotal, nutrient.savedAmount(_saved));
          expect(receipt.entries.single.macroSnapshot!.servings, 1.5);
          await _tap(
            tester,
            find.byKey(const ValueKey<String>('nutrient-contributors-back')),
          );
          expect(find.byType(DayScreen), findsOneWidget);
        }
        expect(
          await session.db.select(session.db.mealPlanEntries).get(),
          before,
        );
        expect(
          await session.db.select(session.db.pendingWrites).get(),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      '${expanded ? 'expanded' : 'compact'} Day: targets and Details/Less '
      'remain separate from the total actions',
      (WidgetTester tester) async {
        await _open(tester, expanded: expanded);
        await _tap(tester, find.text('This week’s targets · Change'));
        expect(find.byType(NutrientContributorsScreen), findsNothing);
        expect(find.text('Use these targets each new week'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await pumpFrames(tester, frames: 16);
        await _tap(tester, find.text(expanded ? 'Less' : 'Details'));
        expect(
          find.byType(MacroRings),
          expanded ? findsNothing : findsOneWidget,
        );
        expect(
          find.byType(MinorNutrientBars),
          expanded ? findsNothing : findsOneWidget,
        );
        expect(find.byType(NutrientContributorsScreen), findsNothing);
        await _tap(tester, _total(SupportedNutrient.protein));
        expect(
          _receipt(tester).contributors.nutrient,
          SupportedNutrient.protein,
        );
      },
    );

    for (final bool empty in <bool>[true, false]) {
      testWidgets('${expanded ? 'expanded' : 'compact'} Day: '
          '${empty ? 'empty' : 'missing snapshot'} totals still explain gaps', (
        WidgetTester tester,
      ) async {
        await _open(
          tester,
          expanded: expanded,
          targets: false,
          entries: empty ? <MealPlanEntry>[] : _entries(missingSnapshot: true),
        );
        for (final SupportedNutrient nutrient in <SupportedNutrient>[
          SupportedNutrient.calories,
          SupportedNutrient.fiber,
        ]) {
          await _tap(tester, _total(nutrient));
          final DailyNutrientContributors receipt = _receipt(tester)
              .contributors;
          expect(receipt.knownTotal, isNull);
          expect(receipt.entries, empty ? isEmpty : hasLength(1));
          if (!empty) {
            expect(
              receipt.missingInformation.single.gap,
              NutrientInformationGap.snapshotUnavailable,
            );
          }
          await _tap(
            tester,
            find.byKey(const ValueKey<String>('nutrient-contributors-back')),
          );
        }
        expect(find.text('Set targets'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Day opens frozen details even after the current food changes', (
    WidgetTester tester,
  ) async {
    final StreamController<List<Food>> foods = StreamController<List<Food>>();
    addTearDown(foods.close);
    foods.add(<Food>[_food()]);
    final _Session session = await _open(tester, foodStream: foods.stream);
    await _tap(tester, _total(SupportedNutrient.calories));
    final Food changed = _food(name: 'Edited recipe source', kcal: 2000);
    await FoodStore(session.db).upsert(changed, updatedAt: DateTime(2026, 10));
    foods.add(<Food>[changed]);
    await pumpFrames(tester, frames: 16);
    expect(_receipt(tester).contributors.knownTotal, 315);
    expect(
      _receipt(tester).contributors.entries.single.macroSnapshot!.label,
      'Oats as logged',
    );
    await _tap(
      tester,
      find.byKey(const ValueKey<String>('contributor-known-open-frozen-oats')),
    );
    expect(find.byType(LoggedDetailsSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LoggedDetailsSheet),
        matching: find.text('Oats as logged'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LoggedDetailsSheet>(find.byType(LoggedDetailsSheet))
          .entry
          .macroSnapshot!
          .macros,
      _saved,
    );
    expect(find.text('Edited recipe source'), findsNothing);
    expect(await session.db.select(session.db.pendingWrites).get(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Day receipt keeps the selected date it was opened from', (
    WidgetTester tester,
  ) async {
    final _Session session = await _open(tester);
    await _tap(tester, _total(SupportedNutrient.calories));
    session.container.read(selectedDateProvider.notifier).shiftDays(1);
    await pumpFrames(tester, frames: 16);
    expect(_receipt(tester).contributors.date, _date);
    expect(_receipt(tester).contributors.knownTotal, 315);
    await _tap(
      tester,
      find.byKey(const ValueKey<String>('nutrient-contributors-back')),
    );
    await _tap(tester, _total(SupportedNutrient.calories));
    expect(_receipt(tester).contributors.date, DateTime(2026, 10, 1));
    expect(_receipt(tester).contributors.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final bool expanded in <bool>[false, true]) {
    testWidgets(
      '${expanded ? 'expanded' : 'compact'} captured Day action rejects a repainted household round trip',
      (WidgetTester tester) async {
        final _Session session = await _open(tester, expanded: expanded);
        final VoidCallback oldAction = tester
            .widget<Semantics>(_total(SupportedNutrient.calories))
            .properties
            .onTap!;
        session.container
            .read(_householdProvider.notifier)
            .select('another-household');
        await pumpFrames(tester, frames: 16);
        session.container
            .read(_householdProvider.notifier)
            .select(LocalAuthGateway.account.householdId);
        await pumpFrames(tester, frames: 16);
        oldAction();
        await pumpFrames(tester, frames: 16);
        expect(find.byType(NutrientContributorsScreen), findsNothing);
        await _tap(tester, _total(SupportedNutrient.calories));
        expect(_receipt(tester).contributors.knownTotal, 315);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${expanded ? 'expanded' : 'compact'} held Day action captures the date displayed at press',
      (WidgetTester tester) async {
        final _Session session = await _open(tester, expanded: expanded);
        final Finder total = _total(SupportedNutrient.calories);
        await tester.ensureVisible(total);
        await pumpFrames(tester);
        final TestGesture press = await tester.startGesture(
          tester.getCenter(total),
        );
        session.container.read(selectedDateProvider.notifier).shiftDays(1);
        await tester.idle();
        await press.up();
        await pumpFrames(tester, frames: 16);
        expect(_receipt(tester).contributors.date, _date);
        expect(_receipt(tester).contributors.knownTotal, 315);
        expect(tester.takeException(), isNull);
      },
    );

    for (final _LifetimeChange change in _LifetimeChange.values) {
      testWidgets(
        '${expanded ? 'expanded' : 'compact'} held Day total rejects ${change.name} before repaint',
        (WidgetTester tester) async {
          final _Session session = await _open(tester, expanded: expanded);
          final Finder total = _total(SupportedNutrient.calories);
          await tester.ensureVisible(total);
          await pumpFrames(tester);
          final TestGesture press = await tester.startGesture(
            tester.getCenter(total),
          );
          switch (change) {
            case _LifetimeChange.person:
            case _LifetimeChange.personAndBack:
              session.container
                  .read(_userProvider.notifier)
                  .select('another-person');
              await tester.idle();
              expect(
                session.container.read(currentUserIdProvider),
                'another-person',
              );
              if (change == _LifetimeChange.personAndBack) {
                session.container
                    .read(_userProvider.notifier)
                    .select(LocalAuthGateway.account.userId);
              }
            case _LifetimeChange.household:
            case _LifetimeChange.householdAndBack:
              session.container
                  .read(_householdProvider.notifier)
                  .select('another-household');
              await tester.idle();
              expect(
                session.container.read(currentHouseholdIdProvider),
                'another-household',
              );
              if (change == _LifetimeChange.householdAndBack) {
                session.container
                    .read(_householdProvider.notifier)
                    .select(LocalAuthGateway.account.householdId);
              }
            case _LifetimeChange.repository:
              final PlanRepository before = session.container.read(
                planRepositoryProvider,
              );
              session.container.invalidate(planRepositoryProvider);
              await tester.idle();
              expect(
                session.container.read(planRepositoryProvider),
                isNot(same(before)),
              );
          }
          // Provider changes have settled, but the held action still belongs to
          // the old rendered lifetime, even when the IDs have returned to A.
          await tester.idle();
          await press.up();
          await pumpFrames(tester, frames: 16);
          expect(find.byType(NutrientContributorsScreen), findsNothing);
          if (change == _LifetimeChange.person) {
            expect(find.text('Oats as logged'), findsNothing);
          }
          expect(
            await session.db.select(session.db.pendingWrites).get(),
            isEmpty,
          );

          // The newly rendered action remains usable after the stale press was
          // discarded; only its own current person/date can supply the receipt.
          await _tap(tester, _total(SupportedNutrient.calories));
          expect(_receipt(tester).contributors.date, _date);
          if (change == _LifetimeChange.person) {
            expect(_receipt(tester).contributors.entries, isEmpty);
          } else {
            expect(_receipt(tester).contributors.knownTotal, 315);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a Day receipt expires when the active person changes', (
    WidgetTester tester,
  ) async {
    final _Session session = await _open(tester);
    await _tap(tester, _total(SupportedNutrient.calories));
    session.container.read(_userProvider.notifier).select('another-person');
    await pumpFrames(tester, frames: 16);
    expect(find.byType(NutrientContributorsScreen), findsNothing);
    expect(
      find.text('This view expired. Open the day and try again.'),
      findsOneWidget,
    );
    session.container
        .read(_userProvider.notifier)
        .select(LocalAuthGateway.account.userId);
    await pumpFrames(tester, frames: 16);
    expect(find.byType(NutrientContributorsScreen), findsNothing);
    expect(find.text('Oats as logged'), findsNothing);
    expect(await session.db.select(session.db.pendingWrites).get(), isEmpty);
  });

  testWidgets(
    'missing snapshot does not substitute current food calories in Day totals',
    (WidgetTester tester) async {
      await _open(tester, entries: _entries(missingSnapshot: true));
      final bool claimedLiveCalories = find
          .bySemanticsLabel(RegExp('8100 of 2000 calories'))
          .evaluate()
          .isNotEmpty;
      await _tap(tester, _total(SupportedNutrient.calories));
      expect(_receipt(tester).contributors.knownTotal, isNull);
      expect(
        _receipt(tester).contributors.missingInformation.single.gap,
        NutrientInformationGap.snapshotUnavailable,
      );
      expect(
        claimedLiveCalories,
        isFalse,
        reason:
            'Day must not claim the current food’s 900 kcal × 9 servings '
            'as historical intake when the receipt has no saved nutrition.',
      );
    },
  );

  testWidgets('Week distinguishes missing saved nutrition from a logged zero', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      weekEntries: <DateTime, List<MealPlanEntry>>{
        _date: _entries(missingSnapshot: true),
      },
    );
    final SweepTools tools = SweepTools(tester);
    await tools.planView('Week');
    await tools.weekContent('Nutrition');
    expect(
      find.bySemanticsLabel(
        RegExp('Wednesday 9/30.*Saved nutrition unavailable'),
      ),
      findsOneWidget,
    );
    expect(find.text('logged as nothing'), findsNothing);
    expect(find.text('Nothing logged this week yet.'), findsNothing);
    await tools.reach(find.bySemanticsLabel(RegExp('Wednesday 9/30')));
    final DayProgress progress = tester
        .widget<MacroRings>(find.byType(MacroRings))
        .progress;
    expect(progress.availability, SavedNutritionAvailability.unavailable);
    for (final MacroProgress macro in progress.all) {
      expect(macro.hasKnownIntake, isFalse);
      expect(macro.remaining, isNull);
    }
  });

  testWidgets(
    'Week Meals names unavailable saved nutrition on the logged row',
    (WidgetTester tester) async {
      await _open(
        tester,
        weekEntries: <DateTime, List<MealPlanEntry>>{
          _date: <MealPlanEntry>[
            _entries(missingSnapshot: true).first
                .copyWith(slot: MealSlot.dinner),
          ],
        },
      );
      await SweepTools(tester).planView('Week');
      expect(
        find.textContaining('Saved nutrition unavailable'),
        findsOneWidget,
      );
    },
  );

  for (final bool expanded in <bool>[false, true]) {
    testWidgets(
      '${expanded ? 'expanded' : 'compact'} Day qualifies mixed saved totals and meal rows',
      (WidgetTester tester) async {
        await _open(
          tester,
          expanded: expanded,
          entries: <MealPlanEntry>[
            _entries().first,
            _entries(missingSnapshot: true, id: 'missing-meal').first,
          ],
        );
        expect(find.text('Known subtotal · incomplete'), findsOneWidget);
        final Semantics calories = tester.widget<Semantics>(
          _total(SupportedNutrient.calories),
        );
        expect(calories.properties.label, contains('315'));
        expect(calories.properties.label, contains('known subtotal'));
        expect(calories.properties.label, isNot(contains('of 2000')));
        expect(find.textContaining('1685 left'), findsNothing);
        final Finder meal = find.byKey(
          const ValueKey<String>('meal-open-missing-meal'),
        );
        await tester.scrollUntilVisible(
          meal,
          250,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 30,
        );
        final Semantics row = tester.widget<Semantics>(meal);
        expect(row.properties.label, contains('Saved nutrition unavailable'));
        expect(row.properties.label, isNot(contains('0 kcal')));
        await _tap(tester, _total(SupportedNutrient.calories));
        final DailyNutrientContributors receipt = _receipt(tester).contributors;
        expect(receipt.knownTotal, 315);
        expect(receipt.knownContributors, hasLength(1));
        expect(receipt.missingInformation, hasLength(1));
      },
    );

    testWidgets(
      '${expanded ? 'expanded' : 'compact'} Day never calls unavailable intake zero or untouched',
      (WidgetTester tester) async {
        await _open(
          tester,
          expanded: expanded,
          entries: <MealPlanEntry>[_entries(missingSnapshot: true).first],
        );
        expect(find.text('Nothing logged yet'), findsNothing);
        for (final SupportedNutrient nutrient in SupportedNutrient.values) {
          final Semantics action = tester.widget<Semantics>(_total(nutrient));
          expect(
            action.properties.label,
            contains('saved nutrition unavailable'),
          );
          expect(action.properties.label, isNot(contains('consumed')));
          expect(action.properties.label, isNot(contains('0 of')));
        }
        expect(find.textContaining('2000 left'), findsNothing);
      },
    );
  }

  testWidgets('Week displays the known subtotal and discloses excluded days', (
    WidgetTester tester,
  ) async {
    final DateTime yesterday = DateTime(2026, 9, 29);
    await _open(
      tester,
      weekEntries: <DateTime, List<MealPlanEntry>>{
        _date: <MealPlanEntry>[
          _entries().first,
          _entries(missingSnapshot: true, id: 'missing-meal').first,
        ],
        yesterday: <MealPlanEntry>[
          MealPlanEntry(
            id: 'saved-zero',
            dayId: 'saved-zero-day',
            slot: MealSlot.dinner,
            refType: PlanRefType.food,
            refId: 'current-oats',
            servings: 1,
            isLogged: true,
            macroSnapshot: MacroSnapshot(
              label: 'Explicit logged zero',
              macros: Macros.zero,
              servings: 1,
              capturedAt: yesterday,
            ),
          ),
        ],
      },
    );
    final SweepTools tools = SweepTools(tester);
    await tools.planView('Week');
    await tools.weekContent('Nutrition');
    expect(
      find.bySemanticsLabel(
        RegExp('Wednesday 9/30.*Known subtotal 315 kcal.*incomplete'),
      ),
      findsOneWidget,
    );
    expect(find.text('logged as nothing'), findsOneWidget);
    await tools.reach(find.bySemanticsLabel(RegExp('Wednesday 9/30')));
    final DayProgress progress = tester
        .widget<MacroRings>(find.byType(MacroRings))
        .progress;
    expect(progress.availability, SavedNutritionAvailability.partial);
    expect(progress.consumed.kcal, 315);
    expect(progress.calories.remaining, isNull);
    await tools.bring(find.text('Daily average'));
    expect(
      find.textContaining(
        'over 1 fully saved day · 1 incomplete day excluded · 5 not logged',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final Brightness brightness in Brightness.values) {
    for (final bool expanded in <bool>[false, true]) {
      testWidgets(
        'small 3x ${brightness.name} ${expanded ? 'expanded' : 'compact'} '
        'Day: all seven actions, target change, and layout switch are reachable',
        (WidgetTester tester) async {
          await _open(
            tester,
            expanded: expanded,
            size: const Size(320, 568),
            scale: 3,
            brightness: brightness,
          );
          for (final SupportedNutrient nutrient in SupportedNutrient.values) {
            await _tap(tester, _total(nutrient));
            expect(_receipt(tester).contributors.nutrient, nutrient);
            expect(tester.takeException(), isNull);
            await _tap(
              tester,
              find.byKey(const ValueKey<String>('nutrient-contributors-back')),
            );
          }
          for (final Finder control in <Finder>[
            find.text('This week’s targets · Change'),
            find.text(expanded ? 'Less' : 'Details'),
          ]) {
            await tester.ensureVisible(control);
            await pumpFrames(tester);
            expect(control.hitTestable(), findsOneWidget);
          }
          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(DayScreen)))
                .scale(16),
            48,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
