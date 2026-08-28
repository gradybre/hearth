import 'package:meta/meta.dart';

import '../local/pending_write_store.dart';

/// A record as the server holds it.
@immutable
class RemoteRecord {
  const RemoteRecord({
    required this.id,
    required this.updatedAt,
    required this.payload,
  });

  final String id;

  /// What whole-record last-write-wins compares (spec §7.1).
  final DateTime updatedAt;

  final Map<String, Object?> payload;
}

/// Thrown when a push could not reach the server. The write stays queued.
class RemoteUnavailable implements Exception {
  const RemoteUnavailable(this.message);

  final String message;

  @override
  String toString() => 'RemoteUnavailable: $message';
}

/// The seam between the data layer and Supabase.
///
/// An interface rather than a direct client call so sync can be tested without
/// a network, and so the offline paths — the ones that matter in a kitchen and
/// a supermarket — can be exercised deterministically.
abstract interface class RemoteGateway {
  /// Sends one queued write. Throws [RemoteUnavailable] when offline; any
  /// other exception is treated as a real failure and recorded against the
  /// write.
  Future<void> push({
    required String entityTable,
    required String entityId,
    required WriteOperation operation,
    required Map<String, Object?> payload,
  });

  /// Records changed at or after [since], for the pull half of a sync.
  Future<List<RemoteRecord>> fetchChanged({
    required String entityTable,
    DateTime? since,
  });
}
