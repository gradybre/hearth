@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/remote/remote_gateway.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Paging a real PostgREST (spec §7.1, R04).
///
/// The loop is unit-tested against a fake server that caps without saying so.
/// What that cannot test is the **filter string**: `_keysetAfter` builds a
/// PostgREST `or=(...)` by hand, with quoted values because a timestamp is
/// full of characters the grammar reads as syntax. A malformed one would not
/// error — PostgREST would answer with an empty result, which this loop reads
/// as "end of table". That is the same silent-empty failure the codebase
/// already documents twice, and only a real server can rule it out.
///
/// Run with: HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  const String url = 'http://127.0.0.1:54321';
  final bool live = Platform.environment['HEARTH_LIVE'] == '1';
  final String? key = live
      ? Platform.environment['HEARTH_PUBLISHABLE_KEY']
      : null;

  late SupabaseClient client;
  late SupabaseRemoteGateway gateway;
  final String runId = DateTime.now().microsecondsSinceEpoch.toString();

  setUpAll(() async {
    HttpOverrides.global = null;
    if (key == null) return;
    client = SupabaseClient(url, key);
    gateway = SupabaseRemoteGateway(client);
    await client.auth.signInWithPassword(
      email: 'pull@hearth.test',
      password: 'HearthPull2026a',
    );
  });

  tearDownAll(() async {
    if (key == null) return;
    await client.from('collections').delete().like('name', 'page-$runId-%');
  });

  test(
    'reads every row past the server row cap',
    () async {
      // More than one page at the gateway's 500, and more than `max_rows`
      // whatever it turns out to be locally. The old code asked once and
      // treated the cap as the whole answer.
      const int count = 1200;
      final String household =
          (await client.from('collections').select('household_id').limit(1))
                  .first['household_id']
              as String;

      await client.from('collections').insert(<Map<String, Object?>>[
        for (int i = 0; i < count; i++)
          <String, Object?>{
            'household_id': household,
            'name': 'page-$runId-${i.toString().padLeft(5, '0')}',
          },
      ]);

      final List<RemoteRecord> rows = await gateway.fetchChanged(
        entityTable: 'collections',
      );
      final Set<String> mine = <String>{
        for (final RemoteRecord r in rows)
          if ('${r.payload['name']}'.startsWith('page-$runId-'))
            '${r.payload['name']}',
      };

      expect(
        mine,
        hasLength(count),
        reason: 'every inserted row must come back, across every page',
      );
    },
    skip: key == null ? 'supabase not running' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
