import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/unsaved_work_guard.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../data/local/editor_draft_store.dart';
import '../../data/repositories/ingredient_match_repository.dart';
import '../../domain/foods/no_match_rule.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/direction_parser.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/recipes/ingredient_matcher.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/text/text_normaliser.dart';
import '../foods/food_picker.dart';
import '../foods/read_label_sheet.dart';
import '../plan/logging_intent.dart';
import 'macro_stats_row.dart';
import 'match_review_controller.dart';
import 'match_review_screen.dart';
import 'recipe_chat_controller.dart' show ChatMessage;
import 'recipe_draft.dart';
import 'recipe_icon.dart';
import 'recipe_icon_controller.dart';
import 'recipe_import_controller.dart';
import 'recipe_photo.dart';
import 'recipe_revise_controller.dart';

/// The ways out of a line whose food cannot answer in its unit.
enum _FixChoice { addServing, readLabel, pickAnother, scan, unmatch, noMatch }

/// Create or edit a recipe (spec §5.2).
///
/// Ingredients and directions are typed or pasted as blocks and parsed live,
/// rather than filled into a field per quantity. Typing a recipe is already
/// the slow part of owning one; the parsers exist so this can be a paste.
///
/// The parse is always shown back before saving, so a misread quantity is
/// caught by eye rather than discovered later in a macro total.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({
    this.recipeId,
    this.imported,
    this.draft,
    this.intent,
    super.key,
  });

  /// The meal this recipe is being built for, when it began in one (U04).
  ///
  /// The restaurant builder starts on the day screen — a particular day, a
  /// particular slot — and ends here. Without it the editor knows only that a
  /// recipe was written, so it saves and stops, and the meal somebody was in
  /// the middle of logging is not logged.
  final LoggingIntent? intent;

  /// Null when creating.
  final String? recipeId;

  /// A recipe that arrived from an import or a generation (spec §5.3, §5.4).
  ///
  /// This screen is that review — the same way the food editor is the review
  /// for a barcode scan. It arrives filled in and entirely editable, and
  /// anything the model was unsure of is pointed at rather than left for the
  /// user to find.
  final RecipeImportResult? imported;

  /// A draft to open with, for a recipe that is neither new nor an import —
  /// today, a duplicate (spec §5.2). Unsaved, like an import: the copy is
  /// written only when Save is pressed.
  final RecipeDraft? draft;

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

  /// Cooked, or eaten out (spec §5.2). Held here rather than in a controller
  /// because it is a switch, not text.
  RecipeKind _kind = RecipeKind.cooked;
  bool _saving = false;
  String? _existingId;
  bool _showErrors = false;

  /// Waits out a burst of typing before writing the draft down (review N01).
  ///
  /// A keystroke is not worth a database write, and a write per keystroke
  /// would make the editor feel like it is thinking. Two seconds is short
  /// enough that a crash loses a phrase rather than a paragraph.
  Timer? _draftTimer;

  /// True once a restore has been offered, so a rebuild does not ask again.
  bool _draftAsked = false;

  /// What the recipe's `updatedAt` was when this editor opened.
  ///
  /// Compared against a draft's own record of the same thing, which is how a
  /// draft taken before the other phone edited the recipe is recognised as
  /// out of date rather than applied over their work.
  DateTime? _sourceUpdatedAt;

  /// The draft as the editor opened on it, for the unsaved-work guard
  /// (review F01). Null until the first fill, which is the moment before
  /// which there is nothing to lose.
  RecipeDraft? _openedDraft;

  /// Whether leaving now would lose something.
  ///
  /// A comparison rather than a flag set on every keystroke, so typing a
  /// character and deleting it again leaves the editor clean — an editor that
  /// asks when nothing actually differs teaches people to press Discard
  /// without reading it.
  ///
  /// Null baseline means the editor is still loading an existing recipe,
  /// which returns a spinner from `build` and never reaches the guard.
  bool get _isDirty =>
      _restored || (_openedDraft != null && _draft != _openedDraft);

  /// True once a draft has been put back. Work recovered is still work
  /// unsaved, however closely it happens to match its own baseline.
  bool _restored = false;

  /// The sketch icon this recipe already has (spec §5.2).
  ///
  /// Held rather than derived, because [_draft] is rebuilt from the text
  /// controllers on every keystroke and a field the draft does not carry is a
  /// field the next save deletes.
  String? _iconSvg;

  /// The title as it stood when the editor opened.
  ///
  /// The whole of the "regenerate only when the title changes materially"
  /// rule lives in this one field. Comparing against it at save time is what
  /// stops a note keystroke or an ingredient edit from spending money to
  /// redraw the same muffin.
  String _titleWhenOpened = '';

  /// Normalised ingredient name to food id, mirroring [RecipeDraft.matches].
  Map<String, String> _matches = <String, String>{};

  /// Lines marked as needing no food at all. Held here rather than derived
  /// from the household rules each build, so a mark made in this editor shows
  /// before the store has been re-read.
  Set<String> _noMatch = <String>{};

  /// Remembered matches already applied, so auto-apply runs once per string
  /// and never fights a user who has just unmatched something.
  final Set<String> _autoApplied = <String>{};

  @override
  void dispose() {
    _draftTimer?.cancel();
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
  /// Only defaults and remembered matches are applied silently — both are
  /// decisions this household already made. A best guess is offered in the
  /// picker instead of being assumed, because a wrong macro is worse than a
  /// missing one (spec §5.3).
  ///
  /// Lines that already carry a food are skipped, so this only ever fills a
  /// blank. Nothing anybody matched, or deliberately unmatched, is
  /// second-guessed.
  void _autoApplyTrustedMatches(
    Map<String, String> remembered,
    NoMatchRules noMatchRules,
  ) {
    final Map<String, String> next = <String, String>{..._matches};
    final Set<String> nextNoMatch = <String>{..._noMatch};
    bool changed = false;

    for (final ParsedIngredient ingredient in _draft.parsedIngredients) {
      final String key = normaliseKey(ingredient.name);
      if (key.isEmpty) continue;

      // Salt needs no food, and the household — or the list Hearth ships —
      // has already said so. Applied before matching is even attempted,
      // because there is nothing here to match.
      if (!next.containsKey(key) &&
          !nextNoMatch.contains(key) &&
          noMatchRules.covers(ingredient.name)) {
        nextNoMatch.add(key);
        changed = true;
        continue;
      }
      if (nextNoMatch.contains(key)) continue;
      if (next.containsKey(key)) continue;
      if (_autoApplied.contains(key)) continue;

      final MatchSuggestion? suggestion = IngredientMatcher.suggest(
        ingredientName: ingredient.name,
        library: _foods.values.toList(growable: false),
        remembered: remembered,
        // A recipe is matched against the kitchen it came out of: a bowl
        // resolves against the restaurant's menu and nothing else, a chilli
        // against the household's foods and nothing else (spec §5.2).
        kind: _kind,
      );
      if (suggestion == null || !suggestion.isTrusted) continue;

      next[key] = suggestion.foodId;
      _autoApplied.add(key);
      changed = true;
    }

    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _matches = next;
            _noMatch = nextNoMatch;
            // The baseline moves with them. Nobody chose these — the matcher
            // applied what the household had already decided elsewhere — so
            // counting them as unsaved work would ask "discard this recipe?"
            // over a recipe that was opened and not touched. A match the user
            // makes by hand goes through the review sheet, not through here,
            // and still counts.
            _openedDraft = _draft;
          });
        }
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
    for (final MapEntry<String, String> entry in applied.entries) {
      await ref
          .read(ingredientMatchRepositoryProvider)
          .remember(ingredientString: entry.key, foodId: entry.value);
    }
    ref.invalidate(rememberedMatchesProvider);
  }

  /// Opens the matched food's editor, for a line whose problem is the food
  /// rather than the match.
  ///
  /// "No serving in tbsp" is fixed by giving that food a serving in tbsp —
  /// sending the user to the food *picker* instead, as tapping the row used
  /// to, offers to solve it by choosing a different food, which is not what
  /// went wrong.
  Future<void> _fixFood(String foodId) async {
    await context.push<void>('/food/$foodId');
  }

  /// Reads the packet and opens the matched food's editor with it merged in.
  ///
  /// The same destination as "add a serving", with the numbers already
  /// filled: the food keeps every serving it had and gains the ones the label
  /// states, which for a US panel is usually a weight *and* a volume — the
  /// pair that lets a line measured in cups resolve against a food sold by
  /// weight. Still saved by hand from there (CLAUDE.md rule 4).
  Future<void> _readLabelFor(Food food) async {
    final LabelReading? reading = await showReadLabelSheet(context);
    if (reading == null || !mounted) return;
    await context.push<void>('/food/${food.id}', extra: reading);
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
            kind: _kind,
            // Not `remembered` here: a remembered match is already applied
            // by `_autoApplyTrustedMatches` before the row can even be tapped, so
            // `current` would already be set — passing it again would just
            // re-offer a match the user may have deliberately unmatched.
            previouslyUsed: ref.read(mostUsedFoodsProvider),
          );

    // Several defaults answering one line is the case worth showing rather
    // than resolving: "milk" against whole, 2% and non-fat has genuinely not
    // said which. One default never reaches here — it was applied already.
    final List<Food> defaults = current != null
        ? const <Food>[]
        : IngredientMatcher.defaultsFor(
            ingredient.name,
            _foods.values.toList(growable: false),
            kind: _kind,
          );

    final String? chosen = await showFoodPicker(
      context,
      ingredientName: ingredient.name,
      currentFoodId: current ?? suggestion?.foodId,
      defaults: defaults.length > 1 ? defaults : const <Food>[],
      // The same guard the row's own grass icon has carried all along
      // (`_offersNoMatch`): a line the recipe already excluded cannot show a
      // seasoning badge, so it is not offered one. The Seasonings screen is
      // where that list is managed.
      offerSeasoning: !ingredient.isOptional,
      // Only here. The eat-out builder attaches a deduction by name, so
      // renaming or re-splitting that line breaks the attachment — and
      // without this the line could never be matched again (spec §5.2).
      offerModifiers: _kind == RecipeKind.eatenOut,
    );
    await _applyMatch(ingredient, chosen);
  }

  /// Marks a line as one that will never have a food — salt, a spice — or
  /// takes the mark back off (spec §5.3).
  ///
  /// Both at once, deliberately: the draft changes so this recipe stops
  /// nagging now, and the household remembers so the next recipe using the
  /// same wording starts quiet. That is the whole of what Brendan asked for —
  /// select it, and have it stick.
  Future<void> _markNoMatch(
    ParsedIngredient ingredient, {
    required bool marked,
  }) async {
    if (!mounted) return;
    final String key = normaliseKey(ingredient.name);
    if (key.isEmpty) return;

    setState(() {
      _noMatch = <String>{..._noMatch};
      if (marked) {
        _noMatch.add(key);
        // A line that needs no food cannot also be matched to one.
        _matches = <String, String>{..._matches}..remove(key);
      } else {
        _noMatch.remove(key);
      }
    });

    final IngredientMatchRepository matches = ref.read(
      ingredientMatchRepositoryProvider,
    );
    if (marked) {
      await matches.rememberNoMatch(ingredient.name);
    } else {
      // Not `forget`: taking the mark off one of the seasonings Hearth ships
      // knowing about has to be recorded, or the built-in would simply put it
      // back on the next build.
      await matches.rememberNeedsMatch(ingredient.name);
    }
    ref.invalidate(noMatchRulesProvider);
    ref.invalidate(rememberedMatchesProvider);
  }

  /// Records what a line was matched to — or unmatched from.
  ///
  /// Shared by the picker, the scanner, and the unmatch action, because all
  /// three end in the same two things: the draft updated, and the decision
  /// remembered so the same correction is never made twice (spec §5.3).
  Future<void> _applyMatch(ParsedIngredient ingredient, String? chosen) async {
    if (chosen == null || !mounted) return;
    if (chosen == noMatchNeededSentinel) {
      await _markNoMatch(ingredient, marked: true);
      return;
    }
    final String key = normaliseKey(ingredient.name);

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

    final IngredientMatchRepository matches = ref.read(
      ingredientMatchRepositoryProvider,
    );
    if (chosen != clearFoodSentinel) {
      await matches.remember(ingredientString: ingredient.name, foodId: chosen);
    } else {
      await matches.forget(ingredient.name);
    }
    ref.invalidate(rememberedMatchesProvider);
  }

  /// What to do about a line whose food cannot answer in the unit it is
  /// written in.
  ///
  /// Four ways out, because the right one depends on what actually went
  /// wrong: the food is right and just needs this unit, the wrong food is
  /// attached, the packet is in your hand, or it should not be matched at
  /// all. Going straight to the food editor assumed the first and quietly
  /// removed the other three.
  Future<void> _showFixOptions(ParsedIngredient ingredient, Food food) async {
    final String unit =
        ingredient.quantity?.preferredUnit?.label ?? 'that unit';

    final _FixChoice? choice = await showModalBottomSheet<_FixChoice>(
      context: context,
      backgroundColor: context.colors.surface,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Text(
                '${food.name} has no serving in $unit',
                style: context.text.sectionHeader,
              ),
            ),
            for (final (_FixChoice value, IconData icon, String label)
                in <(_FixChoice, IconData, String)>[
                  (
                    _FixChoice.addServing,
                    Icons.straighten,
                    'Add a serving in $unit',
                  ),
                  // Above picking a different food, because the usual reason
                  // a line is flagged is not that the match is wrong — it is
                  // that the food only knows one unit, and the packet's own
                  // panel is the thing that states both.
                  if (canReadLabels(ref))
                    (
                      _FixChoice.readLabel,
                      Icons.document_scanner_outlined,
                      "Read the packet's label",
                    ),
                  (
                    _FixChoice.pickAnother,
                    Icons.search,
                    'Match a different food',
                  ),
                  (
                    _FixChoice.scan,
                    Icons.qr_code_scanner,
                    'Scan the packet instead',
                  ),
                  (_FixChoice.unmatch, Icons.link_off, 'Unmatch this line'),
                  (
                    _FixChoice.noMatch,
                    Icons.grass_outlined,
                    "Nothing to match — it's a seasoning",
                  ),
                ])
              ListTile(
                leading: Icon(icon, color: context.colors.textSecondary),
                title: Text(label, style: context.text.body),
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: HearthSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _FixChoice.addServing:
        await _fixFood(food.id);
      case _FixChoice.readLabel:
        await _readLabelFor(food);
      case _FixChoice.pickAnother:
        await _matchIngredient(ingredient);
      case _FixChoice.scan:
        await _applyMatch(
          ingredient,
          await context.push<String>('/food/scan?pick=1'),
        );
      case _FixChoice.unmatch:
        await _applyMatch(ingredient, clearFoodSentinel);
      case _FixChoice.noMatch:
        await _markNoMatch(ingredient, marked: true);
    }
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
    iconSvg: _iconSvg,
    kind: _kind,
    matches: _matches,
    noMatch: _noMatch,
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
    final RecipeDraft? initial = widget.imported?.draft ?? widget.draft;
    if (initial != null) {
      // Filled content is the baseline, not something to be asked about. An
      // import or a duplicate opens on a *review* screen, and Cancel there is
      // the reject answer that screen exists to offer (rule 4) — asking
      // "discard this recipe?" when somebody pressed the button meaning
      // exactly that is over-prompting, not protection. Edit the import and
      // Cancel does ask, because then there is something of yours in it.
      _fill(initial);
    } else {
      // A blank editor has a baseline too, and it is the blank editor. Only
      // an *existing* recipe reaches `_fill`, so without this a new recipe
      // never had one — and a guard with no baseline is a guard that never
      // fires, which is the defect it was built to fix.
      _openedDraft = _draft;
    }
  }

  void _hydrate(Recipe recipe) {
    _sourceUpdatedAt = recipe.updatedAt?.toUtc();
    _fill(RecipeDraft.fromRecipe(recipe));
  }

  /// Puts [draft] into the fields.
  ///
  /// [asOpened] says whether this *is* the recipe the editor opened on. It is
  /// false for a revision asked for in the panel below, and that distinction
  /// is the whole of [_titleWhenOpened]: filling the fields from an answer
  /// used to reset it, so revising "Pumpkin muffins" into "Vegan pumpkin
  /// muffins" and saving detected no change at all and left the muffins
  /// beside a dish they no longer described.
  void _fill(RecipeDraft draft, {bool asOpened = true}) {
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
    _iconSvg = draft.iconSvg;
    if (asOpened) _titleWhenOpened = draft.title;
    _kind = draft.kind;
    _matches = draft.matches;
    _noMatch = draft.noMatch;
    _loaded = true;
    // Read back out of the controllers rather than stored from the argument.
    // Filling normalises — 4.0 servings becomes the text "4", tags become a
    // joined string and split again — so the incoming draft and the one the
    // editor produces a moment later are not always equal, and using the
    // former as the baseline would leave every editor dirty on open.
    //
    // Set on every fill, so a revision accepted from the panel below becomes
    // the new baseline: having asked for it and kept it, being asked about it
    // again on the way out is noise.
    _openedDraft = _draft;
  }

  Future<void> _save() async {
    final RecipeDraft draft = _draft;
    if (!draft.isValid) {
      setState(() => _showErrors = true);
      return;
    }

    setState(() => _saving = true);
    try {
      // Read before the await: the editor pops the moment the save lands, and
      // the drawing outlives it.
      final RecipeIconController icons = ref.read(recipeIconControllerProvider);
      final Recipe drafted = draft.toRecipe();
      final bool redraw = RecipeIconController.needsDrawing(
        currentIcon: drafted.iconSvg,
        titleWhenOpened: _titleWhenOpened,
        titleNow: drafted.title,
        // A recipe that has never been saved has never been offered a sketch.
        // One that has, and has none, is one whose icon was removed, refused
        // or never arrived — and saving it again must not buy another.
        isNewRecipe: draft.existingId == null,
      );

      // The old sketch goes at the moment the title stops describing it.
      // Keeping it until a replacement arrives would be gentler, and it would
      // also mean muffins beside "Chicken noodle soup" for ever if the call
      // never came back.
      final Recipe saved = redraw
          ? drafted.copyWith(clearIconSvg: true)
          : drafted;
      await ref.read(recipeRepositoryProvider).save(saved);

      // Remembered before anything else can fail. The meal entry is written
      // after this, and if it throws the editor stays open with the button
      // live again — which is the retry. Without this the draft would mint a
      // fresh id on the way through and leave two copies of the same
      // restaurant meal in the library (§8.3: retain the saved recipe and
      // offer retry without duplicating it).
      _existingId = saved.id;

      // The draft goes once the recipe is committed locally, and not before.
      // A save that throws on the way here leaves it exactly where it was,
      // which is the moment it is worth most.
      await ref
          .read(editorDraftStoreProvider)
          .clear(kind: 'recipe', targetId: widget.recipeId);
      _restored = false;

      // Not awaited, deliberately (spec §5.2): saving a recipe must never sit
      // waiting on a picture. It lands in the store, so it appears on
      // whatever screen is showing the recipe by the time it arrives.
      if (redraw) {
        unawaited(icons.drawFor(recipeId: saved.id, title: saved.title));
      }
      // And onto the meal it was built for, if it was built for one.
      //
      // The day and the slot come from the intent that travelled here, never
      // from the clock: a dinner built for last Tuesday must not become
      // tonight's. The nutrition is frozen from the recipe as reviewed on
      // this screen, once — the same numbers the person just approved.
      if (widget.intent case final LoggingIntent intent) {
        final RecipeMacros macros = MacroCalculator.forRecipe(
          saved,
          foods: _foods,
        );
        try {
          await ref
              .read(planRepositoryProvider)
              .add(
                date: intent.date,
                slot: intent.slot,
                refType: PlanRefType.recipe,
                refId: saved.id,
                servings: 1,
                loggedMacros: intent.eaten ? macros.perServing : null,
                loggedCoverage: macros.coverage,
                label: saved.title,
              );
        } on Object {
          // The recipe is written and stays written; only the meal did not
          // land. Staying put with the button live is the retry, and the id
          // remembered above is what stops that retry writing the recipe
          // twice (§8.3).
          //
          // Object, not Exception: a type error from a malformed payload is
          // an Error, and letting it escape here would leave the editor
          // looking like it had done nothing at all.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Saved the recipe, but could not add it to '
                  '${intent.slot.name}. Try again.',
                ),
              ),
            );
          }
          return;
        }
      }

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
    _autoApplyTrustedMatches(
      ref.watch(rememberedMatchesProvider).value ?? const <String, String>{},
      ref.watch(noMatchRulesProvider).value ?? NoMatchRules.none,
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
    // Computed once for the whole form rather than per section and again for
    // the macro card: the ingredient rows and the nutrition summary are two
    // views of the same calculation, and they must never disagree about which
    // lines counted.
    final RecipeMacros macros = MacroCalculator.forRecipe(
      draft.toRecipe(idFactory: () => 'preview'),
      foods: _foods,
    );
    final Map<String, IngredientMacroStatus> statusByName =
        <String, IngredientMacroStatus>{
          for (final IngredientMacros part in macros.ingredients)
            normaliseKey(part.ingredient.name): part.status,
        };
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    // Hooked to the rebuild rather than to the text fields. Typing is only
    // one of fifteen ways this editor changes — adding a section, matching an
    // ingredient, switching kind — and hanging the draft off `onChanged`
    // meant the guard and the draft disagreed about what counts as work:
    // match a food, lose the app, and the match was gone although Cancel
    // would have asked about it. Every change goes through `setState`, so
    // this fires for all of them and there is no call site left to forget.
    // It only arms a timer, so a build stays a build.
    _rememberDraft();

    // After the first frame the editor is actually usable on — not in
    // `initState`, which for an existing recipe runs before the recipe has
    // been read and would compare a draft against nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDraft());

    return UnsavedWorkGuard(
      isDirty: () => _isDirty,
      what: 'recipe',
      child: Scaffold(
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
            onPressed: _saving ? null : _cancel,
            child: const Text('Cancel'),
          ),
          leadingWidth: 88,
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: HearthSpacing.sm),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? 'Saving…' : widget.intent?.action ?? 'Save',
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(gutter),
            children: <Widget>[
              if (widget.imported?.uncertain
                  case final List<AiUncertainty> notes
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
              const SizedBox(height: HearthSpacing.lg),
              RecipeIconField(
                recipeId: _existingId,
                svg: _iconSvg,
                onCleared: () => setState(() => _iconSvg = null),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Field(
                      controller: _servings,
                      label: 'Serves',
                      // A number pad on iOS has no decimal point, so a recipe
                      // that serves 4.5 could not be typed. Prep and cook
                      // beside it stay whole minutes.
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      errorText: _showErrors ? draft.servingsError : null,
                      onChanged: _rebuild,
                    ),
                  ),
                  // Nothing to prep and nothing to cook when somebody else did
                  // both (spec §5.2).
                  if (_kind == RecipeKind.cooked) ...<Widget>[
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
                  hint: '2 tbsp olive oil\n3 cloves garlic, minced\nsalt to taste',
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
                    statusByName: statusByName,
                    onMatch: _matchIngredient,
                    onFix: _showFixOptions,
                    onNoMatch: (ParsedIngredient i, bool marked) =>
                        _markNoMatch(i, marked: marked),
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
                _LiveMacros(macros: macros),
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
              const SizedBox(height: HearthSpacing.md),
              // Merged so a screen reader says "Eaten out, switch, off" as one
              // thing rather than three (§6.3).
              MergeSemantics(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Eaten out', style: context.text.body),
                          Text(
                            'A meal you ordered. Never goes on the shopping '
                            'list.',
                            style: context.text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _kind == RecipeKind.eatenOut,
                      onChanged: (bool value) => setState(() {
                        _kind = value ? RecipeKind.eatenOut : RecipeKind.cooked;
                        // Times belong to a recipe you cook. Cleared rather than
                        // hidden, so a bowl saved after the switch is flipped
                        // does not keep a prep time nobody can see.
                        if (value) {
                          _prep.clear();
                          _cook.clear();
                        }
                        // Anything *Hearth* matched was matched against the
                        // wrong kitchen and is dropped, so the auto-apply can
                        // answer again with the other library. Hand-picked
                        // matches are left exactly where they are — a person
                        // choosing a food is not a guess to revisit.
                        final Map<String, String> next = <String, String>{
                          ..._matches,
                        };
                        for (final String key in _autoApplied) {
                          next.remove(key);
                        }
                        _autoApplied.clear();
                        _matches = next;
                      }),
                    ),
                  ],
                ),
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
              // Last, deliberately. It is for correcting what the reader got
              // wrong, which is something you notice after reading down the
              // recipe — and putting it above the fields would push the save
              // button around every time the conversation grew.
              if (ref.watch(recipeAiProvider) != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.xl),
                _ReviseCard(
                  current: () => _draft,
                  // Not "as opened": a title the model changed on request is
                  // still a title change, and the sketch has to follow it.
                  onApply: (RecipeDraft revised) =>
                      setState(() => _fill(revised, asOpened: false)),
                ),
              ],
              const SizedBox(height: HearthSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  /// Leaves the editor, asking first if there is anything to lose.
  ///
  /// Routed through the same question the system back gesture asks, rather
  /// than popping directly: two ways out that disagree is one way out that
  /// silently does not protect anything.
  Future<void> _cancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    if (await UnsavedWorkGuard.confirm(context, 'recipe')) navigator.pop();
  }

  void _rebuild(String _) => setState(() {});

  /// Writes what is in the editor down, shortly.
  ///
  /// Only when there is something to lose: a clean editor has nothing worth
  /// recovering, and writing one would mean offering to restore a recipe
  /// somebody opened and read.
  void _rememberDraft() {
    _draftTimer?.cancel();
    if (!_isDirty) return;
    _draftTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || !_isDirty) return;
      await ref
          .read(editorDraftStoreProvider)
          .save(
            EditorDraft(
              kind: 'recipe',
              targetId: widget.recipeId,
              sourceUpdatedAt: _sourceUpdatedAt,
              payload: _draft.toJson(),
            ),
            at: DateTime.now().toUtc(),
          );
    });
  }

  /// Offers a draft back, once, if one outlived the last session.
  ///
  /// Asked rather than restored: a draft applied on open would put work in
  /// front of somebody who does not know where it came from, and — for an
  /// existing recipe — could quietly replace what their partner has since
  /// changed. Rule 4's spirit, one screen earlier.
  Future<void> _offerDraft() async {
    if (_draftAsked) return;
    _draftAsked = true;

    final EditorDraft? draft = await ref
        .read(editorDraftStoreProvider)
        .find(kind: 'recipe', targetId: widget.recipeId);
    if (draft == null || !mounted) return;

    // Moved on underneath. Restoring silently here is the one outcome worth
    // refusing outright: it would hand back a copy of a version the other
    // phone has already replaced.
    final bool stale =
        _sourceUpdatedAt != null &&
        draft.sourceUpdatedAt != null &&
        _sourceUpdatedAt!.isAfter(draft.sourceUpdatedAt!);

    final bool restore = await UnsavedWorkGuard.offerDraft(
      context,
      what: 'recipe',
      stale: stale,
    );
    if (!mounted) return;
    if (restore) {
      setState(() {
        _fill(RecipeDraft.fromJson(draft.payload));
        // Filling sets the baseline to the restored draft, which would leave
        // the editor *clean* — and leaving would then lose the very work just
        // recovered, without asking. It is not clean: it is exactly the
        // unsaved work it was before the app closed, and it says so until it
        // is saved.
        _restored = true;
      });
    } else {
      await ref
          .read(editorDraftStoreProvider)
          .clear(kind: 'recipe', targetId: widget.recipeId);
    }
  }
}

