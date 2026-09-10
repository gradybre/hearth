import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import 'generated_migrations/schema.dart';

/// A real historical upgrade, from a real old schema (CLAUDE.md rule 8).
///
/// `migration_replay_test.dart` winds `user_version` back on today's tables,
/// which is the *half-applied* state an interrupted upgrade leaves — the
/// state that once stopped the app opening its own database. It is not an old
/// database, and it said so.
///
/// This is the other half, and it only became possible when a second snapshot
/// existed: drift builds a database at v25 exactly as v25 was, runs the real
/// migration against it, and checks the result against v26 exactly as v26 is.
/// A step that creates a table the old schema already had, or forgets one the
/// new schema needs, fails here rather than on somebody's phone.
///
/// Every future schema change gets one of these for free, provided the two
/// `drift_dev schema` commands in rule 8 are run.
void main() {
  test('v25 upgrades to v26 and matches the recorded schema', () async {
    final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());

    final InitializedSchema old = await verifier.schemaAt(25);
    final HearthDatabase db = HearthDatabase.forTesting(old.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 26);
  });

  test('and a database already holding rows keeps them', () async {
    // The half that matters on a phone. A schema that validates is not the
    // same as a schema that kept the year of logs already in it, and an
    // additive step that quietly rebuilt a table would pass the check above.
    final SchemaVerifier verifier = SchemaVerifier(GeneratedHelper());
    final InitializedSchema old = await verifier.schemaAt(25);

    old.rawDatabase.execute(
      'INSERT INTO recipes (id, household_id, title, servings, kind, '
      'is_deleted, updated_at) VALUES '
      "('r1', 'h1', 'Weeknight chilli', 4, 'cooked', 0, 0)",
    );

    final HearthDatabase db = HearthDatabase.forTesting(old.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 26);

    final List<RecipeRow> kept = await db.select(db.recipes).get();
    expect(kept.single.title, 'Weeknight chilli');
  });
}
