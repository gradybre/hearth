import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Food _currentFood() => aFood(
  'Greek yoghurt',
  id: 'yoghurt',
  servingOptions: <ServingOption>[
    ServingOption(
      id: 'pot',
      label: '200 g pot',
      amount: Quantity.of(200, Units.gram),
      macros: const Macros(kcal: 240, proteinG: 20),
    ),
  ],
);

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester, frames: 12);
  await tester.longPress(find.text('Greek yoghurt').last);
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.text('Edit portion'));
  await pumpFrames(tester, frames: 12);
}

void main() {
  testWidgets('125 g reopens and corrects using the frozen 170 g serving', (
    WidgetTester tester,
  ) async {
    final ServingOption original = ServingOption(
      id: 'pot',
      label: '170 g pot',
      amount: Quantity.of(170, Units.gram),
      macros: const Macros(kcal: 170, proteinG: 17),
    );
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[_currentFood()],
      entries: <MealPlanEntry>[
        const MealPlanEntry(
          id: 'weighted-log',
          dayId: 'day-1',
          slot: MealSlot.breakfast,
          refType: PlanRefType.food,
          refId: 'yoghurt',
          servings: 125 / 170,
        ).log(
          liveMacros: original.macros,
          at: DateTime.utc(2026, 6, 1, 8),
          label: 'Greek yoghurt',
          coverage: NutrientCoverage.ofOne(original.macros),
          loggedPortion: LoggedPortion.tryCapture(
            amount: 125,
            unit: const PortionUnit.raw(Units.gram),
            servings: 125 / 170,
            standard: original,
          ),
        ),
      ],
    );
    await _edit(tester);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'g')).selected,
      isTrue,
    );
    expect(find.widgetWithText(TextField, '125'), findsOneWidget);
    expect(find.textContaining('200 g pot'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '62.5');
    await tester.tap(find.text('Update logged portion'));
    await pumpFrames(tester, frames: 20);
    final MealPlanEntryRow row =
        (await db.select(db.mealPlanEntries).get()).single;
    final Map<String, Object?> json =
        jsonDecode(row.macroSnapshot!) as Map<String, Object?>;
    expect(json['kcal'], closeTo(62.5, 1e-9));
    expect(
      (json['logged_portion']! as Map<String, Object?>)['entered_amount'],
      62.5,
    );
    expect(json['label'], 'Greek yoghurt');
  });

  testWidgets(
    'legacy corrections never invent an old weight from today’s food',
    (WidgetTester tester) async {
      final HearthDatabase db = await pumpHearthApp(
        tester,
        foods: <Food>[_currentFood()],
        entries: <MealPlanEntry>[
          const MealPlanEntry(
            id: 'old-log',
            dayId: 'day-1',
            slot: MealSlot.breakfast,
            refType: PlanRefType.food,
            refId: 'yoghurt',
            servings: 1,
          ).log(
            liveMacros: const Macros(kcal: 170, proteinG: 17),
            at: DateTime.utc(2026, 6, 1, 8),
            label: 'Greek yoghurt',
            coverage: const NutrientCoverage.notRecorded(),
          ),
        ],
      );
      await _edit(tester);
      expect(find.widgetWithText(ChoiceChip, 'g'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, '200 g pot'), findsNothing);
      expect(
        find.textContaining('original amount wasn’t recorded'),
        findsOneWidget,
      );
      expect(find.text('Saved servings'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '0.5');
      await tester.tap(find.text('Update logged portion'));
      await pumpFrames(tester, frames: 20);
      final MealPlanEntryRow row =
          (await db.select(db.mealPlanEntries).get()).single;
      final Map<String, Object?> json =
          jsonDecode(row.macroSnapshot!) as Map<String, Object?>;
      expect(row.servings, 0.5);
      expect(json['kcal'], 85);
      expect(json['logged_portion'], isNull);
    },
  );

  for (final String evidenceKind in <String>[
    'future version',
    'stale evidence',
  ]) {
    testWidgets(
      '$evidenceKind correction explains recorded amount is unavailable',
      (WidgetTester tester) async {
        final LoggedPortion evidence = LoggedPortion.tryCapture(
          amount: 125,
          unit: const PortionUnit.raw(Units.gram),
          servings: 125 / 170,
          standard: ServingOption(
            id: 'old-pot',
            label: '170 g pot',
            amount: Quantity.of(170, Units.gram),
            macros: const Macros(kcal: 170),
          ),
        )!;
        final MacroSnapshot snapshot = PlanMapper.snapshotFromJson(
          jsonEncode(<String, Object?>{
            'kcal': 255,
            'servings': 1.5,
            'captured_at': DateTime.utc(2026, 6, 1, 8).toIso8601String(),
            'label': 'Greek yoghurt',
            'logged_portion': <String, Object?>{
              ...evidence.toJson(),
              if (evidenceKind == 'future version') 'version': 99,
            },
          }),
        )!;
        expect(snapshot.usableLoggedPortion, isNull);
        final HearthDatabase db = await pumpHearthApp(
          tester,
          foods: <Food>[_currentFood()],
          entries: <MealPlanEntry>[
            MealPlanEntry(
              id: 'unavailable-amount',
              dayId: 'day-1',
              slot: MealSlot.breakfast,
              refType: PlanRefType.food,
              refId: 'yoghurt',
              servings: 1.5,
              isLogged: true,
              loggedAt: snapshot.capturedAt,
              macroSnapshot: snapshot,
            ),
          ],
        );
        await _edit(tester);
        expect(
          find.textContaining(
            'The original amount is unavailable. These are the saved servings.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('wasn’t recorded'), findsNothing);
        expect(
          find.textContaining('Today’s serving size is not used'),
          findsOneWidget,
        );
        expect(find.widgetWithText(ChoiceChip, 'g'), findsNothing);
        expect(find.widgetWithText(ChoiceChip, '200 g pot'), findsNothing);
        expect(find.text('Saved servings'), findsOneWidget);
        final MealPlanEntryRow row =
            (await db.select(db.mealPlanEntries).get()).single;
        expect(row.servings, 1.5);
        expect(PlanMapper.snapshotFromJson(row.macroSnapshot), snapshot);
      },
    );
  }
}
