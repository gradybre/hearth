import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/direction_parser.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/recipes/ingredient_matcher.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/text/text_normaliser.dart';
import '../foods/food_picker.dart';
import 'match_review_controller.dart';
import 'match_review_screen.dart';
import 'recipe_draft.dart';
import 'recipe_import_controller.dart';
import 'recipe_photo.dart';

/// Create or edit a recipe (spec §5.2).
///
/// Ingredients and directions are typed or pasted as blocks and parsed live,
/// rather than filled into a field per quantity. Typing a recipe is already
/// the slow part of owning one; the parsers exist so this can be a paste.
///
/// The parse is always shown back before saving, so a misread quantity is
/// caught by eye rather than discovered later in a macro total.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({this.recipeId, this.imported, super.key});

  /// Null when creating.
  final String? recipeId;

  /// A recipe that arrived from an import or a generation (spec §5.3, §5.4).
  ///
  /// This screen is that review — the same way the food editor is the review
  /// for a barcode scan. It arrives filled in and entirely editable, and
  /// anything the model was unsure of is pointed at rather than left for the
  /// user to find.
  final RecipeImportResult? imported;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _servings = TextEditingController(text: '4');
  final TextEditingController _prep = TextEditingController();
  final TextEditingController _cook = TextEditingController();
  final TextEditingController _cuisine = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// One set of fields per section. A new recipe starts with a single unnamed
  /// one, which renders with no section chrome at all (spec §5.2).
  final List<_SectionFields> _sections = <_SectionFields>[_SectionFields()];

  bool _loaded = false;
  bool _saving = false;
  String? _existingId;
  bool _showErrors = false;

  /// Normalised ingredient name to food id, mirroring [RecipeDraft.matches].
  Map<String, String> _matches = <String, String>{};

  /// Remembered matches already applied, so auto-apply runs once per string
  /// and never fights a user who has just unmatched something.
  final Set<String> _autoApplied = <String>{};

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _title,
      _servings,
      _prep,
      _cook,
      _cuisine,
      _tags,
      _notes,
    ]) {
      controller.dispose();
    }
    for (final _SectionFields section in _sections) {
      section.dispose();
    }
    super.dispose();
  }

  /// The household's foods, keyed by id, for macro calculation and row labels.
  Map<String, Food> _foods = <String, Food>{};

  /// Applies remembered matches to any line that has none.
  ///
  /// Only remembered matches are applied silently — they are decisions this
  /// household already made. A best guess is offered in the picker instead of
  /// being assumed, because a wrong macro is worse than a missing one
  /// (spec §5.3).
  void _autoApplyRemembered(Map<String, String> remembered) {
    if (remembered.isEmpty) return;
    final Map<String, String> next = <String, String>{..._matches};
    bool changed = false;

    for (final ParsedIngredient ingredient in _draft.parsedIngredients) {
      final String key = normaliseKey(ingredient.name);
      if (key.isEmpty || next.containsKey(key)) continue;
      if (_autoApplied.contains(key)) continue;

      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: ingredient.name,
        library: _foods.values.toList(growable: false),
        remembered: remembered,
      );
      if (suggestion == null || !suggestion.isTrusted) continue;

      next[key] = suggestion.foodId;
      _autoApplied.add(key);
      changed = true;
    }

    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _matches = next);
      });
    }
  }

  /// Ingredients in section [i] with no food attached and no reason to skip.
  List<ParsedIngredient> _unmatchedIn(int i, RecipeDraft draft) =>
      <ParsedIngredient>[
        for (final ParsedIngredient ingredient in RecipeDraft.parseIngredients(
          _sections[i].ingredients.text,
        ))
          // Optional lines are excluded from macros on purpose (§5.2): not a
          // gap, so not something to go looking for.
          if (!ingredient.isOptional &&
              ingredient.name.trim().isNotEmpty &&
              draft.foodIdFor(ingredient.name) == null)
            ingredient,
      ];

  /// Searches every unmatched line, then hands the results to the review
  /// screen before any of it counts (spec §5.3).
  Future<void> _findMatches(List<ParsedIngredient> unmatched) async {
    ref.read(matchReviewProvider.notifier).reset();
    final Map<String, String>? applied = await showMatchReview(
      context,
      ingredients: unmatched,
      // Only a generated recipe carries these, and only the lines the real
      // chain cannot match will ever see them (spec §5.4).
      estimates: widget.imported?.estimates ?? const <AiEstimate>[],
    );
    if (applied == null || applied.isEmpty || !mounted) return;

    setState(() {
      final Map<String, String> next = <String, String>{..._matches};
      for (final MapEntry<String, String> entry in applied.entries) {
        final String key = normaliseKey(entry.key);
        next[key] = entry.value;
        _autoApplied.add(key);
      }
      _matches = next;
    });

    // Remembered like any other correction, so the same ingredient string is
    // never looked up twice (spec §5.3).
    final String household = ref.read(currentHouseholdIdProvider);
    for (final MapEntry<String, String> entry in applied.entries) {
      await ref
          .read(ingredientMatchStoreProvider)
          .remember(
            householdId: household,
            ingredientString: entry.key,
            foodId: entry.value,
            id: const Uuid().v4(),
            updatedAt: DateTime.now(),
          );
    }
    ref.invalidate(rememberedMatchesProvider);
  }

  Future<void> _matchIngredient(ParsedIngredient ingredient) async {
    final String key = normaliseKey(ingredient.name);
    final String? current = _matches[key];

    // Offer the best guess as the pre-selected option so the common case is
    // one tap rather than a search.
    final MatchSuggestion? suggestion = current != null
        ? null
        : IngredientMatcher.suggest(
            ingredientName: ingredient.name,
            library: _foods.values.toList(growable: false),
          );

    final String? chosen = await showFoodPicker(
      context,
      ingredientName: ingredient.name,
      currentFoodId: current ?? suggestion?.foodId,
    );
    if (chosen == null || !mounted) return;

    setState(() {
      final Map<String, String> next = <String, String>{..._matches};
      if (chosen == clearFoodSentinel) {
        next.remove(key);
        _autoApplied.remove(key);
      } else {
        next[key] = chosen;
        // A deliberate choice supersedes any auto-apply for this string.
        _autoApplied.add(key);
      }
      _matches = next;
    });

    // Remember it, so the same correction is never made twice (spec §5.3).
    if (chosen != clearFoodSentinel) {
      await ref
          .read(ingredientMatchStoreProvider)
          .remember(
            householdId: ref.read(currentHouseholdIdProvider),
            ingredientString: ingredient.name,
            foodId: chosen,
            id: const Uuid().v4(),
            updatedAt: DateTime.now(),
          );
    } else {
      await ref
          .read(ingredientMatchStoreProvider)
          .forget(
            householdId: ref.read(currentHouseholdIdProvider),
            ingredientString: ingredient.name,
          );
    }
    ref.invalidate(rememberedMatchesProvider);
  }

  RecipeDraft get _draft => RecipeDraft(
    title: _title.text,
    servings: double.tryParse(_servings.text.trim()) ?? 0,
    sections: <DraftSection>[
      for (final _SectionFields section in _sections) section.toDraft(),
    ],
    prepMinutes: int.tryParse(_prep.text.trim()),
    cookMinutes: int.tryParse(_cook.text.trim()),
    cuisine: _cuisine.text,
    tags: _tags.text
        .split(',')
        .map((String t) => t.trim())
        .where((String t) => t.isNotEmpty)
        .toList(growable: false),
    notes: _notes.text,
    existingId: _existingId,
    matches: _matches,
  );

  void _addSection() => setState(() {
    // The first section gets a name too, so a grouped recipe does not read as
    // "untitled group, then Sauce".
    if (_sections.length == 1 && _sections.first.name.text.trim().isEmpty) {
      _sections.first.name.text = Recipe.defaultSectionName;
    }
    _sections.add(_SectionFields());
  });

  void _removeSection(int index) => setState(() {
    _sections.removeAt(index).dispose();
    // Back to one section: the name goes with it, so the recipe returns to
    // showing no section chrome at all.
    if (_sections.length == 1 &&
        _sections.first.name.text.trim() == Recipe.defaultSectionName) {
      _sections.first.name.text = '';
    }
  });

  void _moveSection(int from, int to) =>
      setState(() => _sections.insert(to, _sections.removeAt(from)));

  @override
  void initState() {
    super.initState();
    final RecipeImportResult? imported = widget.imported;
    if (imported != null) _fill(imported.draft);
  }

  void _hydrate(Recipe recipe) => _fill(RecipeDraft.fromRecipe(recipe));

  void _fill(RecipeDraft draft) {
    _title.text = draft.title;
    _servings.text = draft.servings == draft.servings.roundToDouble()
        ? draft.servings.round().toString()
        : draft.servings.toString();
    _prep.text = draft.prepMinutes?.toString() ?? '';
    _cook.text = draft.cookMinutes?.toString() ?? '';
    _cuisine.text = draft.cuisine ?? '';
    _tags.text = draft.tags.join(', ');
    _notes.text = draft.notes ?? '';
    for (final _SectionFields section in _sections) {
      section.dispose();
    }
    _sections
      ..clear()
      ..addAll(draft.sections.map(_SectionFields.from));
    _existingId = draft.existingId;
    _matches = draft.matches;
    _loaded = true;
  }

  Future<void> _save() async {
    final RecipeDraft draft = _draft;
    if (!draft.isValid) {
      setState(() => _showErrors = true);
      return;
    }

    setState(() => _saving = true);
    try {
      final Recipe saved = draft.toRecipe();
      await ref.read(recipeRepositoryProvider).save(saved);
      // Pops the id, not nothing: an import needs to tell a save from a
      // cancel, because cancelling should leave you on the import screen to
      // try different pictures rather than throwing you back to the library.
      if (mounted) Navigator.of(context).pop(saved.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool editing = widget.recipeId != null;

    _foods = <String, Food>{
      for (final Food food
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };
    _autoApplyRemembered(
      ref.watch(rememberedMatchesProvider).value ?? const <String, String>{},
    );

    if (editing && !_loaded) {
      final AsyncValue<Recipe?> existing = ref.watch(
        recipeByIdProvider(widget.recipeId!),
      );
      return existing.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (Object e, StackTrace s) => Scaffold(
          body: Center(child: Text('Could not open that recipe.\n$e')),
        ),
        data: (Recipe? recipe) {
          if (recipe == null) {
            return const Scaffold(
              body: Center(child: Text('That recipe no longer exists.')),
            );
          }
          _hydrate(recipe);
          return _form(context, colors);
        },
      );
    }

    return _form(context, colors);
  }

  Widget _form(BuildContext context, HearthColors colors) {
    final HearthTextStyles text = context.text;
    final RecipeDraft draft = _draft;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(switch ((widget.recipeId, widget.imported)) {
          (final String? id, _) when id != null => 'Edit recipe',
          (_, final RecipeImportResult? i) when i != null => 'Check and save',
          _ => 'New recipe',
        }, style: text.sectionHeader),
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: HearthSpacing.sm),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            if (widget.imported?.uncertain case final List<AiUncertainty> notes
                when notes.isNotEmpty) ...<Widget>[
              _UncertainNotes(notes: notes),
              const SizedBox(height: HearthSpacing.lg),
            ],
            _Field(
              controller: _title,
              label: 'Title',
              hint: 'Braised short ribs',
              errorText: _showErrors ? draft.titleError : null,
              onChanged: _rebuild,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: HearthSpacing.lg),
            const SizedBox(height: HearthSpacing.lg),
            // A photo needs a recipe to belong to, so it is offered only once
            // there is one to attach it to (spec §5.2).
            RecipePhotoField(recipeId: _existingId),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Field(
                    controller: _servings,
                    label: 'Serves',
                    keyboardType: TextInputType.number,
                    errorText: _showErrors ? draft.servingsError : null,
                    onChanged: _rebuild,
                  ),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: _Field(
                    controller: _prep,
                    label: 'Prep (min)',
                    keyboardType: TextInputType.number,
                    onChanged: _rebuild,
                  ),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: _Field(
                    controller: _cook,
                    label: 'Cook (min)',
                    keyboardType: TextInputType.number,
                    onChanged: _rebuild,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.xl),
            for (int i = 0; i < _sections.length; i++) ...<Widget>[
              if (_sections.length > 1) ...<Widget>[
                _SectionHeader(
                  fields: _sections[i],
                  index: i,
                  count: _sections.length,
                  onChanged: _rebuild,
                  onMoveUp: i == 0 ? null : () => _moveSection(i, i - 1),
                  onMoveDown: i == _sections.length - 1
                      ? null
                      : () => _moveSection(i, i + 1),
                  onRemove: () => _removeSection(i),
                ),
                const SizedBox(height: HearthSpacing.md),
              ],
              _Field(
                controller: _sections[i].ingredients,
                label: 'Ingredients',
                hint:
                    '2 tbsp olive oil\n3 cloves garlic, minced\nsalt to taste',
                minLines: 4,
                maxLines: 12,
                onChanged: _rebuild,
              ),
              if (RecipeDraft.parseIngredients(_sections[i].ingredients.text)
                  .isNotEmpty) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                _IngredientPreview(
                  ingredients: RecipeDraft.parseIngredients(
                    _sections[i].ingredients.text,
                  ),
                  foods: _foods,
                  draft: draft,
                  onMatch: _matchIngredient,
                ),
                if (_unmatchedIn(i, draft) case final List<ParsedIngredient> u
                    when u.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.sm),
                  // Offered, not automatic. A dozen searches fired while
                  // someone is still typing their ingredients would be work
                  // nobody asked for, against services free to rate-limit us.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _findMatches(u),
                      icon: const Icon(Icons.travel_explore, size: 18),
                      label: Text(
                        u.length == 1
                            ? 'Find nutrition for 1 ingredient'
                            : 'Find nutrition for ${u.length} ingredients',
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: HearthSpacing.lg),
              _Field(
                controller: _sections[i].directions,
                label: 'Directions',
                hint: 'Paste or type. Steps are numbered automatically.',
                minLines: 4,
                maxLines: 14,
                onChanged: _rebuild,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: HearthSpacing.xl),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addSection,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add a section'),
              ),
            ),
            if (draft.parsedIngredients.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.lg),
              // Whole-recipe, not per section: nutrition is about the dish,
              // and a section's macros on their own are not a number anyone
              // eats (spec §5.2's flatten-for-nutrition).
              _LiveMacros(draft: draft, foods: _foods),
            ],
            if (draft.parsedDirections.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.lg),
              // Numbered straight through the recipe. A cook counting steps
              // counts the whole method, not each group from one.
              _DirectionsPreview(directions: draft.parsedDirections),
            ],
            const SizedBox(height: HearthSpacing.xl),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Field(
                    controller: _cuisine,
                    label: 'Cuisine',
                    onChanged: _rebuild,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: _Field(
                    controller: _tags,
                    label: 'Tags',
                    hint: 'weeknight, batch',
                    onChanged: _rebuild,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.lg),
            _Field(
              controller: _notes,
              label: 'Notes',
              minLines: 2,
              maxLines: 6,
              onChanged: _rebuild,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: HearthSpacing.xxl),
          ],
        ),
      ),
    );
  }

  void _rebuild(String _) => setState(() {});
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final ValueChanged<String> onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: HearthSpacing.xs),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          style: context.text.body,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            // The visible label is above the field; repeating it here would
            // make a screen reader say it twice.
            isDense: false,
          ),
        ),
      ],
    );
  }
}

