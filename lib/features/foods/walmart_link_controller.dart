import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../data/adapters/walmart_link_reader.dart';
import '../../domain/shopping/walmart_link_reading.dart';

/// Whether the label reader configured for this build also happens to
/// implement [WalmartLinkReader] (D-WALMART-001, plan P-HEARTH-WALMART-001).
///
/// The two adapters share one server function and one key; whether the
/// Walmart-link path is available in this build is exactly whether the
/// configured label reader is also a [WalmartLinkReader].
final Provider<WalmartLinkReader?> walmartLinkReaderProvider =
    Provider<WalmartLinkReader?>((ref) {
      final Object? reader = ref.watch(labelReaderProvider);
      return reader is WalmartLinkReader ? reader : null;
    });

/// State of reading a Walmart product link off one screenshot
/// (D-WALMART-001).
///
/// One slot only, unlike the label sheet's two: a Walmart link comes from
/// wherever it is visible in a single screenshot, not from a fixed pair of
/// roles.
@immutable
sealed class WalmartLinkScanState {
  const WalmartLinkScanState({this.photo});

  /// Retained only while selecting, reading, or explicitly retrying a failure.
  final PickedPhoto? photo;

  bool get hasPhoto => photo != null;
}

class WalmartLinkScanIdle extends WalmartLinkScanState {
  const WalmartLinkScanIdle({super.photo});
}

/// The system picker is open. Kept distinct from [WalmartLinkScanIdle] so
/// the sheet can disable its buttons while a picker is already showing.
class WalmartLinkScanPicking extends WalmartLinkScanState {
  const WalmartLinkScanPicking({super.photo});
}

class WalmartLinkScanReading extends WalmartLinkScanState {
  const WalmartLinkScanReading({super.photo});
}

/// A usable link was found. Terminal: the sheet closes on this state, and
/// the photo is dropped rather than kept (spec: originals discarded only
/// after a successful extraction).
class WalmartLinkScanFound extends WalmartLinkScanState {
  const WalmartLinkScanFound(this.reading);
  final WalmartLinkReading reading;
}

/// The server looked and found nothing trustworthy:
/// [WalmartLinkStatus.notFound], [WalmartLinkStatus.ambiguous] or
/// [WalmartLinkStatus.unreadable]. Completed reads release the screenshot.
class WalmartLinkScanMiss extends WalmartLinkScanState {
  const WalmartLinkScanMiss(this.status, {super.photo});
  final WalmartLinkStatus status;
}

/// A picker or a network call failed outright. The photo, where one was
/// already chosen, is kept for an explicit retry — never for an automatic
/// one.
class WalmartLinkScanFailed extends WalmartLinkScanState {
  const WalmartLinkScanFailed(
    this.message, {
    required this.canRetry,
    super.photo,
  });

  final String message;
  final bool canRetry;
}

/// Reads a Walmart product link from one screenshot (D-WALMART-001).
///
/// Picking is never followed by an automatic read: choosing the photo and
/// asking the server to read it are two separate, deliberate steps, as in
/// the label reader's controller.
class WalmartLinkScanController extends Notifier<WalmartLinkScanState> {
  @override
  WalmartLinkScanState build() {
    ref.onDispose(() {
      // Nothing in flight can land after this: every generation it might
      // have been waiting on is bumped, and the photo it would have set is
      // gone.
      _pick++;
      _read++;
      _disposed = true;
      _photo = null;
    });
    return const WalmartLinkScanIdle();
  }

  /// Beyond this the function refuses it anyway. Caught here so the user is
  /// told before waiting on an upload rather than after.
  static const int maxImageBytes = 5 * 1024 * 1024;

  PickedPhoto? _photo;

  /// One generation for picking and one for reading: beginning a new pick
  /// invalidates whatever read was in flight for the photo it is about to
  /// replace, and beginning a new read invalidates any earlier one.
  int _pick = 0;
  int _read = 0;
  bool _disposed = false;

