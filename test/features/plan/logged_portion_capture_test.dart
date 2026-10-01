import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

Future<HearthDatabase> _choose(WidgetTester tester) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    foods: <Food>[
      aFood(
        'Yoghurt',
        id: 'yoghurt',
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'pot',
            label: '170 g pot',
            amount: Quantity.of(170, Units.gram),
            macros: const Macros(kcal: 170, proteinG: 17),
          ),
        ],
      ),
    ],
  );
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.byTooltip('Add to breakfast').first);
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.text('Yoghurt').last);
  await pumpFrames(tester, frames: 12);
  await tester.tap(find.widgetWithText(ChoiceChip, 'g'));
  await pumpFrames(tester, frames: 8);
  return db;
}

Future<Map<String, Object?>> _save(
  WidgetTester tester,
  HearthDatabase db,
) async {
  await SweepTools(tester).reach(find.text('Log it'));
  await pumpFrames(tester, frames: 20);
  final MealPlanEntryRow row =
      (await db.select(db.mealPlanEntries).get()).single;
  return jsonDecode(row.macroSnapshot!) as Map<String, Object?>;
}

void main() {
  testWidgets('typing the displayed number records the chosen unit too', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _choose(tester);
    await tester.enterText(find.byType(TextField).last, '');
    await tester.enterText(find.byType(TextField).last, '170');
    final Map<String, Object?> snapshot = await _save(tester, db);
    final Map<String, Object?> portion =
        snapshot['logged_portion']! as Map<String, Object?>;
    expect(portion['entered_amount'], 170);
    expect((portion['entered_unit']! as Map<String, Object?>)['unit_id'], 'g');
    expect(snapshot['kcal'], 170);
  });

  testWidgets('pending precise input survives saving without keyboard Done', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _choose(tester);
    await tester.enterText(find.byType(TextField).last, '125.123456');
    final Map<String, Object?> snapshot = await _save(tester, db);
    final Map<String, Object?> portion =
        snapshot['logged_portion']! as Map<String, Object?>;
    expect(portion['entered_amount'], 125.123456);
    expect(snapshot['kcal'], closeTo(125.123456, 1e-9));
  });

  testWidgets('viewing ounces keeps the actual gram entry unchanged', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _choose(tester);
    await tester.enterText(find.byType(TextField).last, '125.123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, frames: 8);
    await tester.tap(find.widgetWithText(ChoiceChip, 'oz'));
    await pumpFrames(tester, frames: 8);
    final Map<String, Object?> snapshot = await _save(tester, db);
    final Map<String, Object?> portion =
        snapshot['logged_portion']! as Map<String, Object?>;
    expect(portion['entered_amount'], 125.123456);
    expect((portion['entered_unit']! as Map<String, Object?>)['unit_id'], 'g');
    expect(snapshot['kcal'], closeTo(125.123456, 1e-9));
  });
}
