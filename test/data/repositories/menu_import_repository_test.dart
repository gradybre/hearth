import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/menu_import_repository.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/foods/menu_provenance.dart';

/// Recording where a menu came from (review N08).
void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late MenuImportRepository repository;

  final DateTime now = DateTime.utc(2026, 9, 11, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = MenuImportRepository(
      database: db,
      queue: queue,
      householdId: 'household-1',
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  test('a menu remembers where it came from', () async {
    await repository.record(
      restaurant: 'Chopt',
      itemCount: 44,
      source: 'chopt.com/nutrition',
      documentDate: DateTime(2026, 3, 4),
    );

    final MenuProvenance? saved = await repository.forRestaurant('Chopt');
    expect(saved!.itemCount, 44);
    expect(saved.source, 'chopt.com/nutrition');
    expect(saved.documentDate, DateTime(2026, 3, 4));
  });

  test('and is found however the name was typed', () async {
    // Keyed on the normalised brand, which is what the menu itself is grouped
    // by — otherwise "Chopt" and "chopt " would describe two menus.
    await repository.record(restaurant: 'Chopt', itemCount: 44);

    expect(await repository.forRestaurant('  chopt '), isNotNull);
  });

  test('a second import replaces the first rather than adding a row', () async {
    // One row per restaurant. The question is "whose numbers are these and
    // how old are they", which the latest reading settles.
    await repository.record(restaurant: 'Chopt', itemCount: 44);
    await repository.record(
      restaurant: 'Chopt',
      itemCount: 51,
      source: 'a PDF',
    );

    expect(await db.select(db.menuImports).get(), hasLength(1));
    expect((await repository.forRestaurant('Chopt'))!.itemCount, 51);
  });

  test('and it is queued for the other phone', () async {
    await repository.record(restaurant: 'Chopt', itemCount: 44);

    final List<PendingWriteRow> queued = await db
        .select(db.pendingWrites)
        .get();
    expect(queued.single.entityTable, 'menu_imports');
  });

  test('the document date is sent as a date, not a moment', () async {
    // What is printed on a nutrition sheet is a day. Sending a timestamp
    // would invent a time it never had, and the column is a `date`.
    await repository.record(
      restaurant: 'Chopt',
      itemCount: 1,
      documentDate: DateTime(2026, 3, 4),
    );

    final PendingWriteRow queued =
        (await db.select(db.pendingWrites).get()).single;
    expect(queued.payload, contains('"document_date":"2026-03-04"'));
  });

  dateParsing();

  test('two households do not see each other\'s menus', () async {
    await repository.record(restaurant: 'Chopt', itemCount: 44);

    final MenuImportRepository theirs = MenuImportRepository(
      database: db,
      queue: queue,
      householdId: 'household-2',
      clock: () => now,
    );

    expect(await theirs.forRestaurant('Chopt'), isNull);
  });
}

/// A date arriving from the other phone is a date, not a moment (review N08).
///
/// `document_date` is a Postgres `date` — "2026-03-04", no time and no zone.
/// Run through the timestamp parser the other columns use it becomes an
/// instant and then a UTC one, which for anyone east of Greenwich lands on
/// the previous day: a menu printed on the 4th reads as the 3rd. The same
/// class of bug `calendarDaysBetween` exists for.
void dateParsing() {
  test('a document date survives the trip as the day it was', () async {
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    await RemoteRows(db).applyMenuImport(<String, Object?>{
      'id': 'import-1',
      'household_id': 'household-1',
      'restaurant_key': 'chopt',
      'restaurant': 'Chopt',
      'item_count': 44,
      'document_date': '2026-03-04',
      'imported_at': '2026-09-11T12:00:00Z',
      'updated_at': '2026-09-11T12:00:00Z',
    });

    // The whole date, not its year, month and day read off an instant that
    // happens to land right here. Checking the parts passes in every zone
    // west of Greenwich whatever the code does, which is worse than no test
    // — the machine that would catch it is in Sydney.
    final MenuImportRow row = (await db.select(db.menuImports).get()).single;
    expect(
      row.documentDate,
      DateTime(2026, 3, 4),
      reason: 'a date pushed through a timestamp parser becomes an instant',
    );
  });
}