  /// Opens the library picker. Never reads on its own.
  Future<void> pick() async {
    if (_disposed) return;
    final int run = ++_pick;
    // Whatever a read was sent for is about to change or be reaffirmed;
    // either way, a response to it landing later would be stale.
    _read++;
    state = WalmartLinkScanPicking(photo: _photo);

    PickedPhoto? picked;
    try {
      picked = await ref.read(photoPickerProvider).pick(PhotoOrigin.library);
    } on Object {
      if (_disposed || run != _pick) return;
      _photo = null;
      state = WalmartLinkScanFailed(
        'That photo could not be opened. Choose it again or enter the link.',
        canRetry: false,
        photo: _photo,
      );
      return;
    }
    if (_disposed || run != _pick) return;

    if (picked == null) {
      // Cancelling the picker leaves whatever was already chosen alone.
      state = WalmartLinkScanIdle(photo: _photo);
      return;
    }

    if (picked.bytes.lengthInBytes > maxImageBytes) {
      // Desktop pickers ignore the downscaling the mobile ones apply, so a
      // full-resolution screenshot can arrive intact.
      _photo = null;
      state = WalmartLinkScanFailed(
        'That photo is too big to send. A screenshot from your phone will '
        'be fine.',
        canRetry: false,
        photo: _photo,
      );
      return;
    }

    if (picked.bytes.isEmpty ||
        !const {
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
        }.contains(picked.extension.toLowerCase())) {
      _photo = null;
      state = const WalmartLinkScanFailed(
        'Choose a PNG, JPEG, GIF, or WebP screenshot with image data.',
        canRetry: false,
      );
      return;
    }
    _photo = picked;
    state = WalmartLinkScanIdle(photo: _photo);
  }

  /// Sends the currently selected screenshot. A no-op with nothing selected
  /// or a read already in flight.
  Future<void> read() async {
    if (_disposed || state is WalmartLinkScanReading) return;
    if (_photo == null) return;

    final int run = ++_read;
    final WalmartLinkReader? reader = ref.read(walmartLinkReaderProvider);
    if (reader == null) {
      _photo = null;
      state = WalmartLinkScanFailed(
        "Reading a link needs a connection to Hearth's server, and this "
        'build has none configured.',
        canRetry: false,
        photo: _photo,
      );
      return;
    }

    state = WalmartLinkScanReading(photo: _photo);

    try {
      final List<AiImage> images = <AiImage>[AiImage.ofPhoto(_photo!)];
      final WalmartLinkReading reading = await reader.readWalmartLink(images);
      // A late response after a newer request (or a reset) must not
      // overwrite what is on screen now.
      if (_disposed || _read != run) return;

      if (reading.hasLink) {
        // The original has done its job and is not kept.
        _photo = null;
        state = WalmartLinkScanFound(reading);
      } else {
        _photo = null;
        state = WalmartLinkScanMiss(reading.status);
      }
    } on RecipeAiException catch (error) {
      if (_disposed || _read != run) return;
      if (!error.isRetryable) _photo = null;
      state = WalmartLinkScanFailed(
        error.message,
        canRetry: error.isRetryable,
        photo: _photo,
      );
    } on Object {
      if (_disposed || _read != run) return;
      state = WalmartLinkScanFailed(
        'That did not go through. Your screenshot is still here.',
        canRetry: true,
        photo: _photo,
      );
    }
  }

  void reset() {
    if (_disposed) return;
    _pick++;
    _read++;
    _photo = null;
    state = const WalmartLinkScanIdle();
  }
}

/// Auto-disposed, so reopening the sheet starts clean rather than replaying
/// whatever the controller last held.
final NotifierProvider<WalmartLinkScanController, WalmartLinkScanState>
walmartLinkScanProvider =
    NotifierProvider<WalmartLinkScanController, WalmartLinkScanState>(
      WalmartLinkScanController.new,
      isAutoDispose: true,
    );
