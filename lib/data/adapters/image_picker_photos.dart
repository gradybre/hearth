import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_picker.dart';

/// The real photo picker.
class ImagePickerPhotos implements PhotoPicker {
  ImagePickerPhotos({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Long edge to downscale to on the way in.
  ///
  /// A hero photo is read at arm's length on a phone; the extra pixels of a
  /// modern camera cost storage and decode time and buy nothing. Honoured by
  /// the mobile pickers only — the desktop ones hand back the file as it is,
  /// which is why the store keeps a size limit of its own.
  static const double maxEdge = 1600;
  static const int quality = 85;

  final ImagePicker _picker;

  @override
  bool get canUseCamera => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    final XFile? file = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxEdge,
      maxHeight: maxEdge,
      imageQuality: quality,
    );
    if (file == null) return null;

    final Uint8List bytes = await file.readAsBytes();
    return PickedPhoto(bytes: bytes, extension: _extensionOf(file.name));
  }

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 3}) async {
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: maxEdge,
      maxHeight: maxEdge,
      imageQuality: quality,
      limit: max,
    );

    // Capped again here: `limit` is a hint the platform pickers are free to
    // ignore, and the pages of one recipe are the first few chosen.
    return <PickedPhoto>[
      for (final XFile file in files.take(max))
        PickedPhoto(
          bytes: await file.readAsBytes(),
          extension: _extensionOf(file.name),
        ),
    ];
  }

  /// Falls back to jpg rather than guessing from the bytes: the extension only
  /// names the file, and every viewer here decodes by content anyway.
  static String _extensionOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'jpg';
    final String ext = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'jpg';
  }
}
