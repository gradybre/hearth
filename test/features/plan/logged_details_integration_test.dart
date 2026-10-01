import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/logged_details_sheet.dart';

import '../../support/app_harness.dart';
import '../../support/swept_surfaces.dart';

const String _entryId = 'saved-yogurt';
const String _foodId = 'yogurt';
const String _frozenName = 'Yogurt as eaten';
const String _currentName = 'Today\'s changed yogurt';
const ValueKey<String> _openKey = ValueKey<String>('meal-open-$_entryId');
const ValueKey<String> _logKey = ValueKey<String>('meal-log-$_entryId');
final DateTime _recordedAt = DateTime.utc(2026, 6, 2, 10, 35);
const Macros _savedNutrition = Macros(
  kcal: 250,
  proteinG: 25,
  carbG: 50,
  fatG: 12.5,
  fiberG: 5,
  sodiumMg: 100,
  cholesterolMg: 10,
);

ServingOption _originalPot() => ServingOption(
  id: 'pot',
  label: '170 g pot',
  amount: Quantity.of(170, Units.gram),
  macros: const Macros(
    kcal: 340,
    proteinG: 34,
    carbG: 68,
    fatG: 17,
    fiberG: 6.8,
    sodiumMg: 136,
    cholesterolMg: 13.6,
  ),
);

Food _currentFood({bool deleted = false}) => Food(
  id: _foodId,
  name: _currentName,
  source: FoodSource.manual,
  isDeleted: deleted,
  servingOptions: <ServingOption>[
    ServingOption(
      id: 'pot',
      label: '200 g pot',
      amount: Quantity.of(200, Units.gram),
      macros: const Macros(kcal: 999, proteinG: 90),
    ),
  ],
);

MealPlanEntry _logged({bool legacy = false}) {
  final double count = legacy ? 1.5 : 125 / 170;
  return MealPlanEntry(
    id: _entryId,
    dayId: 'saved-day',
    slot: MealSlot.breakfast,
    refType: PlanRefType.food,
    refId: _foodId,
    servings: count,
    servingOptionId: 'pot',
    isLogged: true,
    loggedAt: _recordedAt,
    macroSnapshot: MacroSnapshot(
      macros: _savedNutrition,
      servings: count,
      capturedAt: _recordedAt,
      label: _frozenName,
      coverage: const NutrientCoverage.allComplete(),
      loggedPortion: legacy
          ? null
          : LoggedPortion.tryCapture(
              amount: 125,
              unit: const PortionUnit.raw(Units.gram),
              servings: count,
              standard: _originalPot(),
            ),
    ),
  );
}

MealPlanEntry _planned({double count = 1.25, String? servingOptionId}) =>
    MealPlanEntry(
      id: _entryId,
      dayId: 'saved-day',
      slot: MealSlot.breakfast,
      refType: PlanRefType.food,
      refId: _foodId,
      servings: count,
      servingOptionId: servingOptionId,
    );

Future<HearthDatabase> _day(
  WidgetTester tester, {
  MealPlanEntry? entry,
  Food? food,
  double textScale = 1,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    launchTarget: LaunchTarget.today,
    size: const Size(320, 568),
    textScale: textScale,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    foods: <Food>[food ?? _currentFood()],
    entries: <MealPlanEntry>[entry ?? _logged()],
  );
  await SweepTools(tester).bring(find.byKey(_openKey));
  return db;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await SweepTools(tester).bring(target);
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await pumpFrames(tester);
  await tester.tap(target.hitTestable());
  await pumpFrames(tester, frames: 12);
  expect(tester.takeException(), isNull);
}

Future<void> _options(WidgetTester tester) =>
    _tap(tester, find.byTooltip(RegExp('^Edit ')).last);

Future<void> _details(WidgetTester tester) async {
  await _options(tester);
  expect(find.text('View logged details'), findsOneWidget);
  await _tap(tester, find.text('View logged details'));
  expect(find.byType(LoggedDetailsSheet), findsOneWidget);
}

Finder _savedText(String text) => find.descendant(
  of: find.byType(LoggedDetailsSheet),
  matching: find.text(text),
);

