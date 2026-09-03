import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/recipe.dart';
import '../../domain/parsing/direction_parser.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/parsing/step_timer_parser.dart';
import '../../domain/text/text_normaliser.dart';

/// Turns what the user typed into a [Recipe].
///
/// Kept out of the widget so the conversion — which is where a mistyped
/// quantity or a mis-split step would do real damage — can be tested without
/// pumping a screen.
///
/// Ingredients and directions are entered as free text and parsed, because
/// typing a recipe line by line into separate fields is the slow path, and
/// the parsers already handle the shapes people actually paste (spec §5.2).
@immutable
/// One component group as the editor holds it (spec §5.2).
///
/// Ingredients and directions are kept as the raw text the user typed, per
/// section, and parsed on the way out. A recipe with one unnamed section is
/// the ordinary case and renders with no header at all, so a simple recipe
/// never has to know sections exist.
@immutable
class DraftSection {
  const DraftSection({
    this.name = '',
    this.ingredientsText = '',
    this.directionsText = '',
    this.existingId,
  });

  final String name;
  final String ingredientsText;
  final String directionsText;

  /// Reusing the section id on edit keeps ingredient and step rows pointing at
  /// a section that still exists.
  final String? existingId;

  /// The name as stored. An unnamed section is the default "Main", which the
  /// reader renders without a header.
  String get storedName =>
      name.trim().isEmpty ? Recipe.defaultSectionName : name.trim();

  bool get isEmpty =>
      name.trim().isEmpty &&
      ingredientsText.trim().isEmpty &&
      directionsText.trim().isEmpty;

  DraftSection copyWith({
    String? name,
    String? ingredientsText,
    String? directionsText,
  }) => DraftSection(
    name: name ?? this.name,
    ingredientsText: ingredientsText ?? this.ingredientsText,
    directionsText: directionsText ?? this.directionsText,
    existingId: existingId,
  );
}

class RecipeDraft {
  const RecipeDraft({
    required this.title,
    required this.servings,
    this.sections = const <DraftSection>[DraftSection()],
    this.prepMinutes,
    this.cookMinutes,
    this.cuisine,
    this.kind = RecipeKind.cooked,
    this.tags = const <String>[],
    this.notes,
    this.existingId,
    this.matches = const <String, String>{},
    this.noMatch = const <String>{},
  });

  final String title;
  final double servings;

  /// At least one, always. Sections are ordered; the order here is the order
  /// they read in.
  final List<DraftSection> sections;
  final int? prepMinutes;
  final int? cookMinutes;
  final String? cuisine;

  /// Cooked, or eaten out (spec §5.2). An eaten-out recipe never reaches
  /// the shopping list and offers neither cook-along nor scaling.
  final RecipeKind kind;
  final List<String> tags;
  final String? notes;

  /// Set when editing, so a save updates rather than creating a duplicate.
  final String? existingId;

  /// Normalised ingredient name to food id.
  ///
  /// Keyed by name rather than by row index so a match survives the user
  /// editing the text above it — retyping a quantity should not silently drop
  /// the food you attached.
  final Map<String, String> matches;

  /// Lines marked as needing no food at all — salt, pepper, a spice
  /// (spec §5.3). Keyed the same way as [matches], and for the same reason:
  /// the mark has to survive the text above it being edited.
  final Set<String> noMatch;

  bool get isEditing => existingId != null;

  /// A title is the only field required to save. Yield defaults rather than
  /// blocking, because "missing data flags, never blocks" (spec §5.3) applies
  /// just as much to the user's own typing.
  String? get titleError =>
      title.trim().isEmpty ? 'A recipe needs a title.' : null;

  String? get servingsError =>
      servings > 0 ? null : 'Servings must be more than zero.';

  bool get isValid => titleError == null && servingsError == null;

  /// Whether this recipe is grouped at all. A single unnamed section is the
  /// ordinary case and shows no section chrome.
  bool get hasSections =>
      sections.length > 1 ||
      sections.any((DraftSection s) => s.name.trim().isNotEmpty);

