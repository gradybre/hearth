import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/shopping_store.dart';
import 'package:hearth/domain/planning/week.dart';
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

    // The screen's own order: it watches the list and only builds the body
    // that reads this range once the list has loaded. Reading the range
    // *first* builds the notifier while the list is still loading, which is
    // the one ordering where a listener alone is enough — and reading them
    // that way round is exactly how the first version of this test passed
    // against a fix that did nothing on the phone.
    await container.read(shoppingListProvider.future);

    expect(container.read(shoppingRangeProvider), (from: from, to: to));
  });

  test('even when it arrives after the range is first read', () async {
    // The other order, which happens on a cold open: something reads the
    // range before the list has finished loading.
    final DateTime from = DateTime(2026, 9, 4);
    final DateTime to = DateTime(2026, 9, 13);
    final ProviderContainer container = containerWith(
      saved(from: from, to: to),
    );
    addTearDown(container.dispose);

    container.read(shoppingRangeProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(shoppingRangeProvider), (from: from, to: to));
  });

  test('and the default when there is no list yet', () async {
    final ProviderContainer container = containerWith(null);
    addTearDown(container.dispose);

    await container.read(shoppingListProvider.future);

    final ({DateTime from, DateTime to}) range = container.read(
      shoppingRangeProvider,
    );
    // Compared with the calendar, not with a Duration: `inDays` truncates,
    // so in the week before a spring-forward the gap is 143 hours and this
    // would read as five days — the very arithmetic the other half of this
    // change exists to remove.
    expect(range.to, addDays(range.from, 6));
  });

  test('but a different household hands it back to that list', () async {
    // A range chosen for one household's list means nothing against
    // another's. The notifier object is reused across rebuilds, so the flag
    // that remembers the user's choice has to be cleared with the state it
    // was about — otherwise signing in shows household A's dates over
    // household B's list, for good.
    String household = 'house-a';
    ShoppingListSnapshot current = saved(
      from: DateTime(2026, 9, 4),
      to: DateTime(2026, 9, 13),
    );

    final ProviderContainer container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentHouseholdIdProvider.overrideWith((Ref ref) => household),
        shoppingListProvider.overrideWith((Ref ref) async => current),
      ],
    );
    addTearDown(container.dispose);

    await container.read(shoppingListProvider.future);
    container.read(shoppingRangeProvider);
    container
        .read(shoppingRangeProvider.notifier)
        .set(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 7));

    // Signing in as the other household: a new id, and its own list.
    household = 'house-b';
    current = saved(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 8));
    container.invalidate(currentHouseholdIdProvider);
    container.invalidate(shoppingListProvider);
    await container.read(shoppingListProvider.future);

    expect(container.read(shoppingRangeProvider), (
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 8),
    ));
  });

  test('and hands it back even if that list is still loading', () async {
    // The same switch, but read before the new list has arrived — so the
    // range comes from the listener rather than from the synchronous read,
    // and the listener is the half the remembered choice would silence.
    String household = 'house-a';
    ShoppingListSnapshot current = saved(
      from: DateTime(2026, 9, 4),
      to: DateTime(2026, 9, 13),
    );

    final ProviderContainer container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentHouseholdIdProvider.overrideWith((Ref ref) => household),
        shoppingListProvider.overrideWith((Ref ref) async => current),
      ],
    );
    addTearDown(container.dispose);

    await container.read(shoppingListProvider.future);
    container.read(shoppingRangeProvider);
    container
        .read(shoppingRangeProvider.notifier)
        .set(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 7));

    household = 'house-b';
    current = saved(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 8));
    container.invalidate(currentHouseholdIdProvider);
    container.invalidate(shoppingListProvider);

    // Read while the new list is still in flight, then let it land.
    container.read(shoppingRangeProvider);
    await container.read(shoppingListProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(shoppingRangeProvider), (
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 8),
    ));
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

    await container.read(shoppingListProvider.future);
    container.read(shoppingRangeProvider);

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
