import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/barcode_scanner.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../domain/foods/produce_plu.dart';

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

/// A produce sticker's code, and what it names (spec §5.5).
///
/// Kept apart from [BarcodeFound] because a PLU identifies a *commodity*, not
/// a product: 4011 is "bananas", not anybody's particular bananas. There are
/// no macros attached to it — the name is what goes out to the sources, and
/// the household picks which bananas from what comes back.
class ProduceFound extends BarcodeLookupState {
  const ProduceFound(this.produce);
  final ProduceItem produce;
}

/// A produce code this table does not carry.
///
/// A different miss from [BarcodeMissing]: nobody is going to scan it into
/// existence, so the way out is naming the food by hand.
class ProduceUnknown extends BarcodeLookupState {
  const ProduceUnknown(this.code);
  final String code;
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

    // A produce code is a different namespace and takes a different road.
    // It is never sent to a barcode lookup: Open Food Facts has short codes
    // of its own and answers them confidently with unrelated food — cucumber
    // (4062) comes back as pumpkin seeds at 600 kcal. See [ProducePlu].
    if (ProducePlu.isPlu(barcode)) {
      _last = barcode;
      state = BarcodeSearching(barcode);

      // The library first, so produce already saved under this code is the
      // household's own answer rather than another trip outward.
      final NutritionMatch? saved = await ref
          .read(nutritionLookupProvider)
          .fromLibraryByBarcode(barcode);
      if (_last != barcode) return;
      if (saved != null) {
        state = BarcodeFound(barcode, saved);
        return;
      }

      final ProduceItem? produce = ProducePlu.lookup(barcode);
      state = produce == null ? ProduceUnknown(barcode) : ProduceFound(produce);
      return;
    }

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
