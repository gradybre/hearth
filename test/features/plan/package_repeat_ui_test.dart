import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/entry_resolver.dart';
import 'package:hearth/features/plan/log_sheet.dart';

import '../../support/app_harness.dart';

void main() {
  final pack = Quantity.of(10, Units.ounce);
  final cup = Quantity.of(1, Units.cup);
  final selected = ServingOption(
    id: 'label-cup',
    label: 'Label cup',
    amount: cup,
    macros: const Macros(kcal: 100),
  );
  Food food({bool removed = false}) => Food(
    id: 'corn',
    name: 'Corn',
    source: FoodSource.manual,
    packSize: pack,
    servingOptions: [
      ServingOption(
        id: 'default',
        label: 'Other cup',
        amount: cup,
        macros: const Macros(kcal: 200, fiberG: 7),
      ),
      if (!removed) selected,
    ],
    packageNutrition: PackageNutrition.manual(
      servingsPerPackage: 2,
      servingOptionId: selected.id,
      servingAmount: cup,
      packageAmount: pack,
      isApproximate: true,
    ),
  );
  final source =
      const MealPlanEntry(
        id: 'old',
        dayId: 'd',
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'corn',
        servings: 6,
        servingOptionId: 'label-cup',
      ).log(
        liveMacros: selected.macros,
        label: 'Corn',
        at: DateTime(2026, 9, 18),
        usesApproximatePackage: true,
        coverage: NutrientCoverage.ofOne(selected.macros),
      );
  for (final removed in [false, true]) {
    testWidgets(
      removed
          ? 'repeat refuses a removed serving'
          : 'one tap repeat freezes 600 kcal from the selected cup',
      (tester) async {
        final db = await pumpHearthApp(
          tester,
          foods: [food(removed: removed)],
          recentLogs: RecentLogs.from([source]),
        );
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester);
        await tester.tap(find.byTooltip('Add to breakfast'));
        await pumpFrames(tester);
        await tester.tap(
          find.text(
            removed ? 'log again · 6 servings' : 'log again · 6 × Label cup',
          ),
        );
        await pumpFrames(tester, frames: 12);
        final rows = await db.select(db.mealPlanEntries).get();
        if (removed) {
          expect(rows, isEmpty);
          expect(find.textContaining('has been removed'), findsOneWidget);
        } else {
          final entry = PlanMapper.entryToDomain(rows.single);
          expect(entry.servingOptionId, 'label-cup');
          expect(entry.macroSnapshot!.macros.kcal, 600);
          expect(entry.macroSnapshot!.macros.fiberG, isNull);
          expect(entry.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
        }
      },
    );
  }
  testWidgets(
    'reviewing a package recent retains the selected serving and qualifier',
    (tester) async {
      final db = await pumpHearthApp(
        tester,
        foods: [food()],
        recentLogs: RecentLogs.from([source]),
      );
      await tester.tap(find.text('Plan').last);
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Add to breakfast'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Review Corn portion'));
      await pumpFrames(tester);
      expect(
        find.descendant(
          of: find.byType(DraggableScrollableSheet).last,
          matching: find.textContaining('600 kcal'),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ChoiceChip, 'Label cup'), findsOneWidget);
      await tester.tap(find.text('Log it'));
      await pumpFrames(tester, frames: 12);
      final entry = PlanMapper.entryToDomain(
        (await db.select(db.mealPlanEntries).get()).single,
      );
      expect(entry.servingOptionId, 'label-cup');
      expect(entry.macroSnapshot!.macros.kcal, 600);
      expect(entry.macroSnapshot!.macros.fiberG, isNull);
      expect(entry.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
    },
  );
  for (final ({bool fromRecent, bool withoutDone}) scenario
      in <({bool fromRecent, bool withoutDone})>[
        (fromRecent: true, withoutDone: false),
        (fromRecent: true, withoutDone: true),
        (fromRecent: false, withoutDone: false),
        (fromRecent: false, withoutDone: true),
      ]) {
    final bool fromRecent = scenario.fromRecent;
    final bool withoutDone = scenario.withoutDone;
    testWidgets(
      withoutDone
          ? 'multi-day ${fromRecent ? 'named package count' : 'raw package amount'} commits touch input without Done'
          : fromRecent
          ? 'multi-day review of a package recent keeps the selected cup'
          : 'multi-day raw package amounts keep the resolved serving and entry unit',
      (tester) async {
        final double expectedServings = withoutDone ? 4 : 6;
        final double expectedKcal = expectedServings * 100;
        final String rawAmount = withoutDone ? '20' : '30';
        final corn = food();
        final db = await pumpHearthApp(
          tester,
          foods: [corn],
          entries: [source],
          selectedDate: DateTime(2026, 9, 28),
          recentLogs: fromRecent
              ? RecentLogs.from([source])
              : const <RecentLog>[],
        );
        await tester.tap(find.text('Plan').last);
        await pumpFrames(tester);
        await tester.tap(find.byTooltip('Add to breakfast'));
        await pumpFrames(tester);
        if (fromRecent) {
          await tester.tap(find.byTooltip('Review Corn portion'));
        } else {
          await tester.tap(find.text('Corn').last);
        }
        await pumpFrames(tester);
        if (!fromRecent) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'oz'));
          await pumpFrames(tester);
          await tester.enterText(find.byType(TextField).last, rawAmount);
          if (!withoutDone) {
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await pumpFrames(tester);
          }
        } else if (withoutDone) {
          await tester.enterText(find.byType(TextField).last, '4');
        }
        if (withoutDone) {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).last)
                .focusNode!
                .hasFocus,
            isTrue,
          );
        } else {
          expect(
            find.descendant(
              of: find.byType(DraggableScrollableSheet).last,
              matching: find.textContaining('600 kcal'),
            ),
            findsOneWidget,
          );
        }
        // A real touch tap deliberately does not send Done first. Opening
        // the date picker must commit the active portion before it is read.
        await tester.tap(
          find.text('Add to several days'),
          kind: PointerDeviceKind.touch,
        );
        await pumpFrames(tester);
        await tester.tap(find.textContaining(RegExp(r'^Monday ')).last);
        await pumpFrames(tester);
        await tester.tap(find.textContaining(RegExp(r'^Tuesday ')).last);
        await pumpFrames(tester);
        await tester.tap(find.text('Add to days'));
        await pumpFrames(tester, frames: 16);
        final all = (await db.select(db.mealPlanEntries).get())
            .map(PlanMapper.entryToDomain)
            .toList();
        expect(
          all.singleWhere((entry) => entry.id == source.id).macroSnapshot,
          source.macroSnapshot,
        );
        final assigned = all.where((entry) => entry.id != source.id).toList();
        expect(assigned, hasLength(2));
        for (final entry in assigned) {
          expect(entry.servings, closeTo(expectedServings, 1e-8));
          expect(entry.servingOptionId, 'label-cup');
          expect(entry.isLogged, isFalse);
          expect(entry.macroSnapshot, isNull);
          final resolved = EntryResolver.resolve(
            entry,
            recipes: {},
            foods: {corn.id: corn},
          );
          expect(resolved.contribution.kcal, closeTo(expectedKcal, 1e-8));
          expect(resolved.contribution.fiberG, isNull);
        }
        final entry = assigned.first;
        unawaited(
          showLogSheet(
            tester.element(find.byType(Scaffold).first),
            date: DateTime(2026, 9, 28),
            slot: MealSlot.breakfast,
            existing: EntryResolver.resolve(
              entry,
              recipes: {},
              foods: {corn.id: corn},
            ),
          ),
        );
        await pumpFrames(tester, frames: 12);
        expect(
          find.descendant(
            of: find.byType(DraggableScrollableSheet).last,
            matching: find.textContaining('${expectedKcal.round()} kcal'),
          ),
          findsOneWidget,
        );
        if (!fromRecent) {
          expect(
            tester
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'oz'))
                .selected,
            isTrue,
          );
          expect(find.widgetWithText(TextField, rawAmount), findsOneWidget);
        }
        await tester.tap(find.textContaining('Log as eaten · Breakfast ·'));
        await pumpFrames(tester, frames: 16);
        final saved = (await db.select(db.mealPlanEntries).get())
            .map(PlanMapper.entryToDomain)
            .toList();
        final logged = saved.singleWhere((value) => value.id == entry.id);
        expect(logged.macroSnapshot!.macros.kcal, closeTo(expectedKcal, 1e-8));
        expect(logged.macroSnapshot!.macros.fiberG, isNull);
        expect(logged.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
        expect(
          saved.singleWhere((value) => value.id == source.id).macroSnapshot,
          source.macroSnapshot,
        );
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.iOS,
      }),
    );
  }
}
