import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'remote_gateway.dart';

/// The object is not there.
///
/// Distinct from [RemoteUnavailable], which means "ask again later". This one
/// means asking again will get the same answer, so retrying is waste.
@immutable
class PhotoObjectMissing implements Exception {
  const PhotoObjectMissing(this.path);
  final String path;

  @override
  String toString() => 'PhotoObjectMissing($path)';
}

/// Where a recipe's photo lives for the whole household (spec §5.2, rule 7).
///
/// An interface so the sync pass can be exercised without a network — the
/// paths that matter are the ones a supermarket basement produces, and none of
/// them are reachable through a real Supabase client in a unit test.
abstract interface class PhotoStorage {
  /// Uploads [bytes] to [path]. Throws [RemoteUnavailable] when offline.
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  });

  /// Throws [PhotoObjectMissing] when the object is gone.
  Future<Uint8List> download(String path);
}

/// Where a photo sits in the bucket, and how to read that back.
///
/// `<recipe_id>/<uuid>.<ext>`. The recipe id leads because the storage policy
/// derives the household from it — see the migration for why it is keyed on
/// the recipe rather than the household.
abstract final class RecipePhotoPath {
  static const String bucket = 'recipe-photos';

  /// Every upload gets a fresh [objectId], so nothing is ever overwritten.
  ///
  /// That immutability is load-bearing three times over: staleness becomes a
  /// string compare, a partner mid-download of the old object cannot get a
  /// torn read, and two devices photographing the same recipe cannot collide.
  static String build({
    required String recipeId,
    required String objectId,
    required String extension,
  }) => '$recipeId/$objectId.${normaliseExtension(extension)}';

  /// The recipe a path belongs to, or null when it is not one of ours.
  ///
  /// Mirrors what `storage.foldername(name))[1]` does server-side, so a path
  /// this refuses is one the policy would refuse too.
  static String? recipeIdOf(String path) {
    final List<String> parts = path.split('/');
    if (parts.length != 2) return null;
    final String id = parts.first.trim();
    return id.isEmpty ? null : id;
  }

  /// Lower-case, no dot, and only ones the bucket's mime allowlist accepts.
  static String normaliseExtension(String raw) {
    final String ext = raw.toLowerCase().replaceAll('.', '').trim();
    return _contentTypes.containsKey(ext) ? ext : 'jpg';
  }

  /// The mime type for a path or an extension.
  ///
  /// The bucket rejects anything outside its allowlist, so an unknown
  /// extension is called a jpeg rather than sent as something the server will
  /// refuse — the picker only ever produces images in the first place.
  static String contentTypeOf(String pathOrExtension) {
    final String tail = pathOrExtension.split('.').last;
    return _contentTypes[normaliseExtension(tail)] ?? 'image/jpeg';
  }

  static const Map<String, String> _contentTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };
}
