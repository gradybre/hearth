import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

void main() {
  test('the local schema opens and enforces foreign keys', () async {
    final HearthDatabase db = HearthDatabase.forTesting(
      NativeDatabase.memory(),
    );
    addTearDown(db.close);

    // Cascade deletes are declared on the child tables; without the pragma
    // they would silently do nothing and orphan rows on every recipe delete.
    final List<QueryRow> rows = await db
        .customSelect('PRAGMA foreign_keys')
        .get();
    expect(rows.single.data.values.first, 1);
  });
}
