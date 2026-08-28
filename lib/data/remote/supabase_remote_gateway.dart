import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/pending_write_store.dart';
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
      await _client.from(table).upsert(payload);
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

  @override
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  }) async {
    try {
      final PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from(entityTable)
          .select();
      final List<Map<String, dynamic>> rows = since == null
          ? await query
          : await query.gte('updated_at', since.toUtc().toIso8601String());

      return <RemoteRecord>[
        for (final Map<String, dynamic> row in rows)
          RemoteRecord(
            id: '${row['id']}',
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
