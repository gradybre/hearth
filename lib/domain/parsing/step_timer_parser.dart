/// Finds the timer hiding in a step's text (spec §5.2).
///
/// "Simmer for 20 minutes" is a timer the cook should not have to key in by
/// hand — the number is right there in the step. Without this, `timer_seconds`
/// is only ever set by hand and cook-along's timers go unused, which is the
/// same as not having them.
///
/// Conservative, in the same spirit as the ingredient parser: it offers a
/// timer when the step plainly states one and stays quiet otherwise. A wrong
/// timer is worse than no timer — the cook trusts it and burns the dish.
abstract final class StepTimerParser {
  static const Map<String, int> _units = <String, int>{
    'second': 1,
    'seconds': 1,
    'sec': 1,
    'secs': 1,
    'minute': 60,
    'minutes': 60,
    'min': 60,
    'mins': 60,
    'hour': 3600,
    'hours': 3600,
    'hr': 3600,
    'hrs': 3600,
  };

  /// Longest unit words first so "mins" is not matched as "min" with a
  /// trailing "s" that then fails the word boundary.
  static final RegExp _pattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:(?:-|–|—|\s+to\s+)\s*\d+(?:\.\d+)?\s*)?'
    // No word boundary before the unit — "40min" has none between the digit
    // and the letter — but one after it, which is what keeps "3 minced garlic"
    // from reading as three minutes.
    r'(seconds|second|secs|sec|minutes|minute|mins|min|hours|hour|hrs|hr)\b',
    caseSensitive: false,
  );

  /// The timer for [text] in seconds, or null when the step states none.
  ///
  /// The first duration wins: "bake for 40 minutes, turning at 20" means forty
  /// minutes, and the twenty is an aside. A range takes its lower bound —
  /// "20–25 minutes" sets 20, so the cook is called back to check rather than
  /// called back to find it overdone.
  static int? parse(String text) {
    final RegExpMatch? match = _pattern.firstMatch(text);
    if (match == null) return null;

    final double amount = double.parse(match.group(1)!);
    final int unit = _units[match.group(2)!.toLowerCase()]!;
    final int seconds = (amount * unit).round();

    // Nothing under ten seconds and nothing over a day: below that it is a
    // figure of speech ("in 2 seconds"), above it a description of a cure or a
    // marinade rather than something to stand a timer over.
    if (seconds < 10 || seconds > Duration.secondsPerDay) return null;
    return seconds;
  }
}