/// Shows what the parser made of each ingredient line, and which food it is
/// matched to.
///
/// Two review jobs in one place: a misread quantity is caught by eye, and an
/// unmatched ingredient is visible as a gap rather than silently contributing
/// nothing to the macros (spec §5.3's review principle, applied to typing).
class _IngredientPreview extends StatelessWidget {
  const _IngredientPreview({
    required this.ingredients,
    required this.foods,
    required this.draft,
    required this.onMatch,
  });

  final List<ParsedIngredient> ingredients;
  final Map<String, Food> foods;
  final RecipeDraft draft;
  final ValueChanged<ParsedIngredient> onMatch;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return _PreviewCard(
      title: '${ingredients.length} ingredients',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final ParsedIngredient ingredient in ingredients)
            _IngredientRow(
              ingredient: ingredient,
              food: foods[draft.foodIdFor(ingredient.name)],
              onMatch: () => onMatch(ingredient),
              colors: colors,
              text: text,
            ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.food,
    required this.onMatch,
    required this.colors,
    required this.text,
  });

  final ParsedIngredient ingredient;
  final Food? food;
  final VoidCallback onMatch;
  final HearthColors colors;
  final HearthTextStyles text;

  @override
  Widget build(BuildContext context) {
    // Optional lines are excluded from macros on purpose, so they are not a
    // gap and must not be nagged about (spec §5.2).
    final bool needsMatch = food == null && !ingredient.isOptional;

    return Semantics(
      button: true,
      label:
          '${ingredient.quantity == null ? '' : '${QuantityFormat.formatAsAuthored(ingredient.quantity!)} '}'
          '${ingredient.name}. '
          '${food == null ? (ingredient.isOptional ? 'Optional, not counted.' : 'Not matched to a food.') : 'Matched to ${food!.name}.'}',
      onTap: onMatch,
      excludeSemantics: true,
      child: InkWell(
        onTap: onMatch,
        borderRadius: BorderRadius.circular(HearthRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 88,
                child: Text(
                  ingredient.quantity == null
                      ? '—'
                      : QuantityFormat.formatAsAuthored(ingredient.quantity!),
                  style: text.ingredient.copyWith(
                    color: ingredient.quantity == null
                        ? colors.textMuted
                        : colors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: ingredient.name,
                            style: text.ingredient,
                          ),
                          if (ingredient.prepNote != null)
                            TextSpan(
                              text: ', ${ingredient.prepNote}',
                              style: text.ingredient.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          if (ingredient.isOptional)
                            TextSpan(
                              text: '  optional',
                              style: text.metadata.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.xxs),
                    Row(
                      children: <Widget>[
                        Icon(
                          food != null
                              ? Icons.link
                              : needsMatch
                              ? Icons.link_off
                              : Icons.remove,
                          size: 13,
                          color: food != null
                              ? colors.accent
                              : colors.textMuted,
                        ),
                        const SizedBox(width: HearthSpacing.xs),
                        Flexible(
                          child: Text(
                            food != null
                                ? food!.name
                                : ingredient.isOptional
                                ? 'not counted'
                                : 'tap to match a food',
                            style: text.metadata.copyWith(
                              color: food != null
                                  ? colors.textSecondary
                                  : colors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-serving and whole-recipe macros, updating as ingredients change
/// (spec §5.2's live nutrition).
class _LiveMacros extends StatelessWidget {
  const _LiveMacros({required this.draft, required this.foods});

  final RecipeDraft draft;
  final Map<String, Food> foods;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    final Recipe provisional = draft.toRecipe(idFactory: () => 'preview');
    final RecipeMacros macros = MacroCalculator.forRecipe(
      provisional,
      foods: foods,
    );
    final Macros perServing = macros.perServing;

    return _PreviewCard(
      title: 'Nutrition per serving',
      // Missing data flags, never blocks (spec §5.3).
      note: macros.isIncomplete
          ? '${macros.incompleteIngredients.length} ingredient'
                '${macros.incompleteIngredients.length == 1 ? '' : 's'} '
                'not matched yet — not counted below.'
          : null,
      child: Row(
        children: <Widget>[
          for (final (String label, double value) in <(String, double)>[
            ('kcal', perServing.kcal),
            ('protein', perServing.proteinG),
            ('carbs', perServing.carbG),
            ('fat', perServing.fatG),
          ])
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value.round().toString(),
                    style: text.ingredient.copyWith(fontSize: 20),
                  ),
                  Text(
                    label,
                    style: text.metadata.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DirectionsPreview extends StatelessWidget {
  const _DirectionsPreview({required this.directions});

  final ParsedDirections directions;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;

    return _PreviewCard(
      title: '${directions.steps.length} steps',
      // Only an inferred split is worth flagging: numbered or bulleted input
      // was transcribed, not guessed at.
      note: directions.wasInferred
          ? 'Split from prose — check the breaks read right.'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final ParsedStep step in directions.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${step.number}.',
                      style: text.ingredient.copyWith(color: colors.accent),
                    ),
                  ),
                  Expanded(child: Text(step.text, style: text.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            if (note != null) ...<Widget>[
              const SizedBox(height: HearthSpacing.xxs),
              Row(
                children: <Widget>[
                  Icon(Icons.info_outline, size: 14, color: colors.textMuted),
                  const SizedBox(width: HearthSpacing.xs),
                  Expanded(
                    child: Text(
                      note!,
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: HearthSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// The text fields backing one section.
///
/// Controllers rather than plain strings so the cursor survives a rebuild —
/// rebuilding the whole editor on every keystroke is what the live preview
/// costs, and re-seeding a field's text would jump the caret to the end.
class _SectionFields {
  _SectionFields({
    String name = '',
    String ingredients = '',
    String directions = '',
    this.existingId,
  }) : name = TextEditingController(text: name),
       ingredients = TextEditingController(text: ingredients),
       directions = TextEditingController(text: directions);

  factory _SectionFields.from(DraftSection section) => _SectionFields(
    name: section.name,
    ingredients: section.ingredientsText,
    directions: section.directionsText,
    existingId: section.existingId,
  );

  final TextEditingController name;
  final TextEditingController ingredients;
  final TextEditingController directions;
  final String? existingId;

  DraftSection toDraft() => DraftSection(
    name: name.text,
    ingredientsText: ingredients.text,
    directionsText: directions.text,
    existingId: existingId,
  );

  void dispose() {
    name.dispose();
    ingredients.dispose();
    directions.dispose();
  }
}

/// A section's name, with the controls to move or remove it.
///
/// Move up/down rather than a drag handle: the sections are full of text
/// fields, where a long-press-to-drag fights the text selection gesture, and
/// two buttons are reachable by a screen reader in a way a drag never is.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.fields,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final _SectionFields fields;
  final int index;
  final int count;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Expanded(
        child: _Field(
          controller: fields.name,
          label: 'Section ${index + 1} of $count',
          hint: 'Sauce',
          onChanged: onChanged,
          textCapitalization: TextCapitalization.words,
        ),
      ),
      IconButton(
        icon: const Icon(Icons.arrow_upward),
        tooltip: 'Move section up',
        onPressed: onMoveUp,
      ),
      IconButton(
        icon: const Icon(Icons.arrow_downward),
        tooltip: 'Move section down',
        onPressed: onMoveDown,
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Remove section',
        onPressed: onRemove,
      ),
    ],
  );
}

/// What the reader could not make out (spec §5.3).
///
/// Named rather than merely counted. "Check the recipe" makes the user re-read
/// all of it; "the salt could be 1/2 tsp or 12 tsp" sends them to one field.
/// Everything is editable either way — this only says where to look first.
class _UncertainNotes extends StatelessWidget {
  const _UncertainNotes({required this.notes});

  final List<AiUncertainty> notes;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Never colour alone (§6.3): an icon and a sentence, not a tint.
              Icon(
                Icons.visibility_outlined,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: HearthSpacing.sm),
              Expanded(
                child: Text(
                  notes.length == 1
                      ? 'One thing worth checking'
                      : '${notes.length} things worth checking',
                  style: context.text.sectionHeader,
                ),
              ),
            ],
          ),
          const SizedBox(height: HearthSpacing.sm),
          for (final AiUncertainty note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: HearthSpacing.xxs),
              child: Text(
                note.field.isEmpty ? note.note : '${note.field} — ${note.note}',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
