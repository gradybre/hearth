import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/direction_parser.dart';
import '../../domain/parsing/ingredient_parser.dart';
import 'recipe_draft.dart';

/// Create or edit a recipe (spec §5.2).
///
/// Ingredients and directions are typed or pasted as blocks and parsed live,
/// rather than filled into a field per quantity. Typing a recipe is already
/// the slow part of owning one; the parsers exist so this can be a paste.
///
/// The parse is always shown back before saving, so a misread quantity is
/// caught by eye rather than discovered later in a macro total.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({this.recipeId, super.key});

  /// Null when creating.
  final String? recipeId;

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
  final TextEditingController _ingredients = TextEditingController();
  final TextEditingController _directions = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  String? _existingId;
  String? _existingSectionId;
  bool _showErrors = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _title,
      _servings,
      _prep,
      _cook,
      _cuisine,
      _tags,
      _ingredients,
      _directions,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  RecipeDraft get _draft => RecipeDraft(
    title: _title.text,
    servings: double.tryParse(_servings.text.trim()) ?? 0,
    ingredientsText: _ingredients.text,
    directionsText: _directions.text,
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
    existingSectionId: _existingSectionId,
  );

  void _hydrate(Recipe recipe) {
    final RecipeDraft draft = RecipeDraft.fromRecipe(recipe);
    _title.text = draft.title;
    _servings.text = draft.servings == draft.servings.roundToDouble()
        ? draft.servings.round().toString()
        : draft.servings.toString();
    _prep.text = draft.prepMinutes?.toString() ?? '';
    _cook.text = draft.cookMinutes?.toString() ?? '';
    _cuisine.text = draft.cuisine ?? '';
    _tags.text = draft.tags.join(', ');
    _ingredients.text = draft.ingredientsText;
    _directions.text = draft.directionsText;
    _notes.text = draft.notes ?? '';
    _existingId = draft.existingId;
    _existingSectionId = draft.existingSectionId;
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
      await ref.read(recipeRepositoryProvider).save(draft.toRecipe());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool editing = widget.recipeId != null;

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
        title: Text(
          widget.recipeId == null ? 'New recipe' : 'Edit recipe',
          style: text.sectionHeader,
        ),
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
            _Field(
              controller: _title,
              label: 'Title',
              hint: 'Braised short ribs',
              errorText: _showErrors ? draft.titleError : null,
              onChanged: _rebuild,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: HearthSpacing.lg),
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
            _Field(
              controller: _ingredients,
              label: 'Ingredients',
              hint: '2 tbsp olive oil\n3 cloves garlic, minced\nsalt to taste',
              minLines: 4,
              maxLines: 12,
              onChanged: _rebuild,
            ),
            if (draft.parsedIngredients.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              _IngredientPreview(ingredients: draft.parsedIngredients),
            ],
            const SizedBox(height: HearthSpacing.xl),
            _Field(
              controller: _directions,
              label: 'Directions',
              hint: 'Paste or type. Steps are numbered automatically.',
              minLines: 4,
              maxLines: 14,
              onChanged: _rebuild,
              textCapitalization: TextCapitalization.sentences,
            ),
            if (draft.parsedDirections.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
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

/// Shows what the parser made of each ingredient line.
///
/// The point is that a misread quantity is caught here, by eye, rather than
/// silently corrupting a macro total later (spec §5.3's review principle,
/// applied to typing as well as to import).
class _IngredientPreview extends StatelessWidget {
  const _IngredientPreview({required this.ingredients});

  final List<ParsedIngredient> ingredients;

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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 88,
                    child: Text(
                      ingredient.quantity == null
                          ? '—'
                          : QuantityFormat.format(ingredient.quantity!),
                      style: text.ingredient.copyWith(
                        color: ingredient.quantity == null
                            ? colors.textMuted
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
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
