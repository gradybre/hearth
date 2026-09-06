import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';

/// The range the shopping screen opens on (spec §5.7, R09).
///
/// It always opened on "today plus six", whatever the list in front of you
/// actually covered. Build a list on Friday for the weekend and the week
/// after, open the app on Sunday, and the dates on screen described a
/// different stretch from the one the lines came from — and rebuilding then
/// silently moved the list to match the label rather than the other way
/// round.
void main() {
  late HearthDatabase db;

  ShoppingListSnapshot saved({required DateTime from, required DateTime to}) =>
      ShoppingListSnapshot(
        id: 'list-1',
        from: from,
        to: to,
        lines: const <ShoppingLine>[],
      );

  ProviderContainer containerWith(ShoppingListSnapshot? snapshot) =>
      ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          shoppingListProvider.overrideWith((Ref ref) async => snapshot),
        ],
      );

  setUp(() => db = HearthDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('is the range the saved list covers', () async {
    final DateTime from = DateTime(2026, 9, 4);
    final DateTime to = DateTime(2026, 9, 13);
    final ProviderContainer container = containerWith(
      saved(from: from, to: to),
    );
    addTearDown(container.dispose);

    // Read once to build the notifier, then let the saved list arrive.
    container.read(shoppingRangeProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(shoppingRangeProvider), (from: from, to: to));
  });

  test('and the default when there is no list yet', () async {
    final ProviderContainer container = containerWith(null);
    addTearDown(container.dispose);

    container.read(shoppingRangeProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    final ({DateTime from, DateTime to}) range = container.read(
      shoppingRangeProvider,
    );
    expect(range.to.difference(range.from).inDays, 6);
  });

  test('an adjustment the user made is not thrown away by the list', () async {
    // The trap in the obvious fix: watching the saved list inside `build`
    // rebuilds the notifier every time anything about the list changes —
    // ticking an item, say — and each rebuild would discard the dates the
    // user had just chosen.
    final ProviderContainer container = containerWith(
      saved(from: DateTime(2026, 9, 4), to: DateTime(2026, 9, 13)),
    );
    addTearDown(container.dispose);

    container.read(shoppingRangeProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    container
        .read(shoppingRangeProvider.notifier)
        .set(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 7));

    // The list changes underneath, as it does on every tick.
    container.invalidate(shoppingListProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(shoppingRangeProvider), (
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 7),
    ));
  });
}
