import '../../data/adapters/recipe_ai.dart';
import 'recipe_draft.dart';

/// Turns what the model returned into a draft the editor can open
/// (spec §5.3, §5.4).
///
/// Pure, and deliberately so: this is where the awkward answers get made safe
/// — no servings, no sections, a prep time of 900 minutes — and it is far
/// cheaper to pin those down here than through a screen (§9.1).
///
/// Nothing here rejects a recipe. §5.3 is explicit that missing data never
/// blocks; a thin import is something the user finishes in the editor, not an
/// error they have to argue with.
abstract final class AiRecipeMapper {
  /// What a recipe is assumed to serve when the source does not say.
  ///
  /// Four matches the editor's own default for a new recipe, so an import with
  /// no stated yield behaves exactly like one typed by hand — and the field is
  /// right there to correct.
  static const double defaultServings = 4;

  /// Beyond this, a time is a misread rather than a long braise.
  ///
  /// A day is generous enough for an overnight prove or a slow cook, and
  /// stops a stray "1440" from silently becoming a cook time nobody notices.
  static const int maxMinutes = 24 * 60;

  static RecipeDraft toDraft(AiRecipe recipe) {
    final List<DraftSection> sections = <DraftSection>[
      for (final AiSection section in recipe.sections)
        if (!_isBlank(section))
          DraftSection(
            name: section.name.trim(),
            ingredientsText: _lines(section.ingredientsText),
            directionsText: _lines(section.directionsText),
          ),
    ];

    return RecipeDraft(
      title: recipe.title.trim(),
      servings: _servings(recipe.servings),
      prepMinutes: _minutes(recipe.prepMinutes),
      cookMinutes: _minutes(recipe.cookMinutes),
      cuisine: _blankToNull(recipe.cuisine),
      tags: <String>[
        for (final String tag in recipe.tags)
          if (tag.trim().isNotEmpty) tag.trim(),
      ],
      // One section always survives, so the editor never opens section-less.
      sections: sections.isEmpty
          ? const <DraftSection>[DraftSection()]
          : sections,
    );
  }

  /// A section with a name but nothing in it is a heading the model invented.
  static bool _isBlank(AiSection section) =>
      section.ingredientsText.trim().isEmpty &&
      section.directionsText.trim().isEmpty;

  static double _servings(double? value) =>
      value == null || value <= 0 || !value.isFinite ? defaultServings : value;

  static int? _minutes(int? value) =>
      value == null || value <= 0 || value > maxMinutes ? null : value;

  static String? _blankToNull(String? value) =>
      (value ?? '').trim().isEmpty ? null : value!.trim();

  /// Normalises line endings and drops blank lines and stray step numbers.
  ///
  /// The parsers downstream read a line at a time, and a "1." the model kept
  /// from the source would end up inside the step's own text — Hearth numbers
  /// steps itself.
  static String _lines(String value) => <String>[
    for (final String line in value.replaceAll('\r\n', '\n').split('\n'))
      if (line.trim().isNotEmpty) _stripLeadingNumber(line.trim()),
  ].join('\n');

  /// Removes "1.", "2)" or "Step 3:" from the front of a line.
  ///
  /// Conservative on purpose: it will not touch "1 tbsp olive oil", because a
  /// quantity is the one thing that must never be stripped.
  static String _stripLeadingNumber(String line) {
    final RegExp numbered = RegExp(
      r'^(?:step\s+)?\d{1,2}\s*[.):]\s+',
      caseSensitive: false,
    );
    final String stripped = line.replaceFirst(numbered, '');
    return stripped.trim().isEmpty ? line : stripped.trim();
  }
}
