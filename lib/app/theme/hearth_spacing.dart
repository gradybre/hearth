/// Spacing, radius, and touch-target tokens.
///
/// One 4pt grid so density stays consistent between a phone logging screen and
/// a desktop planning view.
abstract final class HearthSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Page gutter on a phone.
  static const double gutterCompact = 16;

  /// Page gutter on a desktop window.
  static const double gutterExpanded = 24;
}

/// Corner radii. Gentle rounding, never pill-shaped — soft and tactile rather
/// than bubbly (spec §6.1).
abstract final class HearthRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
}

/// How wide a column of content is allowed to get.
///
/// A window is as wide as somebody dragged it; a line of text is not. The
/// recipe list on a 1280pt desktop laid a short title at one end of a
/// thousand-point row and a heart at the other, which is not a row anybody
/// reads across (review §6.2.7).
abstract final class HearthLayout {
  /// A list of rows: a title, some metadata, an action at the end.
  ///
  /// Wider than [launcherWidth] on purpose: a row carries its meaning left to
  /// right and wants the room, while a stack of cards does not. Narrow enough
  /// that the eye does not have to travel to find the end of a row.
  static const double readingWidth = 820;

  /// The home screen's column of cards.
  ///
  /// Narrower than [readingWidth], and deliberately: a single card stretched
  /// across a Mac reads as a stray banner, and a launcher is a page rather
  /// than a list. Here beside its sibling so the two numbers are one
  /// decision — `HomeScreen` held its own copy, which is how a pair of
  /// widths becomes a pair of unrelated widths.
  static const double launcherWidth = 640;
}

/// Minimum interactive sizes.
abstract final class HearthTouch {
  /// Apple's and Material's shared floor.
  static const double minTarget = 44;

  /// Android's floor, which is the higher of the two.
  ///
  /// The §6.3 sweep checks both guidelines, so a control built to 44 and not
  /// padded by Material fails one of them. Material's own widgets pad to 48
  /// on their own; anything hand-built has to say so.
  static const double androidTarget = 48;

  /// Cook-along and logging are used at arm's length with messy hands, so
  /// their controls get a deliberately larger target (spec §5.2, §5.6).
  static const double kitchenTarget = 60;
}
