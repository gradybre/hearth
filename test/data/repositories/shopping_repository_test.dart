import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/data/repositories/shopping_repository.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// The shopping list reaching the other phone (spec §5.7, §7.2).
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late ShoppingRepository repository;
  DateTime clock = DateTime.utc(2026, 9, 2, 9);

  setUp(() {
    clock = DateTime.utc(2026, 9, 2, 9);
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = ShoppingRepository(
      database: db,
      store: ShoppingStore(db),
      queue: queue,
      householdId: 'household-1',
      now: () => clock,
      idFactory: () => 'list-1',
    );
  });

  tearDown(() => db.close());

  ShoppingLine beef({bool checked = false}) => ShoppingLine(
    key: 'ground-beef',
    name: 'ground beef',
    planned: <Quantity>[Quantity.of(2, Units.pound)],
    checked: checked,
    sortOrder: 0,
  );

  ShoppingLine coffee() =>
      ShoppingLine.manual(key: 'coffee', name: 'Coffee', sortOrder: 1);

  Future<List<PendingWrite>> pending() => queue.pending();

  test('saving a list queues the list and every line', () async {
    await repository.replace(<ShoppingLine>[beef(), coffee()]);

    final List<PendingWrite> writes = await pending();
    expect(writes.map((PendingWrite w) => w.entityTable).toSet(), <String>{
      'shopping_lists',
      'shopping_list_items',
    });
    expect(
      writes.where((PendingWrite w) => w.entityTable == 'shopping_list_items'),
      hasLength(2),
    );
  });

  test('a line keeps its id across saves', () async {
    // The whole reason ids are derived rather than invented: saving rewrites
    // every line, so a fresh id each time would mint a new row on the server
    // for every tick and leave the old one standing on the partner's phone.
    await repository.replace(<ShoppingLine>[beef()]);
    final String first = (await pending())
        .firstWhere((PendingWrite w) => w.entityTable == 'shopping_list_items')
        .entityId;

    await queue.markSynced((await pending()).last.sequence);
    clock = clock.add(const Duration(minutes: 5));
    await repository.replace(<ShoppingLine>[beef(checked: true)]);

    final String second = (await pending())
        .lastWhere((PendingWrite w) => w.entityTable == 'shopping_list_items')
        .entityId;
    expect(second, first);
  });

  test('and the same line has the same id on both phones', () async {
    // Derived from the list and the line's key, so two devices that built the
    // same list independently agree on which row is which.
    expect(
      ShoppingRepository.itemIdFor(listId: 'list-1', itemKey: 'ground-beef'),
      ShoppingRepository.itemIdFor(listId: 'list-1', itemKey: 'ground-beef'),
    );
    expect(
      ShoppingRepository.itemIdFor(listId: 'list-1', itemKey: 'ground-beef'),
      isNot(
        ShoppingRepository.itemIdFor(listId: 'list-2', itemKey: 'ground-beef'),
      ),
    );
  });

  test('a line taken off the list is queued as a real delete', () async {
    // An item carries no history worth keeping, unlike a recipe or a food, so
    // it goes rather than being tombstoned.
    await repository.replace(<ShoppingLine>[beef(), coffee()]);
    for (final PendingWrite write in await pending()) {
      await queue.markSynced(write.sequence);
    }

    await repository.replace(<ShoppingLine>[beef()]);

    final List<PendingWrite> deletes = (await pending())
        .where((PendingWrite w) => w.operation == WriteOperation.delete)
        .toList();
    expect(deletes, hasLength(1));
    expect(
      deletes.single.entityId,
      ShoppingRepository.itemIdFor(listId: 'list-1', itemKey: 'coffee'),
    );
  });

  test('a tick rides on the queued payload', () async {
    await repository.replace(<ShoppingLine>[beef(checked: true)]);

    final PendingWrite item = (await pending()).firstWhere(
      (PendingWrite w) => w.entityTable == 'shopping_list_items',
    );
    expect(item.payload['checked'], isTrue);
    expect(item.payload['raw_name'], 'ground beef');
    expect(item.payload['shopping_list_id'], 'list-1');
  });

  test('the list payload carries the range as plain dates', () async {
    // The server columns are `date`, not timestamps.
    await repository.replace(<ShoppingLine>[beef()]);

    final PendingWrite list = (await pending()).firstWhere(
      (PendingWrite w) => w.entityTable == 'shopping_lists',
    );
    expect(list.payload['from_date'], '2026-09-02');
    expect(list.payload['to_date'], '2026-09-08');
  });
}
