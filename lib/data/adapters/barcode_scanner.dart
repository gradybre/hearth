/// Turning what a scanner read into the numbers worth looking up (spec §5.5).
///
/// There is deliberately no `BarcodeScanner` interface here. The camera is a
/// widget, not a data source, and the flow is already exercisable without one:
/// the scan screen offers typing the number, and everything downstream takes a
/// string. An interface would have been ceremony around a package that already
/// hands back exactly what is needed.
abstract final class BarcodeVariants {
  /// Every form of a code worth trying, most likely first, without duplicates.
  ///
  /// UPC-A is EAN-13 with a leading zero, and the databases disagree about
  /// which they store — Open Food Facts leans EAN-13, USDA's GTINs are usually
  /// the 12-digit UPC. Looking up only the digits as scanned misses half the
  /// shelf for no reason a user could understand.
  static List<String> of(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const <String>[];

    final List<String> variants = <String>[digits];

    if (digits.length == 12) variants.add('0$digits');
    if (digits.length == 13 && digits.startsWith('0')) {
      variants.add(digits.substring(1));
    }

    return variants.toSet().toList();
  }

  /// Whether a typed or scanned string could be a product barcode at all.
  ///
  /// Retail codes are 8, 12, 13 or 14 digits. Rejecting the rest early stops a
  /// QR code off a menu, or a mistyped number, from being sent to three
  /// services in turn to discover the same thing.
  static bool isPlausible(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    return const <int>{8, 12, 13, 14}.contains(digits.length);
  }
}
