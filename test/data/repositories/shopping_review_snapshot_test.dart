import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

class _PausedRead extends ShoppingStore {
  _PausedRead(super.db);
  Completer<void>? reached;
  Completer<void>? resume;

  @override
  Future<ShoppingListSnapshot?> current({required String householdId}) async {
    final ShoppingListSnapshot? result = await super.current(
      householdId: householdId,
    );
    final Completer<void>? signal = reached;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
      await resume!.future;
    }
    return result;
  }
}

void main() {
  test(
    'a review cannot combine old quantities with a newly edited package',
    () async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final _PausedRead store = _PausedRead(db);
      final ShoppingRepository shopping = ShoppingRepository(
        database: db,
        store: store,
        queue: PendingWriteStore(db),
        householdId: 'household-1',
      );
      final FoodStore foods = FoodStore(db);
      Food food(double grams) => Food(
        id: 'sauce',
        householdId: 'household-1',
        name: 'Sauce',
        source: FoodSource.manual,
        servingOptions: const <ServingOption>[],
        packSize: Quantity.of(grams, Units.gram),
        walmartItemId: '123456789',
      );
      ShoppingLine line(double grams) => ShoppingLine(
        key: 'sauce',
        name: 'Sauce',
        foodId: 'sauce',
        planned: <Quantity>[Quantity.of(grams, Units.gram)],
      );
      await foods.upsert(food(400), updatedAt: DateTime.utc(2026, 10, 1));
      await shopping.replace(<ShoppingLine>[line(600)]);
      store.reached = Completer<void>();
      store.resume = Completer<void>();
      final reading = shopping.reviewSnapshot();
      await store.reached!.future;
      // This write belongs to the other async caller, outside the review's
      // transaction zone. It must be wholly before or wholly after that read.
      final Future<void> writing = db.transaction(() async {
        await foods.upsert(food(100), updatedAt: DateTime.utc(2026, 10, 2));
        await shopping.replace(<ShoppingLine>[line(200)]);
      });
      await Future.any<void>(<Future<void>>[
        writing,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
      store.resume!.complete();
      final snapshot = await reading;
      await writing;
      final double amount =
          snapshot.list!.lines.single.planned.single.canonicalAmount;
      final double pack = snapshot.foods['sauce']!.packSize!.canonicalAmount;
      expect(
        <double>[amount, pack],
        anyOf(equals(<double>[600, 400]), equals(<double>[200, 100])),
        reason: 'A review must describe one coherent version, never 600 g in new 100 g packs.',
      );
    },
  );
}
