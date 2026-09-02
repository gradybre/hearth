import 'dart:typed_data';

import 'package:hearth/data/remote/photo_storage.dart';
import 'package:hearth/data/remote/remote_gateway.dart';

/// A bucket that can be told to be offline, to fail, or to have lost a file.
///
/// Hand-written rather than mocked, matching the `FakeGateway`s the sync tests
/// already use: the paths that matter here are the ones a supermarket basement
/// produces, and they are easier to *state* than to arrange.
class FakePhotoStorage implements PhotoStorage {
  final Map<String, Uint8List> objects = <String, Uint8List>{};

  bool offline = false;

  /// Thrown by the next call, once, when set.
  Object? failWith;

  /// Paths that answer as though the object had been deleted.
  final Set<String> missing = <String>{};

  final List<String> uploaded = <String>[];
  final List<String> downloaded = <String>[];

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (offline) throw const RemoteUnavailable('offline');
    if (failWith case final Object error) {
      failWith = null;
      throw error;
    }
    objects[path] = bytes;
    uploaded.add(path);
  }

  @override
  Future<Uint8List> download(String path) async {
    if (offline) throw const RemoteUnavailable('offline');
    if (failWith case final Object error) {
      failWith = null;
      throw error;
    }
    if (missing.contains(path) || !objects.containsKey(path)) {
      throw PhotoObjectMissing(path);
    }
    downloaded.add(path);
    return objects[path]!;
  }
}