/// Asking for a change instead of typing it (spec §5.4).
///
/// The answer lands straight in the fields above. That is safe because
/// nothing here is saved — the editor *is* the review screen (CLAUDE.md
/// rule 4) — and it is undoable, which is what makes applying it directly
/// better than a second review screen in front of the first.
class _ReviseCard extends ConsumerStatefulWidget {
  const _ReviseCard({required this.current, required this.onApply});

  /// Read at the moment of asking, not captured: the user goes on typing
  /// between questions, and the answer has to be about what is on screen.
  final RecipeDraft Function() current;

  final ValueChanged<RecipeDraft> onApply;

  @override
  ConsumerState<_ReviseCard> createState() => _ReviseCardState();
}

class _ReviseCardState extends ConsumerState<_ReviseCard> {
  final TextEditingController _said = TextEditingController();

  @override
  void dispose() {
    _said.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _said.text.trim();
    if (text.isEmpty) return;
    _said.clear();

    final RecipeDraft? revised = await ref
        .read(recipeReviseProvider.notifier)
        .send(text, widget.current());
    if (revised != null) widget.onApply(revised);
  }

  Future<void> _retry() async {
    final RecipeDraft? revised = await ref
        .read(recipeReviseProvider.notifier)
        .retry(widget.current());
    if (revised != null) widget.onApply(revised);
  }

