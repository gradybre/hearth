import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';

/// What the label reader is doing, and what it has to work with (spec §5.5).
///
/// The photo lives *in* the state rather than beside it, for the reason the
/// recipe import learned the hard way: state a screen renders belongs in the
/// state, or picking a picture changes nothing Riverpod can see.
@immutable
sealed class LabelScanState {
  const LabelScanState({this.photo});

  /// Kept through a failure on purpose — that is the whole of what failing
  /// soft means here. Dropped the moment a reading succeeds (spec §8,
  /// "originals discarded after successful extraction").
  final PickedPhoto? photo;

  bool get hasPhoto => photo != null;
}

class LabelScanIdle extends LabelScanState {
  const LabelScanIdle({super.photo});
}

class LabelScanReading extends LabelScanState {
  const LabelScanReading({super.photo});
}

class LabelScanDone extends LabelScanState {
  const LabelScanDone(this.reading);
  final LabelReading reading;
}

/// It did not work, and what the user can do about it.
class LabelScanFailed extends LabelScanState {
  const LabelScanFailed(this.message, {required this.canRetry, super.photo});

  final String message;
  final bool canRetry;
}

/// Reading a nutrition label off a photo (spec §5.5).
///
/// Deliberately one photo rather than several. A recipe spans pages; a
/// Nutrition Facts panel does not, and asking for more than one shot of the
/// same box would cost more and read no better.
class LabelScanController extends Notifier<LabelScanState> {
  @override
  LabelScanState build() => const LabelScanIdle();

  /// Beyond this the function refuses it anyway. Caught here so the user is
  /// told before waiting on an upload rather than after.
  static const int maxImageBytes = 5 * 1024 * 1024;

  PickedPhoto? _photo;
  int _run = 0;

  /// Takes or chooses a photo and reads it in one go.
  ///
  /// One action rather than pick-then-read: there is nothing to arrange
  /// between the two, and a second tap for no decision is a second tap.
  Future<void> readFrom(PhotoOrigin origin) async {
    final PickedPhoto? picked = await ref
        .read(photoPickerProvider)
        .pick(origin);
    if (picked == null) return;

    if (picked.bytes.lengthInBytes > maxImageBytes) {
      // Desktop pickers ignore the downscaling the mobile ones apply, so a
      // full-resolution photo can arrive intact.
      state = const LabelScanFailed(
        'That photo is too big to send. One from your phone will be fine.',
        canRetry: false,
      );
      return;
    }

    _photo = picked;
    await read();
  }

  /// Asks again with the photo already chosen.
  Future<void> read() async {
    final PickedPhoto? photo = _photo;
    if (photo == null) return;

    final int run = ++_run;
    final LabelReader? reader = ref.read(labelReaderProvider);
    if (reader == null) {
      state = LabelScanFailed(
        "Reading a label needs a connection to Hearth's server, and this "
        'build has none configured.',
        canRetry: false,
        photo: photo,
      );
      return;
    }

    state = LabelScanReading(photo: photo);

    try {
      final LabelReading reading = await reader.read(<AiImage>[
        AiImage(bytes: photo.bytes, mediaType: _mediaTypeOf(photo)),
      ]);
      if (_run != run) return;

      // The original has done its job and is not kept (spec §8).
      _photo = null;
      state = LabelScanDone(reading);
    } on RecipeAiException catch (error) {
      if (_run != run) return;
      state = LabelScanFailed(
        error.message,
        canRetry: error.isRetryable,
        photo: photo,
      );
    } on Object {
      if (_run != run) return;
      state = LabelScanFailed(
        'That did not go through. Your photo is still here.',
        canRetry: true,
        photo: photo,
      );
    }
  }

  void reset() {
    _run++;
    _photo = null;
    state = const LabelScanIdle();
  }

  static String _mediaTypeOf(PickedPhoto photo) => switch (photo.extension) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

final NotifierProvider<LabelScanController, LabelScanState> labelScanProvider =
    NotifierProvider<LabelScanController, LabelScanState>(
      LabelScanController.new,
    );
