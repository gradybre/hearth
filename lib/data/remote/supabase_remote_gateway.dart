import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/pending_write_store.dart';
import 'page_cursor.dart';
import 'remote_gateway.dart';

/// The real sync target (spec §7.1).
///
/// Nothing here decides *what* to send or in what order — that is the sync
/// engine's job. This only knows how one queued write becomes one Supabase
/// call, and how to tell "the network is not there" apart from "the server
/// refused this". The difference matters: the first leaves the write queued to
/// try again, the second must not retry forever.
class SupabaseRemoteGateway implements RemoteGateway {
  SupabaseRemoteGateway(this._client);

  /// Tables whose whole aggregate goes through a function, because they are
  /// more than one table underneath and must land whole (see the migration).
  ///
  /// The parameter name is spelled out rather than derived from the table:
  /// deriving it would work until the first table whose singular is not "drop
  /// the s", and fail as a runtime error nobody would connect to this line.
  static const Map<String, ({String function, String parameter})>
  aggregateFunctions = <String, ({String function, String parameter})>{
    'recipes': (function: 'upsert_recipe', parameter: 'p_recipe'),
    'foods': (function: 'upsert_food', parameter: 'p_food'),
  };

  /// What identifies a row for a delete. Most are keyed by id; the join tables
  /// are keyed by the pair, which is also why their queued entityId is a
  /// composite string rather than something to send.
  static const Map<String, List<String>> deleteKeys = <String, List<String>>{
    'recipe_favorites': <String>['user_id', 'recipe_id'],
    'recipe_collections': <String>['collection_id', 'recipe_id'],
    // The pair its upsert resolves on, and for the same reason: a row written
    // by an older build carries a random id rather than the derived one, so
    // filtering a delete on the id misses it. The write then succeeds against
    // nothing, the queue clears, and the wording stays on the other phone —
    // still answering something the household said to stop answering.
    'ingredient_matches': <String>['household_id', 'ingredient_string'],
  };

  /// What a table is sorted and paged by, when it is not `(updated_at, id)`.
  ///
  /// Its own map rather than [deleteKeys], which it used to read. Those two
  /// happen to agree for the join tables and have no reason to in general —
  /// and while they were one map, giving a table a delete filter silently
  /// re-sorted its pull. Keyset paging wants an order ending in something
  /// unique where a row written mid-pull sorts to the end (#18); a delete
  /// wants whatever identifies the row. Different questions.
  static const Map<String, List<String>> pageOrders = <String, List<String>>{
    // No timestamp at all on these two, so the pair is all they have.
    'recipe_favorites': <String>['user_id', 'recipe_id'],
    'recipe_collections': <String>['collection_id', 'recipe_id'],
  };

  /// Tables that record a deletion rather than removing the row (spec §7.1).
  ///
  /// A plain select only ever returns rows that exist, so there is nothing in
  /// one that says "this used to be here" — which is why a meal deleted on
  /// one phone stayed on the other for ever. These five now do what recipes
  /// and foods have always done: the row stays, the flag turns, and the
  /// ordinary pull carries it across like any other change.
  ///
  /// The two membership tables are deliberately absent. They are fetched
  /// whole every pass and reconciled by replacement, so absence there is
  /// already read correctly as removal; a flag as well would be a second
  /// mechanism for the same fact, and the two would eventually disagree.
  static const Set<String> softDeleteTables = <String>{
    'meal_plan_entries',
    'shopping_list_items',
    'collections',
    'plan_templates',
    'ingredient_matches',
  };

  /// Tables whose upsert must resolve on a unique constraint rather than on
  /// the primary key.
  ///
  /// `ingredient_matches` is unique on (household, wording), and two phones
  /// can decide the same wording independently. Their rows now share a derived
  /// id so they agree, but a row written before that — or by an older build —
  /// would otherwise be refused for ever by the unique index rather than
  /// updating the row already there.
  static const Map<String, String> upsertConflictTargets = <String, String>{
    'ingredient_matches': 'household_id,ingredient_string',
    // Same shape, same reason. `macro_targets` is unique on (user, week) and
    // keyed on the id, and two phones setting this week's targets offline
    // each minted their own — so the second to arrive was refused by the
    // unique key rather than updating the row that was already there.
    //
    // New rows derive their id now (see `PlanStore.idFor`), but a row written
    // before that, or by an older build, still carries a random one. Resolving
    // on the pair the key is on is what lets those meet.
    'macro_targets': 'user_id,week_start_date',
  };

