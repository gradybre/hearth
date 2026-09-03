/// Reading a Walmart product id out of whatever was pasted (spec §5.7).
///
/// The cart URL is keyed by item id, and the only place a person can get one
/// is a product page — so the realistic gesture is Share → Copy Link in the
/// Walmart app and a paste into Hearth. A bare id is accepted too, because
/// once you have typed a few you know what they look like.
///
/// The slug in a product URL is **decorative**: `/ip/Great-Value-Apple-Juice/
/// 10450479` serves whatever product 10450479 is, regardless of the words.
/// Only the trailing number identifies anything.
abstract final class WalmartProduct {
  /// Ids are numeric and, in practice, eight to ten digits. The bounds are
  /// loose on purpose — a real id that fell outside them would be refused for
  /// no better reason than that Hearth had not seen one that shape before.
  static final RegExp _digits = RegExp(r'^\d{3,20}$');

  /// The item id in [raw], or null when there is not one.
  ///
  /// Null rather than a best guess: an id that is wrong fails at the shop,
  /// silently, in a basket somebody is standing over. Refusing at the point of
  /// paste is the only place it can be said usefully.
  static String? idFrom(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    if (_digits.hasMatch(text)) return text;

    // A URL, hopefully. tryParse accepts almost anything, so the work is in
    // what comes out rather than in whether it parsed.
    final Uri? uri = Uri.tryParse(text);
    if (uri == null) return null;

    // The **last** all-digit segment, not the first. A slug can carry digits
    // of its own — "100-apple-juice-96-fl-oz" — and those sit ahead of the id.
    for (final String segment in uri.pathSegments.reversed) {
      final String part = segment.trim();
      if (_digits.hasMatch(part)) return part;
    }
    return null;
  }

  /// Whether [raw] is something to keep, for a field that wants to say so.
  static bool looksValid(String raw) => idFrom(raw) != null;
}