  void _undo() {
    final RecipeDraft? before = ref.read(recipeReviseProvider.notifier).undo();
    if (before != null) widget.onApply(before);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ReviseState state = ref.watch(recipeReviseProvider);
    final RecipeReviseController controller = ref.read(
      recipeReviseProvider.notifier,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Ask for a change', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Swap steps 2 and 3. Use the higher end of the beef range. '
              'This should serve 6.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            for (final ChatMessage message in state.messages) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              _ReviseLine(message: message),
            ],
            if (state case final ReviseFailed failed) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.error_outline, size: 18, color: colors.error),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      failed.message,
                      style: context.text.metadata.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (failed.canRetry)
                    TextButton(
                      onPressed: _retry,
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ],
            // The month's AI budget, said once it is worth saying. A quiet
            // line rather than a dialog: a warning that interrupts every
            // question is one nobody reads by the third time (§3, §8.1).
            if (controller.warning case final AiUsage usage) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'AI budget: ${usage.percent}% of this month used.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
            const SizedBox(height: HearthSpacing.md),
            TextField(
              controller: _said,
              enabled: !state.isBusy,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: context.text.body,
              decoration: InputDecoration(
                hintText: 'What should change?',
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.md),
            Row(
              children: <Widget>[
                if (controller.canUndo) ...<Widget>[
                  TextButton.icon(
                    onPressed: state.isBusy ? null : _undo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Undo'),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                ],
                Expanded(
                  child: SizedBox(
                    height: HearthTouch.minTarget,
                    child: FilledButton(
                      onPressed: state.isBusy ? null : _send,
                      child: Text(state.isBusy ? 'Thinking…' : 'Ask'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviseLine extends StatelessWidget {
  const _ReviseLine({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          message.fromUser ? Icons.person_outline : Icons.auto_awesome,
          size: 16,
          color: colors.textMuted,
        ),
        const SizedBox(width: HearthSpacing.sm),
        Expanded(
          child: Text(
            message.text,
            style: context.text.body.copyWith(
              color: message.fromUser
                  ? colors.textSecondary
                  : colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
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
    required this.statusByName,
    required this.onMatch,
    required this.onFix,
    required this.onNoMatch,
  });

  final List<ParsedIngredient> ingredients;
  final Map<String, Food> foods;
  final RecipeDraft draft;

  /// Why each line did or did not count, keyed by normalised ingredient name
  /// — the same key the matches themselves use.
  final Map<String, IngredientMacroStatus> statusByName;

  final ValueChanged<ParsedIngredient> onMatch;

  /// Offers the ways out of a line whose food cannot answer in its unit.
  final void Function(ParsedIngredient, Food) onFix;

  /// Marks a line as needing no food, or takes the mark back off.
  final void Function(ParsedIngredient, bool) onNoMatch;

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
              status: statusByName[normaliseKey(ingredient.name)],
              onMatch: () => onMatch(ingredient),
              onFix: () {
                final Food? matched = foods[draft.foodIdFor(ingredient.name)];
                if (matched != null) onFix(ingredient, matched);
              },
              onNoMatch: (bool marked) => onNoMatch(ingredient, marked),
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
    required this.status,
    required this.onMatch,
    required this.onFix,
    required this.onNoMatch,
    required this.colors,
    required this.text,
  });

  final ParsedIngredient ingredient;
  final Food? food;

  /// Null only for a line the macro calculation never saw — a blank one.
  final IngredientMacroStatus? status;

  final VoidCallback onMatch;

  /// Tapped instead of [onMatch] when the food is attached but unusable.
  final VoidCallback onFix;

  /// Marks the line as needing no food, or takes the mark back off.
  final ValueChanged<bool> onNoMatch;

  final HearthColors colors;
  final HearthTextStyles text;

  /// What the status line under the ingredient says, and how it looks.
  ///
  /// The row used to know only "linked" and "not linked", which made a line
  /// that was linked *and* unusable look exactly like one that was fine —
  /// the summary would count four problems and nothing on screen said which
  /// four. A gap that is not a missing match gets its own icon and its own
  /// words, because it wants a different fix.
  ({IconData icon, Color colour, String text}) _state() {
    final String name = food?.name ?? '';
    return switch (status) {
      IngredientMacroStatus.unconvertible => (
        icon: Icons.error_outline,
        colour: colors.error,
        text:
            '$name — no serving in '
            '${ingredient.quantity?.preferredUnit?.label ?? 'that unit'}. '
            'Tap to fix.',
      ),
      IngredientMacroStatus.noQuantity => (
        icon: Icons.error_outline,
        colour: colors.error,
        text: name.isEmpty
            ? 'no amount on this line'
            : '$name — no amount on this line',
      ),
      IngredientMacroStatus.optionalExcluded => (
        icon: Icons.remove,
        colour: colors.textMuted,
        text: 'not counted',
      ),
      // Not "not counted": that reads as a gap being tolerated. This line was
      // never going to have a food, and saying so is the whole point.
      //
      // Carries the accent a matched line carries, because it is the same
      // kind of answer: this row is *settled*. Muted put it with the unmatched
      // ones and made a finished row look like an unfinished one.
      IngredientMacroStatus.noMatchNeeded => (
        icon: Icons.grass,
        colour: colors.accent,
        text: 'seasoning — no match needed',
      ),
      IngredientMacroStatus.noFoodMatch => (
        icon: Icons.link_off,
        colour: colors.textMuted,
        text: 'tap to match a food',
      ),
      IngredientMacroStatus.resolved || null => (
        icon: food == null ? Icons.link_off : Icons.link,
        colour: food == null ? colors.textMuted : colors.accent,
        text: food?.name ?? 'tap to match a food',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color colour, String text}) state = _state();

    // A row whose food cannot answer in this unit has more than one thing
    // possibly wrong with it — the food may need that serving, or be the
    // wrong food entirely — so it opens the choices rather than the picker,
    // which can only ever offer a different food.
    final bool needsFixing =
        status == IngredientMacroStatus.unconvertible && food != null;
    final VoidCallback onTap = needsFixing ? onFix : onMatch;

    return Semantics(
      button: true,
      label:
          '${ingredient.quantity == null ? '' : '${QuantityFormat.formatAsAuthored(ingredient.quantity!)} '}'
          '${ingredient.name}. '
          '${state.text}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
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
                        // Icon and wording change together — the colour is
                        // reinforcement, never the only signal (spec §6.3).
                        Icon(state.icon, size: 13, color: state.colour),
                        const SizedBox(width: HearthSpacing.xs),
                        Flexible(
                          child: Text(
                            state.text,
                            style: text.metadata.copyWith(color: state.colour),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Only where it could help. A line already matched to a food, or
              // already excluded by the recipe's own words, does not want this
              // and a control on every row would be noise on most of them.
              if (_offersNoMatch)
                IconButton(
                  onPressed: () => onNoMatch(!_isNoMatch),
                  visualDensity: VisualDensity.compact,
                  tooltip: _isNoMatch
                      ? 'This does need a food after all'
                      : 'Nothing to match — it is a seasoning',
                  icon: Icon(
                    _isNoMatch ? Icons.grass : Icons.grass_outlined,
                    size: 18,
                    color: _isNoMatch ? colors.accent : colors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isNoMatch => status == IngredientMacroStatus.noMatchNeeded;

  bool get _offersNoMatch =>
      _isNoMatch ||
      status == IngredientMacroStatus.noFoodMatch ||
      status == IngredientMacroStatus.noQuantity ||
      (status == null && food == null);
}

/// Per-serving and whole-recipe macros, updating as ingredients change
/// (spec §5.2's live nutrition).
class _LiveMacros extends StatelessWidget {
  const _LiveMacros({required this.macros});

  /// Handed in already computed, so this card and the ingredient rows above
  /// it are guaranteed to be describing the same calculation.
  final RecipeMacros macros;

  @override
  Widget build(BuildContext context) {
    return _PreviewCard(
      title: 'Nutrition per serving',
      // Missing data flags, never blocks (spec §5.3) — and names the actual
      // gap, since "not matched" sent people to re-match ingredients that
      // were already matched and were never the problem.
      note: macros.incompleteReason,
      child: MacroStatsRow(macros: macros.perServing),
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
