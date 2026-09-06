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

  Future<void> _delete(
    String table,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    final List<String> keys = deleteKeys[table] ?? const <String>['id'];
    PostgrestFilterBuilder<void> query = _client.from(table).delete();
    for (final String key in keys) {
      final Object? value = payload[key] ?? (key == 'id' ? entityId : null);
      if (value == null) {
        // Refusing beats guessing: a delete with a missing key would match
        // every row the policy allows.
        throw StateError('Cannot delete from $table without $key.');
      }
      query = query.eq(key, value);
    }
    await query;
  }

  /// What a table is sorted and paged by.
  ///
  /// Always ends in something unique, because a cursor that cannot move is a
  /// loop that never ends. Most tables page by `(updated_at, id)`; the two
  /// join tables carry no timestamp at all, so they page by their pair — the
  /// same columns that identify them for a delete.
  static List<String> pageOrderFor(String entityTable) =>
      deleteKeys[entityTable] ??
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
      // Deliberately untyped. Asking for a generic here makes the call site
      // depend on exactly how the driver decodes a `setof jsonb`, and getting
      // that wrong fails as an empty result rather than an error — a sync that
      // reports success and brings nothing down.
      final Object? response = await _client.rpc<Object?>(
        aggregate.function,
        params: <String, Object?>{
          aggregate.parameter: since?.toUtc().toIso8601String(),
        },
      );

      if (response is! List) {
        throw StateError(
          '${aggregate.function} returned ${response.runtimeType}, '
          'not a list of records.',
        );
      }

      return <RemoteRecord>[
        for (final Object? row in response)
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
  static bool _looksLikeOutage(PostgrestException error) {
    final String message = error.message.toLowerCase();
    return error.code == null ||
        message.contains('failed host lookup') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('network');
  }
}
