import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_storage.dart';
import 'remote_gateway.dart';

/// Recipe photos in the household's private bucket (spec §5.2, §8.1).
///
/// The bucket is private and read with the caller's own JWT, so there is no
/// signed URL to store or refresh — and no public link that would sit outside
/// RLS while the client ships a publishable key by design.
class SupabasePhotoStorage implements PhotoStorage {
  SupabasePhotoStorage(this._client);

  final SupabaseClient _client;

  StorageFileApi get _bucket => _client.storage.from(RecipePhotoPath.bucket);

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType),
      );
    } on StorageException catch (error) {
      throw mapStorageError(error, path);
    } on SocketException catch (error) {
      throw RemoteUnavailable(error.message);
    } on TimeoutException catch (error) {
      throw RemoteUnavailable('$error');
    }
  }

  @override
  Future<Uint8List> download(String path) async {
    try {
      return await _bucket.download(path);
    } on StorageException catch (error) {
      throw mapStorageError(error, path);
    } on SocketException catch (error) {
      throw RemoteUnavailable(error.message);
    } on TimeoutException catch (error) {
      throw RemoteUnavailable('$error');
    }
  }

  /// Which failures are worth another go.
  ///
  /// Public because it is the seam worth testing: the network cannot be faked
  /// without faking Supabase's client whole, but the decision about what a
  /// given error *means* is the part that would go quietly wrong.
  ///
  /// A 404 is settled — the object is not there and asking again will not
  /// change that. A 5xx or a connection-shaped message is the supermarket
  /// basement, and retrying for ever is right. Anything else — a 403 from a
  /// policy, a 413 from the size limit — is a real refusal that should stop
  /// after a few tries rather than hammer.
  static Object mapStorageError(StorageException error, String path) {
    final String status = error.statusCode ?? '';
    if (status == '404') return PhotoObjectMissing(path);

    final String message = error.message.toLowerCase();
    final bool outage =
        status.startsWith('5') ||
        message.contains('failed host lookup') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('network');
    return outage ? RemoteUnavailable(error.message) : error;
  }
}
