/// Drawing a recipe's sketch icon, behind an interface (CLAUDE.md rule 7).
///
/// The only implementation goes through an Edge Function, because the Claude
/// API key cannot ship in the client (§8.1). The interface exists so that
/// stays true of any future provider — and so every screen above it can be
/// tested without a network, a key, or a bill.
abstract interface class RecipeIconSource {
  /// Draws a sketch for a recipe called [title] (spec §5.2, §6.1).
  ///
  /// Answers null whenever there is no icon to show: nothing came back, what
  /// came back would not survive validation, the month's decorative budget is
  /// spent, or the network was not there. One answer for all of them on
  /// purpose — this is decorative work, and no failure of it is worth
  /// interrupting anybody over.
  ///
  /// What comes back has already passed `SketchIcon.parse`. An implementation
  /// that cannot promise that must return null instead.
  Future<String?> draw({required String title});
}
