import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Where a photo is coming from.
enum PhotoOrigin { camera, library }

/// A photo the user chose.
@immutable
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// Lower-case, no dot — 'jpg', 'png', 'heic'.
  final String extension;
}

/// Choosing a recipe photo (spec §5.2).
///
/// An interface so the editor can be exercised without a platform channel: a
/// widget test cannot open a camera, and the screen's behaviour around a photo
/// is worth testing regardless.
abstract interface class PhotoPicker {
  /// Whether this device can take a photo as well as choose one.
  ///
  /// Desktop cannot, and offering a camera button that opens a file dialog is
  /// worse than not offering one.
  bool get canUseCamera;

  /// Null when the user backed out without choosing.
  Future<PickedPhoto?> pick(PhotoOrigin origin);
}
