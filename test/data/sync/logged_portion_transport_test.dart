import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

void main() {
  for (final bool futureVersion in <bool>[false, true]) {
    test(
      'portion evidence survives queue, receiving device and export (future=$futureVersion)',
      () async {
        final HearthDatabase source = HearthDatabase.forTesting(
          NativeDatabase.memory(),
        );
        final HearthDatabase receiver = HearthDatabase.forTesting(
          NativeDatabase.memory(),
        );
        addTearDown(source.close);
        addTearDown(receiver.close);
        final DateTime at = DateTime.utc(2026, 10, 1, 12);
        final ServingOption standard = ServingOption(
          id: 'pot',
          label: '170 g pot',
          amount: Quantity.of(170, Units.gram),
          macros: const Macros(kcal: 170),
        );
        final PendingWriteStore queue = PendingWriteStore(source);
        final PlanRepository plans = PlanRepository(
          database: source,
          store: PlanStore(source),
          queue: queue,
          userId: 'me',
          clock: () => at,
        );
        final MealPlanEntry added = await plans.add(
          date: at,
          slot: MealSlot.lunch,
          refType: PlanRefType.food,
          refId: 'yoghurt',
          servings: 125 / 170,
          loggedMacros: standard.macros,
          label: 'Original yoghurt',
          loggedPortion: LoggedPortion.tryCapture(
            amount: 125,
            unit: const PortionUnit.raw(Units.gram),
            servings: 125 / 170,
            standard: standard,
          ),
        );
        final List<PendingWrite> pending = await queue.pending();
        final Map<String, Object?> outgoing = pending
            .singleWhere((PendingWrite write) => write.entityId == added.id)
            .payload;
        final Map<String, Object?> snapshot =
            outgoing['macro_snapshot']! as Map<String, Object?>;
        final Map<String, Object?> portion =
            snapshot['logged_portion']! as Map<String, Object?>;
        expect(portion['entered_amount'], 125);
        // Simulate an additive field/version from a later client. The transport
        // and export promise is opaque preservation, even when UI cannot use it.
        final Map<String, Object?> incomingSnapshot = <String, Object?>{
          ...snapshot,
          'future_receipt': <String, Object?>{'source': 'kept'},
          'logged_portion': <String, Object?>{
            ...portion,
            if (futureVersion) 'version': 999,
            'future_field': <String>['kept'],
          },
        };
        final RemoteRows rows = RemoteRows(receiver);
        await rows.applyDay(
          pending
              .singleWhere(
                (PendingWrite write) => write.entityId == added.dayId,
              )
              .payload,
        );
        await rows.applyEntry(<String, Object?>{
          ...outgoing,
          'macro_snapshot': incomingSnapshot,
        });
        final MealPlanEntryRow received =
            (await receiver.select(receiver.mealPlanEntries).get()).single;
        expect(jsonDecode(received.macroSnapshot!), incomingSnapshot);
        final MacroSnapshot read = PlanMapper.entryToDomain(received)
            .macroSnapshot!;
        expect(
          read.usableLoggedPortion?.enteredAmount,
          futureVersion ? isNull : 125,
        );
        final Map<String, Object?> exported = await DataExport(
          database: receiver,
          recipes: RecipeStore(receiver),
          foods: FoodStore(receiver),
          clock: () => at,
        ).asJson(householdId: 'our-household', userId: 'me');
        final Map<String, Object?> exportedEntry =
            (exported['meal_plan_entries']! as List<Object?>).single!
                as Map<String, Object?>;
        expect(exportedEntry['macro_snapshot'], incomingSnapshot);
      },
    );
  }
}
