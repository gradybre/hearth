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

/// Minimum interactive sizes.
abstract final class HearthTouch {
  /// Apple's and Material's shared floor.
  static const double minTarget = 44;

  /// Cook-along and logging are used at arm's length with messy hands, so
  /// their controls get a deliberately larger target (spec §5.2, §5.6).
  static const double kitchenTarget = 60;
}
