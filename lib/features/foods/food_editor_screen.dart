import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/repositories/food_repository.dart';
import '../../domain/models/food.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/shopping/walmart_product.dart';
import '../../domain/units/unit.dart';
import 'food_draft.dart';
import 'read_label_sheet.dart';

/// Create or edit a food (spec §5.5).
///
/// Also the review screen a barcode scan lands on: [initialDraft] arrives
/// prefilled from Open Food Facts or USDA, and nothing reaches the library
/// until it is read and saved from here (CLAUDE.md rule 4). Every field stays
/// editable, because a packet's own numbers are sometimes wrong and the user's
/// correction has to win.
class FoodEditorScreen extends ConsumerStatefulWidget {
  const FoodEditorScreen({
    this.foodId,
    this.initialDraft,
    this.initialLabel,
    super.key,
  });

  final String? foodId;

  /// A food already filled in — from a barcode lookup, or from a miss that
  /// carries only the number. Ignored when [foodId] is set: an existing food
  /// loads its own values.
  final FoodDraft? initialDraft;

  /// A label read on the way here, merged in once the food has loaded.
  ///
  /// Separate from [initialDraft] because it has to be applied *after* an
  /// existing food's own values, not instead of them: the case it comes from
  /// is a flagged ingredient whose food has grams and needs a cup, and
  /// [FoodDraft.withLabel] is what keeps both.
  final LabelReading? initialLabel;

