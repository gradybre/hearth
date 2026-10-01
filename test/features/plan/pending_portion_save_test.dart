import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';
import 'package:hearth/features/plan/log_sheet.dart';

import '../../support/app_harness.dart';

void main() {
  final cup = Quantity.of(1, Units.cup);
  final pack = Quantity.of(10, Units.ounce);
  final food = Food(
    id: 'corn',
    name: 'Corn',
    source: FoodSource.manual,
    packSize: pack,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'default',
        label: 'Other cup',
        amount: cup,
        macros: const Macros(kcal: 500, fiberG: 20),
      ),
      ServingOption(
        id: 'label-cup',
        label: 'Label cup',
        amount: cup,
        macros: const Macros(kcal: 250, fiberG: 10),
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
  final source =
      const MealPlanEntry(
        id: 'source',
        dayId: 'day',
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'corn',
        servings: 6,
        servingOptionId: 'label-cup',
      ).log(
        liveMacros: const Macros(kcal: 100),
        at: DateTime(2026, 9, 20),
        label: 'Corn',
        coverage: NutrientCoverage.ofOne(const Macros(kcal: 100)),
        usesApproximatePackage: true,
        loggedPortion: LoggedPortion.tryCapture(
          amount: 30,
          unit: const PortionUnit.raw(Units.ounce),
          servings: 6,
          standard: food.servingOptions[1],
        ),
      );

  for (final ({String action, bool raw}) scenario
      in <({String action, bool raw})>[
        for (final String action in <String>[
          'Add to plan',
          'Save planned portion',
          'Log it',
          'Update logged portion',
        ])
          for (final bool raw in <bool>[false, true])
            (action: action, raw: raw),
      ]) {
    final String action = scenario.action;
    final bool raw = scenario.raw;
    testWidgets(
      '$action commits the focused ${raw ? 'raw' : 'named'} amount without Done',
      (tester) async {
        final bool existing =
            action == 'Save planned portion' ||
            action == 'Update logged portion';
        final bool correction = action == 'Update logged portion';
        final bool eaten = correction || action == 'Log it';
        final MealPlanEntry initial = action == 'Save planned portion'
            ? source.unlog()
            : source;
        final DateTime destination = addDays(
          dayKey(DateTime.now()),
          action == 'Add to plan' ? 1 : 0,
        );
        final db = await pumpHearthApp(
          tester,
          foods: [food],
          entries: [initial],
          recentLogs: RecentLogs.from([source]),
        );
        unawaited(
          showLogSheet(
            tester.element(find.byType(Scaffold).first),
            date: destination,
            slot: MealSlot.lunch,
            existing: existing
                ? EntryResolver.resolve(
                    initial,
                    recipes: {},
                    foods: {food.id: food},
                  )
                : null,
          ),
        );
        await pumpFrames(tester, frames: 12);
        if (!existing) {
          await tester.tap(find.byTooltip('Review Corn portion'));
          await pumpFrames(tester);
        }
        expect(find.widgetWithText(FilledButton, action), findsOneWidget);
        if (raw) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'oz'));
          await pumpFrames(tester);
        } else if (correction) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Label cup'));
          await pumpFrames(tester);
        }
        await tester.enterText(find.byType(TextField).last, raw ? '20' : '4');
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .focusNode!
              .hasFocus,
          isTrue,
        );
        // Do not dismiss the keyboard or send Done before the touch action.
        await tester.tap(find.text(action), kind: PointerDeviceKind.touch);
        await pumpFrames(tester, frames: 16);
        final entries = (await db.select(db.mealPlanEntries).get())
            .map(PlanMapper.entryToDomain)
            .toList();
        final saved = existing
            ? entries.single
            : entries.singleWhere((entry) => entry.id != source.id);
        expect(
          saved.servings,
          4,
          reason: 'Save must read the amount under the cursor, not the last committed amount',
        );
        expect(saved.servingOptionId, 'label-cup');
        if (raw) {
          expect(
            await PreferenceStore(db)
                .read('${PreferenceStore.logUnitForEntry}${saved.id}'),
            'unit:oz',
          );
        }
        expect(saved.isLogged, eaten);
        if (eaten) {
          expect(saved.macroSnapshot!.servings, 4);
          expect(saved.macroSnapshot!.macros.kcal, correction ? 400 : 1000);
          expect(saved.macroSnapshot!.macros.fiberG, correction ? isNull : 40);
          expect(saved.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
          if (correction) {
            expect(
              saved.macroSnapshot!.capturedAt,
              source.macroSnapshot!.capturedAt,
            );
            expect(
              saved.macroSnapshot!.coverage,
              source.macroSnapshot!.coverage,
            );
          }
        } else {
          expect(saved.macroSnapshot, isNull);
        }
        if (!existing) {
          expect(
            entries.singleWhere((entry) => entry.id == source.id).macroSnapshot,
            source.macroSnapshot,
          );
        }
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
      }),
    );
  }

  for (final bool focusOnly in <bool>[false, true]) {
    testWidgets(
      'saving ${focusOnly ? 'focused' : 'unfocused'} untouched rounded ounces keeps the exact frozen portion',
      (tester) async {
        final MealPlanEntry initial = source
            .unlog()
            .copyWith(servings: 6.037)
            .log(
              liveMacros: const Macros(kcal: 100),
              at: DateTime(2026, 9, 20),
              label: 'Corn',
              coverage: NutrientCoverage.ofOne(const Macros(kcal: 100)),
              usesApproximatePackage: true,
              loggedPortion: LoggedPortion.tryCapture(
                amount: 6.037 * 5,
                unit: const PortionUnit.raw(Units.ounce),
                servings: 6.037,
                standard: food.servingOptions[1],
              ),
            );
        final db = await pumpHearthApp(
          tester,
          foods: [food],
          entries: [initial],
        );
        await PreferenceStore(
          db,
        ).write('${PreferenceStore.logUnitForEntry}${initial.id}', 'unit:oz');
        unawaited(
          showLogSheet(
            tester.element(find.byType(Scaffold).first),
            date: dayKey(DateTime.now()),
            slot: MealSlot.lunch,
            existing: EntryResolver.resolve(
              initial,
              recipes: {},
              foods: {food.id: food},
            ),
          ),
        );
        await pumpFrames(tester, frames: 12);
        expect(find.widgetWithText(TextField, '30.19'), findsOneWidget);
        if (focusOnly) {
          await tester.tap(
            find.byType(TextField).last,
            kind: PointerDeviceKind.touch,
          );
          await pumpFrames(tester);
        }
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .focusNode!
              .hasFocus,
          focusOnly,
        );
        await tester.tap(
          find.text('Update logged portion'),
          kind: PointerDeviceKind.touch,
        );
        await pumpFrames(tester, frames: 16);
        final saved = PlanMapper.entryToDomain(
          (await db.select(db.mealPlanEntries).get()).single,
        );
        expect(saved.servings, initial.servings);
        expect(saved.servingOptionId, initial.servingOptionId);
        expect(saved.macroSnapshot, initial.macroSnapshot);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
      }),
    );
  }
}