  /// What identifies a row on the way *in*, when it is not `id`.
  ///
  /// The food profile is one row per user and the server keys it that way, so
  /// there is no separate id to read. Getting this wrong is quiet: every
  /// record would arrive with the id "null", collide with the last one, and
  /// last-write-wins would compare a row against itself.
  static const Map<String, String> keyColumns = <String, String>{
    'food_profiles': 'user_id',
  };

  /// The functions that return whole aggregates for the pull half.
  static const Map<String, ({String function, String parameter})>
  pullFunctions = <String, ({String function, String parameter})>{
    'recipes': (function: 'changed_recipes', parameter: 'p_since'),
    'foods': (function: 'changed_foods', parameter: 'p_since'),
  };

  final SupabaseClient _client;

  @override
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  }) async {
    try {
      switch (operation) {
        case WriteOperation.upsert:
          await _upsert(entityTable, payload);
        case WriteOperation.delete:
          await _delete(entityTable, entityId, payload);
      }
    } on SocketException catch (error) {
      throw RemoteUnavailable(error.message);
    } on TimeoutException catch (error) {
      throw RemoteUnavailable('$error');
    } on PostgrestException catch (error) {
      // A refusal, not an outage. Let it fail the write so it stops being
      // retried and the reason is recorded against it.
      if (_looksLikeOutage(error)) throw RemoteUnavailable(error.message);
      rethrow;
    }
  }

  Future<void> _upsert(String table, Map<String, Object?> payload) async {
    final ({String function, String parameter})? aggregate =
        aggregateFunctions[table];
    if (aggregate == null) {
      final String? onConflict = upsertConflictTargets[table];
      await _client.from(table).upsert(payload, onConflict: onConflict);
      return;
    }
    await _client.rpc<void>(
      aggregate.function,
      params: <String, Object?>{aggregate.parameter: payload},
    );
  }

  /// What a deletion actually writes, for a table that records one.
  ///
  /// The writer's own clock travels with it. The server records that as
  /// `deleted_at`, and an upsert may only clear the flag with a write made
  /// after it — which is how an edit left unsent in an outbox stops undoing a
  /// deliberate deletion (spec §7.1).
  ///
  /// A payload from an older build states no time; the server falls back to
  /// its own clock rather than refusing the write, so the deletion still
  /// happens and only the comparison is a little less exact.
  ///
  /// Separated out to be readable on its own: it is the one line that carries
  /// the client's clock onto the wire, and it sits inside a call that needs a
  /// live Postgrest to exercise.
  static Map<String, Object?> softDeletePatch(Map<String, Object?> payload) =>
      <String, Object?>{
        'is_deleted': true,
        if (payload['updated_at'] != null) 'updated_at': payload['updated_at'],
      };

  /// Which columns and values name the row this delete is for.
  ///
  /// Pure and static so the choice can be read and tested on its own, like
  /// [softDeletePatch]: getting it wrong is silent against a real server,
  /// which answers 204 whether it matched a row or nothing at all.
  ///
  /// A payload that predates the columns this table now filters on falls back
  /// to the id it does carry. That is the queue's upgrade path, not a
  /// nicety: a `forget` queued by the previous build is already sitting in
  /// the outbox when the new build starts, and refusing it outright would
  /// take out far more than the deletion — see the note in [SyncEngine.push].
  /// The fallback is narrower than the filter it replaces, never wider, so it
  /// cannot delete anything the queue did not ask for; the only thing it
  /// gives up is reaching a row whose id was never derived, which is exactly
  /// what that older build did anyway.
  static Map<String, Object?> deleteFilter(
    String table,
    String entityId,
    Map<String, Object?> payload,
  ) {
    final List<String> keys = deleteKeys[table] ?? const <String>['id'];
    final Map<String, Object?> filter = <String, Object?>{
      for (final String key in keys)
        if (payload[key] ?? (key == 'id' ? entityId : null)
            case final Object value)
          key: value,
    };
    if (filter.length == keys.length) return filter;

    // Only an `id` the payload itself carries. Never [entityId], which for a
    // table keyed by a pair is a composite string the queue made up to have
    // one — filtering on it would name a column these tables do not have.
    if (payload['id'] case final Object id) return <String, Object?>{'id': id};

    // Refusing beats guessing: a delete with a missing key would match every
    // row the policy allows.
    throw RemoteRefused(
      'Cannot delete from $table without ${keys.join(' and ')}.',
    );
  }

  Future<void> _delete(
    String table,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    // A recorded deletion rather than a removal, for the tables that have
    // somewhere to record it. The filter is built the same way either way, so
    // a missing key is still refused rather than matching every row.
    PostgrestFilterBuilder<void> query = softDeleteTables.contains(table)
        ? _client.from(table).update(softDeletePatch(payload))
        : _client.from(table).delete();
    deleteFilter(table, entityId, payload).forEach((String key, Object? value) {
      query = query.eq(key, value!);
    });
    await query;
  }

  /// What a table is sorted and paged by.
  ///
  /// Always ends in something unique, because a cursor that cannot move is a
  /// loop that never ends. Most tables page by `(updated_at, id)`; the two
  /// join tables carry no timestamp at all, so they page by their pair — the
  /// same columns that identify them for a delete.
  static List<String> pageOrderFor(String entityTable) =>
      pageOrders[entityTable] ??
      <String>['updated_at', keyColumns[entityTable] ?? 'id'];

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async {
    final List<String> order = pageOrderFor(entityTable);

    try {
      final List<Map<String, dynamic>> rows =
          await readAllPages<Map<String, dynamic>>(
            page: (PageCursor? after) =>
                _page(entityTable, order: order, since: since, after: after),
            cursorOf: (Map<String, dynamic> row) =>
                PageCursor(<String>[for (final String c in order) '${row[c]}']),
          );

      return <RemoteRecord>[
        for (final Map<String, dynamic> row in rows)
          RemoteRecord(
            id: '${row[keyColumns[entityTable] ?? 'id']}',
            updatedAt:
                DateTime.tryParse('${row['updated_at']}')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            payload: row,
          ),
      ];
    } on SocketException catch (error) {
      throw RemoteUnavailable(error.message);
    } on TimeoutException catch (error) {
      throw RemoteUnavailable('$error');
    }
  }

  /// One page: everything sorted after [after], oldest first.
  Future<List<Map<String, dynamic>>> _page(
    String entityTable, {
    required List<String> order,
    required DateTime? since,
    required PageCursor? after,
  }) async {
    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from(entityTable)
        .select();

    if (since != null) {
      query = query.gte('updated_at', since.toUtc().toIso8601String());
    }
    if (after != null) {
      query = query.or(_keysetAfter(order, after));
    }

    PostgrestTransformBuilder<List<Map<String, dynamic>>> sorted = query.order(
      order.first,
      ascending: true,
    );
    for (final String column in order.skip(1)) {
      sorted = sorted.order(column, ascending: true);
    }
    return sorted.limit(_pageSize);
  }

  /// The keyset predicate for a composite sort key.
  ///
  /// `(a, b) > (A, B)` written the long way, because PostgREST has no tuple
  /// comparison: either `a` is past `A`, or it matches and `b` is past `B`.
  /// Values are quoted — a timestamp is full of characters the filter grammar
  /// would otherwise read as syntax.
  static String _keysetAfter(List<String> order, PageCursor after) {
    final List<String> clauses = <String>[];
    for (int i = 0; i < order.length; i++) {
      final List<String> equals = <String>[
        for (int j = 0; j < i; j++) '${order[j]}.eq."${after.values[j]}"',
      ];
      final String greater = '${order[i]}.gt."${after.values[i]}"';
      clauses.add(
        equals.isEmpty ? greater : 'and(${equals.join(',')},$greater)',
      );
    }
    return clauses.join(',');
  }

  /// One page of an aggregate, from the paged function.
  ///
  /// A `setof jsonb` has nowhere for a client to put a cursor, so unlike the
  /// plain selects this needs the server's help: `changed_*_page` takes the
  /// last row seen and returns what sorts after it.
  Future<List<Object?>> _aggregatePage(
    ({String function, String parameter}) aggregate,
    DateTime? since,
    PageCursor? after,
  ) async {
    // Deliberately untyped. Asking for a generic here makes the call site
    // depend on exactly how the driver decodes a `setof jsonb`, and getting
    // that wrong fails as an empty result rather than an error — a sync that
    // reports success and brings nothing down.
    final Object? response = await _client.rpc<Object?>(
      '${aggregate.function}_page',
      params: <String, Object?>{
        aggregate.parameter: since?.toUtc().toIso8601String(),
        'p_after_updated_at': after?.values.first,
        'p_after_id': after == null ? null : after.values[1],
        'p_limit': _pageSize,
      },
    );

    if (response is! List) {
      throw StateError(
        '${aggregate.function}_page returned ${response.runtimeType}, '
        'not a list of records.',
      );
    }
    return response;
  }

  /// Rows per request. Well under any plausible `max_rows`, so a page is a
  /// page rather than a silent truncation — and if the server caps it lower
  /// anyway, [readAllPages] simply asks again.
  static const int _pageSize = 500;

  @override
  Future<List<RemoteRecord>> fetchChangedAggregates({
    required String entityTable,
    DateTime? since,
  }) async {
    final ({String function, String parameter})? aggregate =
        pullFunctions[entityTable];
    if (aggregate == null) {
      throw ArgumentError.value(
        entityTable,
        'entityTable',
        'has no aggregate pull function',
      );
    }

    try {
      final List<Object?> rows = await readAllPages<Object?>(
        page: (PageCursor? after) => _aggregatePage(aggregate, since, after),
        cursorOf: (Object? row) => PageCursor(<String>[
          '${(row! as Map)['updated_at']}',
          '${(row as Map)['id']}',
        ]),
      );

      return <RemoteRecord>[
        for (final Object? row in rows)
          if (row is Map)
            RemoteRecord(
              id: '${row['id']}',
              updatedAt:
                  DateTime.tryParse('${row['updated_at']}')?.toUtc() ??
                  DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              payload: <String, Object?>{
                for (final MapEntry<Object?, Object?> entry in row.entries)
                  '${entry.key}': entry.value,
              },
            ),
      ];
    } on SocketException catch (error) {
      throw RemoteUnavailable(error.message);
    } on TimeoutException catch (error) {
      throw RemoteUnavailable('$error');
    }
  }

  /// Postgrest reports a dead connection as an exception like any other, so
  /// the shape has to be read rather than the type.
  /// Whether this is the server being unreachable rather than refusing.
  ///
  /// The distinction now costs something: a refusal spends one of a write's
  /// few attempts, and a write that spends them all stops being sent at all
  /// (spec §7.1). So a condition that will pass on its own must not look like
  /// a refusal — a deploy window where an RPC is briefly missing, a session
  /// expiring a moment before it refreshes, or the server having five minutes
  /// of trouble. None of those are anything the write did wrong, and all of
  /// them would otherwise burn a phone's whole outbox in under a minute,
  /// because passes are triggered by local writes rather than by a clock.
  static bool _looksLikeOutage(PostgrestException error) {
    final String message = error.message.toLowerCase();
    final int? status = int.tryParse(error.code ?? '');
    return error.code == null ||
        // Anything the server says is its own fault, not the request's.
        (status != null && status >= 500) ||
        // A session that has aged out. The client refreshes it and the very
        // next pass succeeds; charging the write for that would stop it being
        // sent over something that fixed itself.
        error.code == 'PGRST301' ||
        // A function the database has not been given yet. Server-first is the
        // deploy order, but a build that gets ahead of a migration should
        // wait for it rather than throw the queue away — see the deploy-order
        // note in docs/SYNC_DESIGN.md.
        error.code == 'PGRST202' ||
        error.code == '42883' ||
        message.contains('failed host lookup') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('network');
  }
}
