import '../../domain/shopping/walmart_link_reading.dart';
import 'recipe_ai.dart';

/// Reading a Walmart product link out of a screenshot, behind an interface
/// (CLAUDE.md rule 7).
///
/// A companion to `LabelReader` rather than a replacement: the same photo
/// plumbing, the same server-side model and key, but a different question —
/// not what a nutrition label says, but whether the screenshot in hand
/// already names a specific product page. The shaping decision (which
/// candidate strings are accepted, merged or rejected) happens server-side;
/// this interface only promises a strictly validated [WalmartLinkReading]
/// back, never a raw guess.
abstract interface class WalmartLinkReader {
  /// Reads a Walmart product link from exactly one screenshot.
  ///
  /// Any doubt comes back as [WalmartLinkStatus.notFound],
  /// [WalmartLinkStatus.ambiguous], or [WalmartLinkStatus.unreadable] rather
  /// than a link that might be wrong — conservatism is the point, per
  /// D-WALMART-001.
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images);
}