  /// The parsed ingredient lines of one section, for the live preview.
  static List<ParsedIngredient> parseIngredients(String text) =>
      <ParsedIngredient>[
        for (final String line in text.split('\n'))
          if (line.trim().isNotEmpty) IngredientParser.parse(line),
      ];

  /// Every ingredient line across every section, in reading order.
  List<ParsedIngredient> get parsedIngredients => <ParsedIngredient>[
    for (final DraftSection section in sections)
      ...parseIngredients(section.ingredientsText),
  ];

  /// The parsed steps of the whole recipe, numbered straight through.
  ///
  /// A cook counts steps across the whole method, not per group — "step 7" has
  /// to mean one thing.
  ParsedDirections get parsedDirections => DirectionParser.parse(
    sections
        .map((DraftSection s) => s.directionsText.trim())
        .where((String t) => t.isNotEmpty)
        .join('\n'),
  );

  /// The food attached to an ingredient line, if any.
  String? foodIdFor(String ingredientName) =>
      matches[normaliseKey(ingredientName)];

  /// Whether this line has been marked as needing no food.
  bool needsNoMatchFor(String ingredientName) =>
      noMatch.contains(normaliseKey(ingredientName));

  /// Attaches a food to every line with this name.
  RecipeDraft withMatch(String ingredientName, String? foodId) {
    final String key = normaliseKey(ingredientName);
    if (key.isEmpty) return this;
    final Map<String, String> next = <String, String>{...matches};
    if (foodId == null) {
      next.remove(key);
    } else {
      next[key] = foodId;
    }
    return _copyWithMatches(next);
  }