Future<void> _reachSavedText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    _savedText(text),
    160,
    maxScrolls: 60,
    scrollable: find.descendant(
      of: find.byType(LoggedDetailsSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await pumpFrames(tester);
  expect(_savedText(text).hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _pressSavedText(WidgetTester tester, String text) async {
  await _reachSavedText(tester, text);
  await tester.tap(_savedText(text).hitTestable());
  await pumpFrames(tester, frames: 12);
  expect(tester.takeException(), isNull);
}

Future<MealPlanEntry> _stored(HearthDatabase db) async =>
    PlanMapper.entryToDomain(
      (await db.select(db.mealPlanEntries).get()).single,
    );

void main() {
  testWidgets(
    'Day keeps 125 g and the saved name; its 3x details expose all seven values without a write',
    (WidgetTester tester) async {
      final HearthDatabase db = await _day(tester, textScale: 3);
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      final List<PendingWriteRow> pendingBefore = await db
          .select(db.pendingWrites)
          .get();
      expect(find.text(_frozenName), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_openKey),
          matching: find.textContaining('125 g'),
        ),
        findsOneWidget,
      );
      expect(find.text(_currentName), findsNothing);

      await _details(tester);
      for (final String value in <String>[
        _frozenName,
        '125 g',
        'Calories: 250 kcal',
        'Protein: 25 g',
        'Carbohydrate: 50 g',
        'Fat: 12.5 g',
        'Fibre: 5 g',
        'Sodium: 100 mg',
        'Cholesterol: 10 mg',
      ]) {
        await _reachSavedText(tester, value);
      }
      await _pressSavedText(tester, 'Close');
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(await db.select(db.mealPlanEntries).get(), before);
      expect(await db.select(db.pendingWrites).get(), pendingBefore);
    },
  );

  for (final bool deleted in <bool>[false, true]) {
    testWidgets(
      'details Edit portion corrects the original basis after the food is ${deleted ? 'deleted' : 'renamed and resized'}',
      (WidgetTester tester) async {
        final HearthDatabase db = await _day(
          tester,
          food: _currentFood(deleted: deleted),
        );
        await _details(tester);
        await _reachSavedText(tester, '125 g');
        if (deleted) {
          await _reachSavedText(
            tester,
            'The current library item is unavailable. Your saved log is still here.',
          );
          expect(_savedText('View current food'), findsNothing);
        }
        await _pressSavedText(tester, 'Edit portion');
        expect(find.byType(LoggedDetailsSheet), findsNothing);
        expect(find.widgetWithText(TextField, '125'), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'g'))
              .selected,
          isTrue,
        );
        expect(find.widgetWithText(ChoiceChip, '200 g pot'), findsNothing);
        await tester.enterText(find.byType(TextField).last, '62.5');
        await _tap(tester, find.text('Update logged portion'));

        final MealPlanEntry corrected = await _stored(db);
        expect(corrected.isLogged, isTrue);
        expect(corrected.servings, closeTo(62.5 / 170, 1e-12));
        expect(corrected.macroSnapshot!.macros, _savedNutrition.scaledBy(0.5));
        expect(corrected.macroSnapshot!.label, _frozenName);
        expect(corrected.macroSnapshot!.capturedAt, _recordedAt);
        expect(
          corrected.macroSnapshot!.usableLoggedPortion!.enteredAmount,
          62.5,
        );
        expect(
          corrected.macroSnapshot!.usableLoggedPortion!.nutritionServing.label,
          '170 g pot',
        );
      },
    );
  }

  testWidgets(
    'View current food leaves the frozen receipt for an explicit current read-only view',
    (WidgetTester tester) async {
      final HearthDatabase db = await _day(tester);
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      await _details(tester);
      await _pressSavedText(tester, 'View current food');
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(find.text(_currentName), findsOneWidget);
      expect(
        find.text('Current library values, not a past log.'),
        findsOneWidget,
      );
      expect(find.text('200 g pot'), findsOneWidget);
      expect(find.text('999 kcal'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pageBack();
      await pumpFrames(tester, frames: 12);
      expect(find.text(_frozenName), findsOneWidget);
      expect(await db.select(db.mealPlanEntries).get(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy Day details and correction use saved servings without inventing grams',
    (WidgetTester tester) async {
      final HearthDatabase db = await _day(
        tester,
        entry: _logged(legacy: true),
      );
      await _details(tester);
      await _reachSavedText(tester, '1 1/2 servings');
      await _reachSavedText(
        tester,
        'The original amount wasn’t recorded. These are the saved servings.',
      );
      expect(_savedText('125 g'), findsNothing);
      await _pressSavedText(tester, 'Edit portion');
      expect(find.text('Saved servings'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'g'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'oz'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '0.75');
      await _tap(tester, find.text('Update logged portion'));
      final MealPlanEntry corrected = await _stored(db);
      expect(corrected.servings, 0.75);
      expect(corrected.macroSnapshot!.macros, _savedNutrition.scaledBy(0.5));
      expect(corrected.macroSnapshot!.usableLoggedPortion, isNull);
      expect(corrected.macroSnapshot!.capturedAt, _recordedAt);
    },
  );

  testWidgets(
    'a planned row offers no logged details and opening More creates no history',
    (WidgetTester tester) async {
      final HearthDatabase db = await _day(tester, entry: _planned());
      final List<MealPlanEntryRow> before = await db
          .select(db.mealPlanEntries)
          .get();
      await _options(tester);
      expect(find.text('View logged details'), findsNothing);
      expect(find.byType(LoggedDetailsSheet), findsNothing);
      expect(await db.select(db.mealPlanEntries).get(), before);
      expect((await _stored(db)).macroSnapshot, isNull);
    },
  );

  testWidgets(
    'one-tap planned food logging captures the current named serving, not an inferred raw amount',
    (WidgetTester tester) async {
      final HearthDatabase db = await _day(tester, entry: _planned());
      await _tap(tester, find.byKey(_logKey));
      final MealPlanEntry logged = await _stored(db);
      expect(logged.macroSnapshot!.usableLoggedPortion, isNotNull);
      final LoggedPortion saved = logged.macroSnapshot!.usableLoggedPortion!;
      expect(logged.isLogged, isTrue);
      expect(saved.enteredAmount, 1.25);
      expect(saved.enteredUnit.isRaw, isFalse);
      expect(saved.enteredUnit.id, 'serving:pot');
      expect(saved.nutritionServing.label, '200 g pot');
      expect(logged.macroSnapshot!.label, _currentName);
      expect(logged.macroSnapshot!.macros.kcal, 999 * 1.25);
    },
  );

  testWidgets(
    'one-tap selected package serving freezes its own nutrition and approximation',
    (WidgetTester tester) async {
      final Quantity cup = Quantity.of(1, Units.cup);
      final Quantity pack = Quantity.of(10, Units.ounce);
      final Food food = Food(
        id: _foodId,
        name: 'Packaged soup',
        source: FoodSource.manual,
        packSize: pack,
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'default',
            label: 'Other cup',
            amount: cup,
            macros: const Macros(kcal: 900, fiberG: 40),
          ),
          ServingOption(
            id: 'label-cup',
            label: 'Label cup',
            amount: cup,
            macros: const Macros(kcal: 100, sodiumMg: 20),
          ),
        ],
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 2,
          servingOptionId: 'label-cup',
          servingAmount: cup,
          packageAmount: pack,
          isApproximate: true,
        ),
      );
      final HearthDatabase db = await _day(
        tester,
        food: food,
        entry: _planned(count: 6, servingOptionId: 'label-cup'),
      );
      await _tap(tester, find.byKey(_logKey));
      final MealPlanEntry logged = await _stored(db);
      final MacroSnapshot snapshot = logged.macroSnapshot!;
      expect(snapshot.usesApproximatePackageNutrition, isTrue);
      expect(snapshot.usableLoggedPortion, isNotNull);
      final LoggedPortion saved = snapshot.usableLoggedPortion!;
      expect(logged.servingOptionId, 'label-cup');
      expect(snapshot.macros.kcal, 600);
      expect(snapshot.macros.fiberG, isNull);
      expect(snapshot.macros.sodiumMg, 120);
      expect(snapshot.coverage.of(MinorNutrient.fiber), MinorCoverage.unknown);
      expect(snapshot.usesApproximatePackageNutrition, isTrue);
      expect(saved.enteredUnit.isRaw, isFalse);
      expect(saved.enteredUnit.id, 'serving:label-cup');
      expect(saved.enteredAmount, 6);
      expect(saved.nutritionServing.id, 'label-cup');
    },
  );
}
