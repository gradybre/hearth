import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/barcode_scanner.dart';
import '../../data/adapters/nutrition_source.dart';

/// What the screen is doing while a barcode is looked up.
@immutable
sealed class BarcodeLookupState {
  const BarcodeLookupState();
}

class BarcodeIdle extends BarcodeLookupState {
  const BarcodeIdle();
}

class BarcodeSearching extends BarcodeLookupState {
  const BarcodeSearching(this.barcode);
  final String barcode;
}

/// Found, with the source and confidence the review screen needs to show.
class BarcodeFound extends BarcodeLookupState {
  const BarcodeFound(this.barcode, this.match);
  final String barcode;
  final NutritionMatch match;
}

/// Nobody had it. Not an error: this is the manual-entry path, and it carries
/// the barcode so the new food is attached to it and found next time (§5.5).
class BarcodeMissing extends BarcodeLookupState {
  const BarcodeMissing(this.barcode);
  final String barcode;
}

/// The number itself is not a product code — a QR code on a menu, or a
/// mistyped digit. Saying so beats three fruitless lookups.
class BarcodeNotAProduct extends BarcodeLookupState {
  const BarcodeNotAProduct(this.barcode);
  final String barcode;
}

/// Looking a barcode up across the chain (spec §5.5).
///
/// Deliberately knows nothing about cameras. A scanner hands it a string and
/// so does a text field, which is what makes the whole flow — lookup, review,
/// save, and the miss path — exercisable on a machine with no camera at all.
class BarcodeLookupController extends Notifier<BarcodeLookupState> {
  @override
  BarcodeLookupState build() => const BarcodeIdle();

  /// The last barcode looked up, so a retry does not need it typed again.
  String? _last;

  Future<void> lookUp(String raw) async {
    final String barcode = raw.trim();
    if (barcode.isEmpty) return;

    if (!BarcodeVariants.isPlausible(barcode)) {
      state = BarcodeNotAProduct(barcode);
      return;
    }

    _last = barcode;
    state = BarcodeSearching(barcode);

    final NutritionMatch? match = await ref
        .read(nutritionLookupProvider)
        .byBarcode(barcode);

    // A newer scan may have started while this one was in flight; the older
    // answer must not overwrite it.
    if (_last != barcode) return;

    state = match == null
        ? BarcodeMissing(barcode)
        : BarcodeFound(barcode, match);
  }

  Future<void> retry() async {
    final String? barcode = _last;
    if (barcode != null) await lookUp(barcode);
  }

  void reset() {
    _last = null;
    state = const BarcodeIdle();
  }
}

final NotifierProvider<BarcodeLookupController, BarcodeLookupState>
barcodeLookupProvider =
    NotifierProvider<BarcodeLookupController, BarcodeLookupState>(
      BarcodeLookupController.new,
    );
