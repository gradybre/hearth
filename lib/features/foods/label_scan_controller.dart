import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';

/// Which of the two label photos a slot holds (spec R11).
enum LabelSlot { nutrition, package }

/// What the label reader is doing, and the photos it has to work with
/// (spec §5.5, R11).
///
/// Two independent slots rather than one: the back of a package states
/// nutrition, the front states net contents, and a user may have either,
/// both, or neither in hand. Nothing here auto-reads on selection — reading
/// is one deliberate action over whatever is currently chosen.
@immutable
sealed class LabelScanState {
  const LabelScanState({this.backPhoto, this.frontPhoto});

  /// Kept through a failure on purpose (spec §8: originals discarded only
  /// after a successful extraction).
  final PickedPhoto? backPhoto;
  final PickedPhoto? frontPhoto;

  bool get hasAnyPhoto => backPhoto != null || frontPhoto != null;
}

class LabelScanIdle extends LabelScanState {
  const LabelScanIdle({super.backPhoto, super.frontPhoto});
}

class LabelScanReading extends LabelScanState {
  const LabelScanReading({super.backPhoto, super.frontPhoto});
}

class LabelScanDone extends LabelScanState {
  const LabelScanDone(this.reading, {super.backPhoto, super.frontPhoto});
  final LabelReading reading;
}

/// It did not work, and what the user can do about it. Both photos, where
/// present, are kept — a retry needs neither reselected.
class LabelScanFailed extends LabelScanState {
  const LabelScanFailed(
    this.message, {
    required this.canRetry,
    super.backPhoto,
    super.frontPhoto,
  });

  final String message;
  final bool canRetry;
}

/// Reading a nutrition label off one or two photos (spec §5.5, R11).
///
/// One combined read rather than one per photo: the two facts on a box come
/// from the same product, and a single reviewed extraction is one thing to
/// check rather than two to reconcile.
class LabelScanController extends Notifier<LabelScanState> {
  @override
  LabelScanState build() {
    ref.onDispose(() {
      _invalidateAll();
      _disposed = true;
      _back = null;
      _front = null;
    });
    return const LabelScanIdle();
  }

  /// Beyond this the function refuses it anyway. Caught here so the user is
  /// told before waiting on an upload rather than after.
  static const int maxImageBytes = 5 * 1024 * 1024;

  PickedPhoto? _back;
  PickedPhoto? _front;

  /// One generation per slot, so an operation on one slot cannot silently
  /// discard an in-flight pick for the other (spec R11: cancelling or
  /// replacing one photo never clears the other). A single counter dropped
  /// a returning nutrition photo whenever the package slot was touched
  /// while the system picker was open, with nothing said.
  final Map<LabelSlot, int> _picks = <LabelSlot, int>{
    LabelSlot.nutrition: 0,
    LabelSlot.package: 0,
  };

  /// And one for the combined read, which any change to either photo
  /// invalidates: a response about photos that are no longer on screen must
  /// not land on the review.
  int _read = 0;
  bool _disposed = false;

  /// Everything in flight stops counting — for a reset or a disposal, where
  /// there is nothing left for any of it to land on.
  void _invalidateAll() {
    _read++;
    for (final LabelSlot slot in LabelSlot.values) {
      _picks[slot] = (_picks[slot] ?? 0) + 1;
    }
  }

  /// Picks or takes a photo for [slot]. Does not read it — reading is a
  /// separate, deliberate step so two photos cost one request, not two.
  Future<void> pick(LabelSlot slot, PhotoOrigin origin) async {
    final int run = _picks[slot] = (_picks[slot] ?? 0) + 1;
    PickedPhoto? picked;
    try {
      picked = await ref.read(photoPickerProvider).pick(origin);
    } on Object {
      if (_disposed || run != _picks[slot]) return;
      state = LabelScanFailed(
        'That photo could not be opened. Choose it again or enter the details.',
        canRetry: false,
        backPhoto: _back,
        frontPhoto: _front,
      );
      return;
    }
    if (_disposed || run != _picks[slot]) return;
    if (picked == null) {
      state = LabelScanIdle(backPhoto: _back, frontPhoto: _front);
      return;
    }

    if (picked.bytes.lengthInBytes > maxImageBytes) {
      // Desktop pickers ignore the downscaling the mobile ones apply, so a
      // full-resolution photo can arrive intact.
      state = LabelScanFailed(
        'That photo is too big to send. One from your phone will be fine.',
        canRetry: false,
        backPhoto: _back,
        frontPhoto: _front,
      );
      return;
    }

    switch (slot) {
      case LabelSlot.nutrition:
        _back = picked;
      case LabelSlot.package:
        _front = picked;
    }
    // Whatever a read was sent for is no longer what is on screen.
    _read++;
    state = LabelScanIdle(backPhoto: _back, frontPhoto: _front);
  }

  /// Clears one slot, leaving the other untouched.
  void remove(LabelSlot slot) {
    // This slot only — a pick still open for the other one stands. The read
    // does not: it was sent for a photo that has just gone.
    _picks[slot] = (_picks[slot] ?? 0) + 1;
    _read++;
    switch (slot) {
      case LabelSlot.nutrition:
        _back = null;
      case LabelSlot.package:
        _front = null;
    }
    state = LabelScanIdle(backPhoto: _back, frontPhoto: _front);
  }

  /// Sends whatever photos are chosen, back-then-front, as one request.
  ///
  /// A fixed order rather than whichever finished picking first: the server
  /// side reads roles positionally, and a stable order is what makes that
  /// safe.
  Future<void> read() async {
    if (_disposed) return;
    if (_back == null && _front == null) return;

    final int run = ++_read;
    final LabelReader? reader = ref.read(labelReaderProvider);
    if (reader == null) {
      state = LabelScanFailed(
        "Reading a label needs a connection to Hearth's server, and this "
        'build has none configured.',
        canRetry: false,
        backPhoto: _back,
        frontPhoto: _front,
      );
      return;
    }

    state = LabelScanReading(backPhoto: _back, frontPhoto: _front);

    try {
      final List<AiImage> images = <AiImage>[
        if (_back != null) AiImage.ofPhoto(_back!, role: 'nutrition'),
        if (_front != null) AiImage.ofPhoto(_front!, role: 'package'),
      ];
      final LabelReading reading = await reader.read(images);
      // A late response after a newer request (or a reset) must not
      // overwrite what is on screen now.
      if (_disposed || _read != run) return;

      // The originals have done their job and are not kept (spec §8).
      _back = null;
      _front = null;
      state = LabelScanDone(reading);
    } on RecipeAiException catch (error) {
      if (_disposed || _read != run) return;
      state = LabelScanFailed(
        error.message,
        canRetry: error.isRetryable,
        backPhoto: _back,
        frontPhoto: _front,
      );
    } on Object {
      if (_disposed || _read != run) return;
      state = LabelScanFailed(
        'That did not go through. Your photos are still here.',
        canRetry: true,
        backPhoto: _back,
        frontPhoto: _front,
      );
    }
  }

  void reset() {
    _invalidateAll();
    _back = null;
    _front = null;
    state = const LabelScanIdle();
  }
}

/// Auto-disposed, so reopening the sheet starts clean rather than replaying
/// whatever the controller last held.
final NotifierProvider<LabelScanController, LabelScanState> labelScanProvider =
    NotifierProvider<LabelScanController, LabelScanState>(
      LabelScanController.new,
      isAutoDispose: true,
    );
