import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/parsing/amount_parser.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/manual_addition.dart';
import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Fault injection after a real queue write proves both sides roll back.
class _FailingQueue extends PendingWriteStore {
  _FailingQueue(super.db);

  @override
  Future<void> enqueue({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
    required DateTime queuedAt,
  }) async {
    await super.enqueue(
      entityTable: entityTable,
      entityId: entityId,
      operation: operation,
      payload: payload,
      queuedAt: queuedAt,
    );
    if (payload['raw_name'] == 'Paper towels') {
      throw StateError('Queue unavailable');
    }
  }
}

void main() {
  late HearthDatabase db;
  late ShoppingStore store;
  late PendingWriteStore queue;
  late ShoppingRepository repository;
  late DateTime clock;

  ShoppingRepository makeRepository({
    String household = 'household-1',
    PendingWriteStore? writeQueue,
  }) => ShoppingRepository(
    database: db,
    store: store,
    queue: writeQueue ?? queue,
    householdId: household,
    now: () => clock,
    idFactory: () => 'list-$household',
  );

  setUp(() {
    clock = DateTime(2026, 9, 30, 9);
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = ShoppingStore(db);
    queue = PendingWriteStore(db);
    repository = makeRepository();
  });

  tearDown(() => db.close());

  Future<void> seed(List<ShoppingLine> lines) async {
    await store.save(
      householdId: 'household-1',
      listId: 'list-household-1',
      from: DateTime(2026, 9, 20),
      to: DateTime(2026, 9, 23),
      lines: lines,
      updatedAt: clock,
      idFor: (String key) => ShoppingRepository.itemIdFor(
        listId: 'list-household-1',
        itemKey: key,
      ),
    );
  }

  test(
    'first add persists canonical fractions, nulls, and manual sources',
    () async {
      final Quantity amount = Quantity.of(parseAmount('1 1/3')!, Units.cup);
      final ManualAdditionResult result = await repository.addManualItems(
        <ManualListItem>[
          ManualListItem(name: 'Rice', quantity: amount),
          const ManualListItem(name: 'Paper towels'),
        ],
      );
      final ShoppingListSnapshot saved = (await repository.current())!;

      expect(result.added, hasLength(2));
      expect(result.skipped, isEmpty);
      expect(saved.lines, result.lines);
      expect(saved.from, DateTime(2026, 9, 30));
      expect(saved.to, DateTime(2026, 10, 6));
      expect(
        saved.lines.first.planned.single.canonicalAmount,
        amount.canonicalAmount,
      );
      expect(saved.lines.first.planned.single.preferredUnit, Units.cup);
      expect(
        saved.lines.first.contributions.single.kind,
        ShoppingSourceKind.manual,
      );
      expect(saved.lines.last.planned, isEmpty);
      expect(saved.lines.last.wanted, isNull);
      expect(saved.lines.last.onHand, isNull);
      expect(saved.lines.last.hasUnquantified, isTrue);
      expect(saved.lines.last.contributions.single.hasUnquantified, isTrue);

      final List<PendingWrite> writes = await queue.pending();
      expect(writes, hasLength(3));
      expect(
        writes.every((PendingWrite w) => w.operation == WriteOperation.upsert),
        isTrue,
      );
      final PendingWrite rice = writes.firstWhere(
        (PendingWrite w) => w.payload['raw_name'] == 'Rice',
      );
      expect(rice.payload['planned_canonical'], amount.canonicalAmount);
      expect(rice.payload['planned_unit'], 'cup');
      expect(rice.payload['is_manual'], isTrue);
      expect(rice.payload['is_deleted'], isFalse);
      expect(
        rice.entityId,
        ShoppingRepository.itemIdFor(listId: saved.id, itemKey: 'rice'),
      );
      final PendingWrite towels = writes.firstWhere(
        (PendingWrite w) => w.payload['raw_name'] == 'Paper towels',
      );
      expect(towels.payload['planned_canonical'], isNull);
      expect(towels.payload['wanted_canonical'], isNull);
      expect(towels.payload['on_hand_canonical'], isNull);
      expect(towels.payload['has_unquantified'], isTrue);
      expect(towels.payload['contributions'], <Object?>[
        <String, Object?>{
          'kind': 'manual',
          'quantities': <Object?>[],
          'has_unquantified': true,
        },
      ]);
    },
  );

  test(
    'current food names and batch repeats report each skipped request',
    () async {
      await seed(<ShoppingLine>[
        ShoppingLine(
          key: 'food-1',
          foodId: 'food-1',
          name: 'Sun-dried tomatoes',
          planned: <Quantity>[Quantity.of(2, Units.pound)],
        ),
      ]);
      final ManualAdditionResult result = await repository.addManualItems(
        <ManualListItem>[
          ManualListItem(
            name: 'sun dried tomatoes',
            quantity: Quantity.of(8, Units.pound),
          ),
          const ManualListItem(name: 'Coffee'),
          const ManualListItem(name: ' coffee '),
          const ManualListItem(name: 'SUN-DRIED TOMATOES'),
        ],
      );

      expect(result.added.single.name, 'Coffee');
      expect(result.skipped.map((ManualAdditionSkip skip) => skip.index), <int>[
        0,
        2,
        3,
      ]);
      expect(
        result.skipped.map((ManualAdditionSkip skip) => skip.reason),
        <ManualAdditionSkipReason>[
          ManualAdditionSkipReason.alreadyOnList,
          ManualAdditionSkipReason.duplicateInBatch,
          ManualAdditionSkipReason.alreadyOnList,
        ],
      );
      expect(result.lines.first.planned.single.amountIn(Units.pound), 2);
      expect((await repository.current())!.lines, hasLength(2));
      expect(await queue.count(), 3);
    },
  );

  test(
    'preserves current metadata, store order, and the existing date range',
    () async {
      final ShoppingLine beef = ShoppingLine(
        key: 'food-beef',
        name: 'Ground beef',
        foodId: 'food-beef',
        planned: <Quantity>[
          Quantity.of(2, Units.pound),
          Quantity.of(1, Units.cup),
        ],
        wanted: Quantity.of(3, Units.pound),
        onHand: Quantity.of(0.5, Units.pound),
        checked: true,
        hasUnquantified: true,
        storeTag: 'Costco',
        sortOrder: 19,
        sourceRecipeIds: const <String>['recipe-1'],
        contributions: <ShoppingContribution>[
          ShoppingContribution(
            kind: ShoppingSourceKind.plan,
            quantities: <Quantity>[Quantity.of(2, Units.pound)],
          ),
          ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'recipe-1',
            label: 'Dinner',
            servings: 2,
            quantities: <Quantity>[Quantity.of(1, Units.cup)],
            hasUnquantified: true,
          ),
        ],
      );
      final ShoppingLine rice = ShoppingLine.manual(
        key: 'rice',
        name: 'Rice',
        storeTag: 'Aldi',
        sortOrder: 8,
      );
      await seed(<ShoppingLine>[beef, rice]);
      final ManualAdditionResult result = await repository.addManualItems(
        const <ManualListItem>[
          ManualListItem(name: 'Ground beef'),
          ManualListItem(name: 'Coffee'),
        ],
      );
      final ShoppingListSnapshot saved = (await repository.current())!;

      expect(result.lines.take(2), <ShoppingLine>[rice, beef]);
      expect(
        saved.lines.firstWhere((ShoppingLine line) => line.key == beef.key),
        beef,
      );
      expect(result.lines.last.name, 'Coffee');
      expect(result.lines.last.sortOrder, 20);
      expect(saved.from, DateTime(2026, 9, 20));
      expect(saved.to, DateTime(2026, 9, 23));
    },
  );

  test('empty input does not create a list or outbox rows', () async {
    final ManualAdditionResult result = await repository.addManualItems(
      const <ManualListItem>[],
    );

    expect(result.lines, isEmpty);
    expect(result.added, isEmpty);
    expect(result.skipped, isEmpty);
    expect(await repository.current(), isNull);
    expect(await queue.count(), 0);
  });

  test(
    'all-skipped input leaves row timestamps and existing outbox untouched',
    () async {
      await repository.addManualItems(const <ManualListItem>[
        ManualListItem(name: 'Coffee'),
      ]);
      final List<ShoppingListRow> listsBefore = await db
          .select(db.shoppingLists)
          .get();
      final List<ShoppingItemRow> itemsBefore = await db
          .select(db.shoppingListItems)
          .get();
      final List<PendingWriteRow> queueBefore = await db
          .select(db.pendingWrites)
          .get();
      clock = clock.add(const Duration(hours: 1));

      final ManualAdditionResult result = await repository.addManualItems(
        <ManualListItem>[
          ManualListItem(name: 'coffee', quantity: Quantity.of(2, Units.item)),
        ],
      );

      expect(result.added, isEmpty);
      expect(
        result.skipped.single.reason,
        ManualAdditionSkipReason.alreadyOnList,
      );
      expect(await db.select(db.shoppingLists).get(), listsBefore);
      expect(await db.select(db.shoppingListItems).get(), itemsBefore);
      expect(await db.select(db.pendingWrites).get(), queueBefore);
    },
  );

  test('a no-op result keeps the list in its store display order', () async {
    final ShoppingLine coffee = ShoppingLine.manual(
      key: 'coffee',
      name: 'Coffee',
      storeTag: 'Costco',
      sortOrder: 1,
    );
    final ShoppingLine rice = ShoppingLine.manual(
      key: 'rice',
      name: 'Rice',
      storeTag: 'Aldi',
      sortOrder: 17,
    );
    await seed(<ShoppingLine>[coffee, rice]);

    final ManualAdditionResult result = await repository.addManualItems(
      const <ManualListItem>[ManualListItem(name: 'Coffee')],
    );

    expect(result.lines, <ShoppingLine>[rice, coffee]);
    expect(await queue.count(), 0);
  });

  test(
    'invalid batch on an empty list cannot leave its valid prefix behind',
    () async {
      await expectLater(
        repository.addManualItems(const <ManualListItem>[
          ManualListItem(name: 'Coffee'),
          ManualListItem(name: ' \t '),
        ]),
        throwsArgumentError,
      );

      expect(await db.select(db.shoppingLists).get(), isEmpty);
      expect(await db.select(db.shoppingListItems).get(), isEmpty);
      expect(await queue.count(), 0);
    },
  );

  test(
    'invalid quantity batch leaves existing records and outbox unchanged',
    () async {
      await repository.addManualItems(const <ManualListItem>[
        ManualListItem(name: 'Coffee'),
      ]);
      final List<ShoppingListRow> listsBefore = await db
          .select(db.shoppingLists)
          .get();
      final List<ShoppingItemRow> itemsBefore = await db
          .select(db.shoppingListItems)
          .get();
      final List<PendingWriteRow> queueBefore = await db
          .select(db.pendingWrites)
          .get();

      for (final double amount in <double>[
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        await expectLater(
          repository.addManualItems(<ManualListItem>[
            const ManualListItem(name: 'Paper towels'),
            ManualListItem(
              name: 'Coffee',
              quantity: Quantity.of(amount, Units.item),
            ),
          ]),
          throwsArgumentError,
        );
        expect(await db.select(db.shoppingLists).get(), listsBefore);
        expect(await db.select(db.shoppingListItems).get(), itemsBefore);
        expect(await db.select(db.pendingWrites).get(), queueBefore);
      }
    },
  );

  test(
    'commit reads changes received while the editable review was open',
    () async {
      await repository.addManualItems(const <ManualListItem>[
        ManualListItem(name: 'Coffee'),
      ]);
      final ShoppingListSnapshot reviewSnapshot = (await repository.current())!;
      final List<ManualListItem> reviewed = <ManualListItem>[
        ManualListItem(name: 'Milk', quantity: Quantity.of(2, Units.item)),
        const ManualListItem(name: 'Paper towels'),
      ];
      expect(
        ManualAdditions.apply(reviewSnapshot.lines, reviewed).added,
        hasLength(2),
      );

      await repository.replace(<ShoppingLine>[
        reviewSnapshot.lines.single.copyWith(checked: true, sortOrder: 16),
        ShoppingLine.manual(
          key: 'milk',
          name: 'Milk',
          planned: <Quantity>[Quantity.of(5, Units.item)],
          sortOrder: 31,
        ),
      ]);
      final ManualAdditionResult result = await repository.addManualItems(
        reviewed,
      );

      expect(result.added.single.name, 'Paper towels');
      expect(result.skipped.single.index, 0);
      expect(
        result.skipped.single.reason,
        ManualAdditionSkipReason.alreadyOnList,
      );
      expect(result.lines.first.checked, isTrue);
      expect(result.lines[1].planned.single.amountIn(Units.item), 5);
      expect(result.lines.last.sortOrder, 32);
      expect((await repository.current())!.lines, result.lines);
    },
  );

  test(
    'simultaneous commits retain both additions and recheck duplicates',
    () async {
      // Without the read inside the transaction all callers can read an empty
      // list and the final snapshot writer discards the earlier additions.
      final List<ManualAdditionResult> results = await Future.wait(
        <Future<ManualAdditionResult>>[
          repository.addManualItems(const <ManualListItem>[
            ManualListItem(name: 'Coffee'),
          ]),
          repository.addManualItems(const <ManualListItem>[
            ManualListItem(name: 'Paper towels'),
          ]),
          repository.addManualItems(const <ManualListItem>[
            ManualListItem(name: 'COFFEE'),
          ]),
        ],
      );

      expect(
        results.expand((ManualAdditionResult result) => result.added),
        hasLength(2),
      );
      expect(
        results.expand((ManualAdditionResult result) => result.skipped),
        hasLength(1),
      );
      final ShoppingListSnapshot saved = (await repository.current())!;
      expect(saved.lines.map((ShoppingLine line) => line.key).toSet(), <String>{
        'coffee',
        'paper towels',
      });
      expect(await db.select(db.shoppingLists).get(), hasLength(1));
      expect(await queue.count(), 3);
    },
  );

  test(
    'households have independent lists, duplicate decisions, and outboxes',
    () async {
      final ShoppingRepository other = makeRepository(household: 'household-2');
      await repository.addManualItems(const <ManualListItem>[
        ManualListItem(name: 'Coffee'),
      ]);
      final ManualAdditionResult result = await other.addManualItems(
        <ManualListItem>[
          ManualListItem(name: 'Coffee', quantity: Quantity.of(4, Units.item)),
        ],
      );

      expect(result.added, hasLength(1));
      expect(result.skipped, isEmpty);
      expect((await repository.current())!.lines.single.planned, isEmpty);
      expect(
        (await other.current())!.lines.single.planned.single.amountIn(
          Units.item,
        ),
        4,
      );
      expect(await db.select(db.shoppingLists).get(), hasLength(2));
      expect(
        (await queue.pending())
            .map((PendingWrite write) => write.entityId)
            .toSet(),
        hasLength(4),
      );
    },
  );

  test(
    'queue failure rolls a first list and its partially written outbox back',
    () async {
      final ShoppingRepository failing = makeRepository(
        writeQueue: _FailingQueue(db),
      );
      await expectLater(
        failing.addManualItems(const <ManualListItem>[
          ManualListItem(name: 'Coffee'),
          ManualListItem(name: 'Paper towels'),
        ]),
        throwsStateError,
      );

      expect(await db.select(db.shoppingLists).get(), isEmpty);
      expect(await db.select(db.shoppingListItems).get(), isEmpty);
      expect(await queue.count(), 0);
    },
  );

  test(
    'queue failure restores existing rows and superseded pending writes',
    () async {
      await repository.addManualItems(const <ManualListItem>[
        ManualListItem(name: 'Coffee'),
      ]);
      final List<ShoppingListRow> listsBefore = await db
          .select(db.shoppingLists)
          .get();
      final List<ShoppingItemRow> itemsBefore = await db
          .select(db.shoppingListItems)
          .get();
      final List<PendingWriteRow> queueBefore = await db
          .select(db.pendingWrites)
          .get();
      clock = clock.add(const Duration(hours: 1));
      final ShoppingRepository failing = makeRepository(
        writeQueue: _FailingQueue(db),
      );

      await expectLater(
        failing.addManualItems(const <ManualListItem>[
          ManualListItem(name: 'Paper towels'),
        ]),
        throwsStateError,
      );

      expect(await db.select(db.shoppingLists).get(), listsBefore);
      expect(await db.select(db.shoppingListItems).get(), itemsBefore);
      expect(await db.select(db.pendingWrites).get(), queueBefore);
    },
  );

  test(
    'a plan rebuild keeps both measured and unmeasured manual additions',
    () async {
      final ManualAdditionResult added = await repository.addManualItems(
        <ManualListItem>[
          ManualListItem(name: 'Rice', quantity: Quantity.of(0.5, Units.pound)),
          const ManualListItem(name: 'Coffee'),
        ],
      );
      final Recipe recipe = aRecipe(
        id: 'dinner',
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('Rice', amount: 1, unit: Units.pound),
        ],
      );
      final DateTime day = DateTime(2026, 10, 1);
      final Map<DateTime, List<MealPlanEntry>> entries =
          <DateTime, List<MealPlanEntry>>{
            day: <MealPlanEntry>[
              const MealPlanEntry(
                id: 'entry-1',
                dayId: 'day-1',
                slot: MealSlot.dinner,
                refType: PlanRefType.recipe,
                refId: 'dinner',
                servings: 1,
              ),
            ],
          };
      final List<ShoppingLine> combined = await repository.rebuild(
        from: day,
        to: day,
        entriesByDay: entries,
        recipes: <String, Recipe>{recipe.id: recipe},
        foods: const <String, Food>{},
      );
      expect(
        combined.first.planned.single.amountIn(Units.pound),
        closeTo(1.5, 1e-9),
      );
      expect(
        combined.first.contributions
            .map((ShoppingContribution c) => c.kind)
            .toSet(),
        <ShoppingSourceKind>{
          ShoppingSourceKind.manual,
          ShoppingSourceKind.plan,
        },
      );
      expect(combined.last.hasUnquantified, isTrue);

      final List<ShoppingLine> rebuilt = await repository.rebuild(
        from: day,
        to: day,
        entriesByDay: const <DateTime, List<MealPlanEntry>>{},
        recipes: <String, Recipe>{recipe.id: recipe},
        foods: const <String, Food>{},
      );
      expect(rebuilt.first.planned, added.lines.first.planned);
      expect(rebuilt.last, added.lines.last);
      expect((await repository.current())!.lines, rebuilt);
    },
  );
}
