import 'package:meta/meta.dart';

/// One line as it will be handed to a store.
@immutable
class ShoppingExportItem {
  const ShoppingExportItem({
    required this.name,
    this.quantityLabel,
    this.storeTag,
  });

  final String name;

  /// Already rendered for humans — v1 exports recipe units ("3 tbsp olive
  /// oil"), not a mapping to purchase sizes (spec §5.7).
  final String? quantityLabel;

  final String? storeTag;
}

/// What an export produced, for the UI to act on.
@immutable
class ShoppingExportResult {
  const ShoppingExportResult({
    required this.kind,
    this.deepLinks = const <Uri>[],
    this.clipboardText,
  });

  final ShoppingExportKind kind;

  /// One search link per item, for adapters that can only deep-link.
  final List<Uri> deepLinks;

  /// The list as text, for the one-tap copy path.
  final String? clipboardText;
}

enum ShoppingExportKind { deepLink, clipboard, cart }

/// A store hand-off, behind an interface (CLAUDE.md rule 7).
///
/// v1 is deep links plus copy (spec §5.7) — not because a cart hand-off is
/// impossible, but because every one of them is keyed by a product id Hearth
/// does not hold yet. Keeping this an interface is what lets a real cart
/// hand-off slot in later without touching the UI.
///
/// **Nothing here may send anything anywhere on its own.** The list is fully
/// editable first and the export is a deliberate, reviewed hand-off, never a
/// silent one (spec §5.7, CLAUDE.md rule 4).
///
/// No implementations yet: shopping is Phase 4.
abstract interface class ShoppingExportAdapter {
  /// Shown on the export button.
  String get displayName;

  /// What this adapter can actually do, so the UI can describe the hand-off
  /// honestly rather than promising a cart it cannot fill.
  ShoppingExportKind get kind;

  /// Builds the hand-off from an already-reviewed list.
  Future<ShoppingExportResult> export(List<ShoppingExportItem> items);
}