  @override
  ConsumerState<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends ConsumerState<FoodEditorScreen> {
  late FoodDraft _draft = _applyInitialLabel(
    widget.initialDraft ?? FoodDraft.blank(),
  );
  bool _loaded = false;
  bool _saving = false;
  bool _showErrors = false;

  /// What the food's provenance was before the restaurant switch touched it,
  /// so turning it back off restores the truth rather than saying "manual".
  late final FoodSource _wasSource = _draft.source == FoodSource.restaurant
      ? FoodSource.manual
      : _draft.source;

  bool get _isRestaurant => _draft.source == FoodSource.restaurant;

  /// A restaurant food with no restaurant on it cannot be grouped into a menu
  /// and would never appear in the builder — so it is asked for rather than
  /// silently accepted.
  String? get _restaurantError =>
      _isRestaurant && _draft.brand.trim().isEmpty ? 'Which restaurant?' : null;

  /// Units offered for a serving size, in groups.
  ///
  /// Grouped rather than listed flat because the third group is the reason it
  /// grew: a tub of protein powder is sold by the scoop and a cereal box by
  /// the bar, and a packet word buried below `fl oz` is a packet word nobody
  /// finds. Weights first — most labels lead with one.
  static final Map<String, List<Unit>> _servingUnits = <String, List<Unit>>{
    'Weight': <Unit>[Units.gram, Units.kilogram, Units.ounce, Units.pound],
    'Volume': <Unit>[
      Units.millilitre,
      Units.litre,
      Units.tsp,
      Units.tbsp,
      Units.cup,
      Units.flOz,
    ],
    'Packets and pieces': <Unit>[
      Units.item,
      Units.slice,
      Units.piece,
      Units.scoop,
      Units.bar,
      Units.patty,
      Units.square,
      Units.stick,
      Units.tortilla,
      Units.package,
      Units.packet,
      Units.container,
      Units.bottle,
      Units.can,
    ],
  };

  FoodDraft _applyInitialLabel(FoodDraft draft) => widget.initialLabel == null
      ? draft
      : draft.withLabel(widget.initialLabel!);

  /// Fills the draft from a photographed label (spec §5.5).
  ///
  /// Merged rather than replacing: the case this exists for is a food that
  /// already has grams and needs a cup, and a typed name must survive a
  /// picture. [FoodDraft.withLabel] holds those rules.
  ///
  /// Nothing is saved — this is the review screen, and it stays one.
  Future<void> _readLabel() async {
    final LabelReading? reading = await showReadLabelSheet(context);
    if (reading == null || !mounted) return;
    setState(() => _draft = _draft.withLabel(reading));

    if (reading.uncertain.isEmpty) return;
    // §5.3's flag-never-guess, at the one moment it matters: the user is
    // looking at numbers they are about to trust.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reading.uncertain.length == 1
              ? 'Worth checking: ${reading.uncertain.single.note}'
              : '${reading.uncertain.length} figures were hard to read — '
                    'check them against the packet.',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_draft.isValid || _restaurantError != null) {
      setState(() => _showErrors = true);
      return;
    }

    final Food food = _draft.toFood();
    final FoodRepository repository = ref.read(foodRepositoryProvider);

    // Spec §5.5: a likely duplicate is a soft warning with a merge option,
    // never a block — two genuinely different foods can share a name.
    final List<Food> duplicates = await repository.likelyDuplicatesOf(food);
    if (duplicates.isNotEmpty && mounted) {
      final bool? proceed = await _confirmDuplicate(duplicates);
      if (proceed != true) return;
    }

    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await repository.save(food);
      // Pops the id, not nothing: a scan started from a recipe ingredient
      // needs to know which food it just created so it can attach it. Callers
      // that only wanted the food saved ignore the result.
      if (mounted) Navigator.of(context).pop(food.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmDuplicate(List<Food> duplicates) {
    final HearthColors colors = context.colors;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text(
          'Already in your library?',
          style: context.text.sectionHeader,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              duplicates.length == 1
                  ? 'This looks like a food you already have:'
                  : 'This looks like foods you already have:',
              style: context.text.body,
            ),
            const SizedBox(height: HearthSpacing.sm),
            for (final Food duplicate in duplicates.take(3))
              Text(
                duplicate.brand == null
                    ? '· ${duplicate.name}'
                    : '· ${duplicate.name} (${duplicate.brand})',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            const SizedBox(height: HearthSpacing.md),
            Text(
              'You can still save it — two things can share a name.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.foodId != null;

    if (editing && !_loaded) {
      final AsyncValue<Food?> existing = ref.watch(
        foodByIdProvider(widget.foodId!),
      );
      return existing.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (Object e, StackTrace s) => Scaffold(
          body: Center(child: Text('Could not open that food.\n$e')),
        ),
        data: (Food? food) {
          if (food == null) {
            return const Scaffold(
              body: Center(child: Text('That food no longer exists.')),
            );
          }
          _draft = _applyInitialLabel(FoodDraft.fromFood(food));
          _loaded = true;
          return _form(context);
        },
      );
    }

    return _form(context);
  }

  Widget _form(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(switch ((widget.foodId, widget.initialDraft)) {
          (final String? id, _) when id != null => 'Edit food',
          (_, final FoodDraft? draft) when draft?.barcode.isNotEmpty ?? false =>
            'Check and save',
          _ => 'New food',
        }, style: context.text.sectionHeader),
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
            _TextField(
              label: 'Name',
              value: _draft.name,
              hint: 'Greek yogurt',
              errorText: _showErrors ? _draft.nameError : null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (String v) =>
                  setState(() => _draft = _draft.copyWith(name: v)),
            ),
            const SizedBox(height: HearthSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: _TextField(
                    // The restaurant *is* the brand — a food from Chipotle is
                    // branded Chipotle, and that one string is what groups a
                    // menu together. Only the label changes, so nothing has to
                    // be re-typed when the switch below is flipped.
                    label: _isRestaurant ? 'Restaurant' : 'Brand',
                    value: _draft.brand,
                    hint: _isRestaurant ? 'Chipotle' : null,
                    errorText: _showErrors ? _restaurantError : null,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (String v) =>
                        setState(() => _draft = _draft.copyWith(brand: v)),
                  ),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: _isRestaurant
                      // Where it sits on their menu, so the builder can lay it
                      // out the way they do rather than A to Z (spec §5.2).
                      // Optional: an unsectioned item is listed last, not
                      // hidden.
                      ? _TextField(
                          label: 'Menu section',
                          value: _draft.menuGroup,
                          hint: 'Proteins',
                          textCapitalization: TextCapitalization.words,
                          onChanged: (String v) => setState(
                            () => _draft = _draft.copyWith(menuGroup: v),
                          ),
                        )
                      // Nothing to tag with a shop. You do not buy a burrito
                      // bowl's chicken at Costco.
                      : _TextField(
                          label: 'Store',
                          value: _draft.storeTag,
                          hint: 'Costco',
                          textCapitalization: TextCapitalization.words,
                          onChanged: (String v) => setState(
                            () => _draft = _draft.copyWith(storeTag: v),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.sm),
            // The same control the other two food-level answers use, rather
            // than a hand-rolled row: SwitchListTile merges its own semantics,
            // so a screen reader says "From a restaurant, switch, off" as one
            // thing (§6.3).
            SwitchListTile.adaptive(
              value: _isRestaurant,
              onChanged: (bool on) => setState(() {
                _draft = _draft.copyWith(
                  source: on ? FoodSource.restaurant : _wasSource,
                  // A shop tag means nothing on a menu item, and leaving one
                  // behind would group a burrito bowl under Costco.
                  storeTag: on ? '' : null,
                );
              }),
              title: Text('From a restaurant', style: context.text.body),
              subtitle: Text(
                'Never matched into a recipe you cook — your chicken breast '
                'and their chicken are not the same food. Shows up when you '
                'build a meal you ate out.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: HearthSpacing.lg),
            // Only on a restaurant food. A deduction is a menu row — "make it
            // a lettuce wrap" — and there is nothing in a household's own
            // pantry that takes calories away.
            if (_isRestaurant) ...<Widget>[
              SwitchListTile.adaptive(
                value: _draft.isModifier,
                onChanged: (bool on) =>
                    setState(() => _draft = _draft.copyWith(isModifier: on)),
                title: Text(
                  'This takes away rather than adds',
                  style: context.text.body,
                ),
                subtitle: Text(
                  '"Make it a lettuce wrap", −180 calories. Enter the numbers '
                  'with their minus signs, as the sheet prints them. A '
                  'deduction is only ever picked in the eat-out builder, '
                  'against something you actually ordered.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: HearthSpacing.lg),
            ],
            // Only when there is something to confirm. A food with real
            // numbers on it has no zeros to vouch for, and offering the
            // question anyway would invite somebody to answer it wrongly.
            if (_draft.looksZeroCalorie) ...<Widget>[
              SwitchListTile.adaptive(
                value: _draft.isZeroCalorie,
                onChanged: (bool on) =>
                    setState(() => _draft = _draft.copyWith(isZeroCalorie: on)),
                title: Text(
                  'This really is 0 calories',
                  style: context.text.body,
                ),
                subtitle: Text(
                  'Black coffee, sparkling water, a zero-calorie sweetener. '
                  'Without this, a food with nothing on it is treated as one '
                  'whose numbers are missing.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: HearthSpacing.lg),
            ],
            // A standing choice, not a one-off correction. Marking it here
            // rather than from the library is deliberate: this is the screen
            // where you have just decided what this food *is*.
            SwitchListTile.adaptive(
              value: _draft.isDefault,
              onChanged: (bool on) =>
                  setState(() => _draft = _draft.copyWith(isDefault: on)),
              title: Text('Use this by default', style: context.text.body),
              subtitle: Text(
                'Recipes calling for this will match it on their own. Several '
                'kinds of one thing can each be a default — whole and 2% milk '
                'both — and a recipe that does not say which will ask.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: HearthSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Serving sizes',
                    style: context.text.sectionHeader,
                  ),
                ),
                // §5.5's fallback chain ends at manual entry, and this is
                // manual entry with the typing removed. It leads because it
                // is the faster path for anything with a panel on it, and
                // because it is the only thing here that can produce a weight
                // and a volume for the same portion — the pair a recipe line
                // measured in cups needs from a food sold by weight.
                if (canReadLabels(ref))
                  TextButton.icon(
                    onPressed: _readLabel,
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Read label'),
                  ),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _draft = _draft.copyWith(
                      servings: <ServingDraft>[
                        ..._draft.servings,
                        const ServingDraft(),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_showErrors && _draft.servingsError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                child: Text(
                  _draft.servingsError!,
                  style: context.text.metadata.copyWith(color: colors.error),
                ),
              ),
            // Shown whether or not Save has been pressed. The hosted database
            // refuses a negative outright and nothing local does, so a save
            // that looked fine would sit in the queue and fail on the way up
            // — better to say so beside the number that caused it.
            if (_draft.macrosError case final String message)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                child: Text(
                  message,
                  style: context.text.metadata.copyWith(color: colors.error),
                ),
              ),
            const SizedBox(height: HearthSpacing.sm),
            for (int i = 0; i < _draft.servings.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.md),
                child: _ServingRow(
                  serving: _draft.servings[i],
                  units: _servingUnits,
                  canRemove: _draft.servings.length > 1,
                  onChanged: (ServingDraft updated) => setState(() {
                    final List<ServingDraft> next = <ServingDraft>[
                      ..._draft.servings,
                    ];
                    next[i] = updated;
                    _draft = _draft.copyWith(servings: next);
                  }),
                  onRemove: () => setState(() {
                    final List<ServingDraft> next = <ServingDraft>[
                      ..._draft.servings,
                    ]..removeAt(i);
                    _draft = _draft.copyWith(servings: next);
                  }),
                ),
              ),

            const SizedBox(height: HearthSpacing.lg),
            // Optional, and skippable for most foods. Filling it in is what
            // turns "Take it shopping" from a search into a basket (§5.7).
            Text('Buying it at Walmart', style: context.text.label),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Paste a product link and Hearth remembers which product this '
              'is. Add the pack size and it works out how many to order.',
              style: context.text.metadata.copyWith(
                color: context.colors.textMuted,
              ),
            ),
            const SizedBox(height: HearthSpacing.sm),
            _TextField(
              label: 'Walmart link or item number',
              value: _draft.walmartItemId,
              hint: 'walmart.com/ip/…/10450479',
              onChanged: (String v) =>
                  setState(() => _draft = _draft.copyWith(walmartItemId: v)),
            ),
            if (_draft.walmartItemId.trim().isNotEmpty &&
                !WalmartProduct.looksValid(_draft.walmartItemId)) ...<Widget>[
              const SizedBox(height: HearthSpacing.xs),
              // Said here rather than discovered at the shop: an id that does
              // not parse is stored as nothing, and a basket that silently
              // omits this food is the first anyone would know about it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: context.colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      'No item number in that. Paste the whole product link, '
                      'or just the number from the end of it.',
                      style: context.text.metadata.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: HearthSpacing.md),
            _TextField(
              label: 'Sold in',
              value: _draft.packSize,
              hint: '1 lb',
              onChanged: (String v) =>
                  setState(() => _draft = _draft.copyWith(packSize: v)),
            ),
            const SizedBox(height: HearthSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _ServingRow extends StatefulWidget {
  const _ServingRow({
    required this.serving,
    required this.units,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final ServingDraft serving;
  final Map<String, List<Unit>> units;
  final bool canRemove;
  final ValueChanged<ServingDraft> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ServingRow> createState() => _ServingRowState();
}

class _ServingRowState extends State<_ServingRow> {
  /// Whether the three minor nutrients are showing (spec §5.6).
  ///
  /// Open whenever any of them has a value, so a food that knows its sodium
  /// never hides the fact behind a tap — and closed otherwise, costing no
  /// height at all, because the toggle lives in a row that already exists.
  late bool _minorOpen = _hasMinor;

  bool get _hasMinor =>
      widget.serving.fiber.trim().isNotEmpty ||
      widget.serving.sodium.trim().isNotEmpty ||
      widget.serving.cholesterol.trim().isNotEmpty;

  @override
  void didUpdateWidget(_ServingRow old) {
    super.didUpdateWidget(old);
    // A label read into this serving fills them in from underneath.
    if (_hasMinor && !_minorOpen) _minorOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ServingDraft serving = widget.serving;
    final Map<String, List<Unit>> units = widget.units;
    final bool canRemove = widget.canRemove;
    final ValueChanged<ServingDraft> onChanged = widget.onChanged;
    final VoidCallback onRemove = widget.onRemove;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: _TextField(
                    label: 'Amount',
                    value: serving.amount,
                    // A plain number pad on iOS offers digits and nothing
                    // else — no "." and no "/" — so a serving of 2/3 cup or
                    // 1.5 tsp simply could not be typed. There is no numeric
                    // keyboard carrying both, so this takes the full one and
                    // filters it down to what an amount can contain.
                    keyboardType: TextInputType.text,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(amountCharacters),
                    ],
                    onChanged: (String v) =>
                        onChanged(serving.copyWith(amount: v)),
                  ),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Unit',
                        style: context.text.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: HearthSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: serving.unitId,
                        isExpanded: true,
                        style: context.text.body.copyWith(
                          color: colors.textPrimary,
                        ),
                        dropdownColor: colors.surfaceElevated,
                        items: <DropdownMenuItem<String>>[
                          for (final MapEntry<String, List<Unit>> group
                              in units.entries) ...<DropdownMenuItem<String>>[
                            // A heading, not a choice — disabled so it cannot
                            // be picked, and skipped by the keyboard for the
                            // same reason.
                            DropdownMenuItem<String>(
                              enabled: false,
                              child: Text(
                                group.key,
                                style: context.text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                            for (final Unit unit in group.value)
                              DropdownMenuItem<String>(
                                value: unit.id,
                                child: Text(
                                  unit.label.isEmpty ? 'item' : unit.label,
                                ),
                              ),
                          ],
                        ],
                        onChanged: (String? value) {
                          if (value == null) return;
                          onChanged(serving.copyWith(unitId: value));
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _minorOpen = !_minorOpen),
                  tooltip: _minorOpen
                      ? 'Hide fibre, sodium and cholesterol'
                      : 'Add fibre, sodium and cholesterol',
                  icon: Icon(
                    _minorOpen ? Icons.expand_less : Icons.expand_more,
                    color: _hasMinor ? colors.accent : colors.textMuted,
                  ),
                ),
                if (canRemove)
                  IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove this serving size',
                    icon: Icon(Icons.close, color: colors.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: HearthSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _TextField(
                    label: 'kcal',
                    value: serving.kcal,
                    keyboardType: _decimal,
                    onChanged: (String v) =>
                        onChanged(serving.copyWith(kcal: v)),
                  ),
                ),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: _TextField(
                    label: 'Protein',
                    value: serving.protein,
                    keyboardType: _decimal,
                    onChanged: (String v) =>
                        onChanged(serving.copyWith(protein: v)),
                  ),
                ),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: _TextField(
                    label: 'Carbs',
                    value: serving.carbs,
                    keyboardType: _decimal,
                    onChanged: (String v) =>
                        onChanged(serving.copyWith(carbs: v)),
                  ),
                ),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: _TextField(
                    label: 'Fat',
                    value: serving.fat,
                    keyboardType: _decimal,
                    onChanged: (String v) =>
                        onChanged(serving.copyWith(fat: v)),
                  ),
                ),
              ],
            ),
            if (_minorOpen) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              // Their own rows rather than beside the four: seven fields
              // across overflows at 3x text, which is how the export sheet
              // broke.
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TextField(
                      label: 'Fibre (g)',
                      value: serving.fiber,
                      keyboardType: _decimal,
                      onChanged: (String v) =>
                          onChanged(serving.copyWith(fiber: v)),
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: _TextField(
                      label: 'Sodium (mg)',
                      value: serving.sodium,
                      keyboardType: _decimal,
                      onChanged: (String v) =>
                          onChanged(serving.copyWith(sodium: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HearthSpacing.sm),
              _TextField(
                label: 'Cholesterol (mg)',
                value: serving.cholesterol,
                keyboardType: _decimal,
                onChanged: (String v) =>
                    onChanged(serving.copyWith(cholesterol: v)),
              ),
              const SizedBox(height: HearthSpacing.xs),
              Text(
                'Leave blank if you do not know. A 0 says it has none.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A number pad that carries a decimal point.
///
/// `TextInputType.number` gives digits alone on iOS, which is why every macro
/// on this screen had to be a whole number — 3.6 g of fat could not be typed.
const TextInputType _decimal = TextInputType.numberWithOptions(decimal: true);

/// A labelled field driven by a value rather than a controller, so the parent
/// can hold the draft as immutable state.
class _TextField extends StatefulWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String value;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt an external change; never fight the user's cursor.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: HearthSpacing.xs),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textCapitalization: widget.textCapitalization,
          style: context.text.body,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
          ),
        ),
      ],
    );
  }
}
