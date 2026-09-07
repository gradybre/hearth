@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:hearth/data/repositories/ingredient_match_repository.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Forgetting a wording reaches the row that holds it (spec §5.3).
///
/// The one that could only be proved here. The delete filtered on the id, and
/// a row written before that id was derived carries a random one — so the
/// update matched nothing, PostgREST answered 204, the queue cleared, and the
/// answer stayed on the partner's phone still answering. Every layer reported
/// success; only the row disagreed.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  const String url = 'http://127.0.0.1:54321';
  final bool live = Platform.environment['HEARTH_LIVE'] == '1';
  final String? key = live ? _publishableKey() : null;
  final String? skip = key == null ? 'supabase not running' : null;

  late SupabaseClient client;
  late HearthDatabase db;
  late String householdId;

  setUpAll(() async {
    HttpOverrides.global = null;
    if (key == null) return;
    client = SupabaseClient(url, key);
    await client.auth.signInWithPassword(
      email: 'pull@hearth.test',
      password: 'HearthPull2026a',
    );
    final List<Map<String, dynamic>> houses = await client
        .from('households')
        .select('id')
        .limit(1);
    householdId = '${houses.single['id']}';
  });

  setUp(() {
    if (key == null) return;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    if (key == null) return;
    await db.close();
  });

  test('even when the row predates the derived id', () async {
    const String wording = 'evoo';

    // A row as an older build wrote it: the right household and wording, an
    // id that is nobody's derivation.
    final String legacyId = '00000000-0000-4000-8000-00000000beef';
    await client
        .from('ingredient_matches')
        .delete()
        .eq('household_id', householdId);
    await client.from('ingredient_matches').insert(<String, Object?>{
      'id': legacyId,
      'household_id': householdId,
      'ingredient_string': wording,
      'needs_no_match': true,
    });

    // The household forgets it.
    final PendingWriteStore queue = PendingWriteStore(db);
    await IngredientMatchRepository(
      database: db,
      store: IngredientMatchStore(db),
      queue: queue,
      householdId: householdId,
    ).forget(wording);

    final SyncEngine engine = SyncEngine(
      queue: queue,
      gateway: SupabaseRemoteGateway(client),
    );
    final SyncResult pushed = await engine.push();
    expect(pushed.failed, 0, reason: 'the delete did not reach the server');

    final List<Map<String, dynamic>> after = await client
        .from('ingredient_matches')
        .select('id, is_deleted')
        .eq('household_id', householdId)
        .eq('ingredient_string', wording);

    // Length first, so a row that was removed rather than flagged fails as
    // "no row" rather than as an unreadable error inside `single`.
    expect(after, hasLength(1), reason: 'the row was removed, not recorded');
    expect(
      after.single['is_deleted'],
      isTrue,
      reason:
          'the row is still answering: the delete filtered on an id this row '
          'never had, matched nothing, and reported success',
    );
  }, skip: skip);
}

/// The local stack's publishable key, from the gitignored config the app
/// itself runs with.
String? _publishableKey() {
  final File file = File('config/local.json');
  if (!file.existsSync()) return null;
  final RegExp pattern = RegExp('"SUPABASE_PUBLISHABLE_KEY"\\s*:\\s*"([^"]+)"');
  return pattern.firstMatch(file.readAsStringSync())?.group(1);
}