  /// Builds the recipe to save.
  ///
  /// [idFactory] is injectable so tests get stable ids.
  Recipe toRecipe({String Function()? idFactory}) {
    final String Function() newId = idFactory ?? const Uuid().v4;
    final String recipeId = existingId ?? newId();

    // Empty sections are dropped rather than saved: an "Add a section" tapped
    // and then thought better of should leave no trace. One always survives,
    // so a recipe is never section-less.
    final List<DraftSection> kept = <DraftSection>[
      for (final DraftSection section in sections)
        if (!section.isEmpty) section,
    ];
    final List<DraftSection> effective = kept.isEmpty
        ? const <DraftSection>[DraftSection()]
        : kept;

    // Steps are numbered straight through the recipe rather than restarting
    // per group: a cook counting steps counts the whole method.
    int stepNumber = 0;

    return Recipe(
      id: recipeId,
      title: title.trim(),
      servings: servings,
      prepTime: prepMinutes == null ? null : Duration(minutes: prepMinutes!),
      cookTime: cookMinutes == null ? null : Duration(minutes: cookMinutes!),
      cuisine: (cuisine ?? '').trim().isEmpty ? null : cuisine!.trim(),
      kind: kind,
      tags: tags,
      notes: (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      sections: <RecipeSection>[
        for (int index = 0; index < effective.length; index++)
          _buildSection(
            effective[index],
            sortOrder: index,
            newId: newId,
            nextStepNumber: () => ++stepNumber,
          ),
      ],
    );
  }

  RecipeSection _buildSection(
    DraftSection section, {
    required int sortOrder,
    required String Function() newId,
    required int Function() nextStepNumber,
  }) {
    final String sectionId = section.existingId ?? newId();
    final List<ParsedIngredient> ingredients = parseIngredients(
      section.ingredientsText,
    );
    final ParsedDirections directions = DirectionParser.parse(
      section.directionsText,
    );

    return RecipeSection(
      id: sectionId,
      name: section.storedName,
      sortOrder: sortOrder,
      ingredients: <RecipeIngredient>[
        for (int i = 0; i < ingredients.length; i++)
          RecipeIngredient(
            id: newId(),
            sectionId: sectionId,
            name: ingredients[i].name,
            quantity: ingredients[i].quantity,
            rawText: ingredients[i].raw,
            prepNote: ingredients[i].prepNote,
            foodId: foodIdFor(ingredients[i].name),
            isOptional: ingredients[i].isOptional,
            needsNoMatch: needsNoMatchFor(ingredients[i].name),
            sortOrder: i,
          ),
      ],
      steps: <RecipeStep>[
        for (final ParsedStep step in directions.steps)
          RecipeStep(
            id: newId(),
            sectionId: sectionId,
            stepNumber: nextStepNumber(),
            text: step.text,
            // "Simmer for 20 minutes" is a timer the cook should not have to
            // key in again — the number is already in the step, and
            // cook-along's timers go unused if nothing ever sets this.
            timerSeconds: StepTimerParser.parse(step.text),
          ),
      ],
    );
  }

  /// Rebuilds a draft from a saved recipe, so editing starts from what is
  /// actually stored rather than from a re-rendered guess.
  factory RecipeDraft.fromRecipe(Recipe recipe) => RecipeDraft(
    title: recipe.title,
    servings: recipe.servings,
    sections: <DraftSection>[
      if (recipe.orderedSections.isEmpty)
        const DraftSection()
      else
        for (final RecipeSection section in recipe.orderedSections)
          DraftSection(
            // The transparent default is not shown back as text the user
            // typed — they never typed it. But only when it stands alone: a
            // section deliberately called "Main" alongside a "Sauce" is a
            // name, and blanking it would lose it.
            name: section.isDefault && recipe.sections.length == 1
                ? ''
                : section.name,
            // The raw line is kept on every ingredient precisely so an edit
            // shows the user what they typed, not the parser's
            // reconstruction.
            ingredientsText: section.ingredients
                .map((RecipeIngredient i) => i.rawText ?? i.name)
                .join('\n'),
            directionsText: section.steps
                .map((RecipeStep s) => '${s.stepNumber}. ${s.text}')
                .join('\n'),
            existingId: section.id,
          ),
    ],
    prepMinutes: recipe.prepTime?.inMinutes,
    cookMinutes: recipe.cookTime?.inMinutes,
    cuisine: recipe.cuisine,
    kind: recipe.kind,
    tags: recipe.tags,
    notes: recipe.notes,
    existingId: recipe.id,
    noMatch: <String>{
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        if (ingredient.needsNoMatch)
          if (normaliseKey(ingredient.name).isNotEmpty)
            normaliseKey(ingredient.name),
    },
    // Keyed by the stored name *and* by whatever the current parser makes of
    // the raw line, because those are not always the same string.
    //
    // The editor re-reads every line on the way in, so a parser that has
    // learned something since — "4 (10 oz) bags frozen chopped onion" now
    // yields "frozen chopped onion" rather than "(10 oz) bags frozen chopped
    // onion" — produces a different key on the way out. Keyed only by the old
    // name, the food quietly detached itself the moment the recipe was saved,
    // which is the opposite of what reopening a recipe should do.
    matches: <String, String>{
      for (final RecipeIngredient ingredient in recipe.allIngredients)
        if (ingredient.foodId != null) ...<String, String>{
          if (normaliseKey(ingredient.name).isNotEmpty)
            normaliseKey(ingredient.name): ingredient.foodId!,
          if (ingredient.rawText case final String raw)
            if (normaliseKey(IngredientParser.parse(raw).name).isNotEmpty)
              normaliseKey(IngredientParser.parse(raw).name):
                  ingredient.foodId!,
        },
    },
  );

  /// The recipe as words, for handing to the model to revise (spec §5.4).
  ///
  /// The draft *as it currently stands*, hand edits and all — not as it was
  /// imported. Asking for "swap steps 2 and 3" against a stale copy would
  /// hand back a recipe with your own corrections quietly undone.
  ///
  /// Plain text rather than JSON on purpose: sections are already stored as
  /// the text the user typed, the model writes them back the same way, and a
  /// schema in between would be two more places for a recipe to lose a line.
  String toPrompt() {
    final StringBuffer out = StringBuffer()
      ..writeln(title.trim().isEmpty ? 'Untitled' : title.trim())
      ..writeln('Serves $servings');
    if (prepMinutes != null) out.writeln('Prep: $prepMinutes minutes');
    if (cookMinutes != null) out.writeln('Cook: $cookMinutes minutes');
    if ((cuisine ?? '').trim().isNotEmpty) out.writeln('Cuisine: $cuisine');
    if (tags.isNotEmpty) out.writeln('Tags: ${tags.join(', ')}');
    if ((notes ?? '').trim().isNotEmpty) out.writeln('Notes: $notes');

    for (final DraftSection section in sections) {
      out
        ..writeln()
        ..writeln('## ${section.storedName}')
        ..writeln('Ingredients:')
        ..writeln(section.ingredientsText.trim())
        ..writeln('Directions:')
        ..writeln(section.directionsText.trim());
    }
    return out.toString().trim();
  }

  /// This draft's content replaced by [incoming], keeping what is not the
  /// model's to decide.
  ///
  /// Three things must survive a revision, and each is a way this could
  /// quietly do damage:
  ///
  ///  * **[existingId]** — without it, editing a saved recipe and asking for
  ///    one change would save a second copy of it instead.
  ///  * **[matches] and [noMatch]** — keyed by normalised ingredient name, so
  ///    every line whose name did not change keeps the food attached to it. A
  ///    revision that dropped them would cost a re-match of the whole recipe
  ///    for the sake of reordering two steps.
  ///  * **[notes]** — the model is not asked about them and must not be able
  ///    to remove them by not mentioning them.
  ///
  /// A line the model genuinely renamed does lose its match, which is correct:
  /// the match was to the old wording, and the food it named may no longer be
  /// what the line says.
  RecipeDraft revisedWith(RecipeDraft incoming) => RecipeDraft(
    title: incoming.title,
    servings: incoming.servings,
    sections: incoming.sections,
    prepMinutes: incoming.prepMinutes,
    cookMinutes: incoming.cookMinutes,
    cuisine: incoming.cuisine,
    kind: kind,
    tags: incoming.tags,
    notes: notes,
    existingId: existingId,
    matches: matches,
    noMatch: noMatch,
  );

  RecipeDraft copyWith({
    String? title,
    double? servings,
    List<DraftSection>? sections,
    int? prepMinutes,
    int? cookMinutes,
    String? cuisine,
    RecipeKind? kind,
    List<String>? tags,
    String? notes,
  }) => RecipeDraft(
    title: title ?? this.title,
    servings: servings ?? this.servings,
    sections: sections ?? this.sections,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    cuisine: cuisine ?? this.cuisine,
    kind: kind ?? this.kind,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    existingId: existingId,
    matches: matches,
    noMatch: noMatch,
  );

  /// This draft with [name] marked as needing no food, or unmarked.
  ///
  /// Keyed by name like [withMatch], so every line saying "salt" changes
  /// together and the mark survives the text above it being edited.
  RecipeDraft withNoMatch(String ingredientName, {required bool marked}) {
    final String key = normaliseKey(ingredientName);
    if (key.isEmpty) return this;
    final Set<String> next = <String>{...noMatch};
    if (marked) {
      next.add(key);
    } else {
      next.remove(key);
    }
    return _copy(noMatch: next);
  }

  RecipeDraft _copyWithMatches(Map<String, String> next) =>
      _copy(matches: next);

  RecipeDraft _copy({Map<String, String>? matches, Set<String>? noMatch}) =>
      RecipeDraft(
        title: title,
        servings: servings,
        sections: sections,
        prepMinutes: prepMinutes,
        cookMinutes: cookMinutes,
        cuisine: cuisine,
        kind: kind,
        tags: tags,
        notes: notes,
        existingId: existingId,
        matches: matches ?? this.matches,
        noMatch: noMatch ?? this.noMatch,
      );
}
