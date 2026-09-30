import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/food_quantity_format.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/shopping/cart_quantity.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/units/mass_display_mode.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../../domain/units/unit_converter.dart';

/// Setting total needed and what is at home, with a live Buy result (§5.7).
///
/// Two numbers, one sheet, because they answer the same question from either
/// end: 1.5 lb of beef is two packets, and one of them is already in the
/// freezer. Neither touches the recipe — the recipes' own number stays on
/// screen throughout, so the difference is visible rather than silently
/// resolved.
/// [onRemove], when given, puts a Remove action in the sheet — the path to
/// taking a line off the list that does not need a swipe. Someone who cannot
/// make a confident horizontal drag still has to be able to do it (§6.3).
/// [food] is the food the line is matched to, when it is matched to one. It
/// decides how the recipes' own amounts read back — the summary the sheet
/// shows is the same one the list shows (spec R5).
Future<ShoppingLine?> showShoppingAmountSheet(
  BuildContext context,
  ShoppingLine line, {
  Food? food,
  Future<void> Function()? onRemove,
}) => showModalBottomSheet<ShoppingLine>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) =>
      _AmountSheet(line: line, food: food, onRemove: onRemove),
);

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.line, this.food, this.onRemove});

  final ShoppingLine line;

  /// Null where the line is matched to nothing.
  final Food? food;

  /// Null where removal is not this sheet's business to offer.
  final Future<void> Function()? onRemove;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  /// The line as every other surface reads it (spec R5).
  ///
  /// Totals settled against the food this line is matched to *now*, and a
  /// cupboard amount expressed in the need's own kind where the food's own
  /// data makes that legal. Derived for reading only: nothing here is
  /// written back, and the asks behind the line are never touched.
  late final ResolvedShoppingLine _resolved = ShoppingLineResolver.resolve(
    line: widget.line,
    food: widget.food,
  );

  /// The need the Total needed field edits, and the recipes' own amount it is judged
  /// against. Both derived, so the sheet opens on the number the list is
  /// already showing rather than on a stored total nobody has read in that
  /// form.
  late final Quantity? _neededAmount = _resolved.line.fullAmount;
  late final Quantity? _plannedAmount = _resolved.planned.length == 1
      ? _resolved.planned.first
      : null;

  /// What is already in the cupboard, in whatever kind it can honestly be
  /// shown in. The resolver converts it into the need's kind when the food
  /// can bridge the two and leaves it alone when it cannot — asking a weight
  /// how many cups it is has no answer, and inventing one here would be a
  /// density nobody stated.
  late final Quantity? _haveAmount = _resolved.onHand;

  /// Each field's unit, chosen the way every other surface chooses it: the
  /// food's display mode and pack size first (spec R3), so 30 oz of a thing
  /// sold in 10 oz bags stays 30 oz instead of climbing the ladder to
  /// 1.88 lb. The two fields are asked separately, because they are not
  /// always the same kind.
  late final Unit _neededUnit = _unitFor(_neededAmount ?? _plannedAmount);
  late final Unit _haveUnit = _haveAmount == null
      ? _neededUnit
      : _unitFor(_haveAmount);

  Unit _unitFor(Quantity? quantity) => quantity == null
      ? _authoredUnit
      : UnitConverter.displayUnitFor(
          quantity,
          massDisplayMode:
              widget.food?.massDisplayMode ?? MassDisplayMode.automatic,
          packSize: widget.food?.packSize,
        );

  /// The fallback for a line with nothing to measure — an item added by hand
  /// without an amount — which is what it always was.
  Unit get _authoredUnit =>
      widget.line.fullAmount?.preferredUnit ??
      (widget.line.planned.isEmpty
          ? Units.item
          : widget.line.planned.first.preferredUnit ?? Units.item);

  /// What each field was opened showing. Kept so an untouched field can hand
  /// back the quantity it was opened with rather than a re-parse of its own
  /// printed text: opening and saving without changing anything must not
  /// round 14.5 oz to whatever the editor happened to display, and must not
  /// turn a converted *view* of the cupboard into a new stored fact
  /// (spec R6).
  late final String _neededInitial = _initial(_neededAmount, _neededUnit);
  late final String _haveInitial = _initial(_haveAmount, _haveUnit);

  late final TextEditingController _needed = TextEditingController(
    text: _neededInitial,
  );
  late final TextEditingController _have = TextEditingController(
    text: _haveInitial,
  );

  String _initial(Quantity? quantity, Unit unit) => quantity == null
      ? ''
      : QuantityFormat.formatAmount(quantity.amountIn(unit), unit);

  @override
  void initState() {
    super.initState();
    _needed.addListener(_changed);
    _have.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _needed.dispose();
    _have.dispose();
    super.dispose();
  }

  /// What a field means now: whether it was typed in at all, and the amount
  /// it comes to if it was.
  ///
  /// Unmodified text is not an edit, so [stored] comes straight back — exact
  /// canonical amount, kind and authored unit, whatever the field happened
  /// to be displaying.
  ({bool edited, Quantity? value}) _read(
    TextEditingController field,
    String initial,
    Unit unit,
    Quantity? stored,
  ) {
    if (field.text.trim() == initial.trim()) {
      return (edited: false, value: stored);
    }
    final double? amount = parseAmount(field.text);
    if (amount == null || amount < 0) return (edited: true, value: null);
    return (edited: true, value: Quantity.of(amount, unit));
  }

  ShoppingLine get _draft {
    final ({bool edited, Quantity? value}) needed = _read(
      _needed,
      _neededInitial,
      _neededUnit,
      widget.line.wanted,
    );
    final ({bool edited, Quantity? value}) have = _read(
      _have,
      _haveInitial,
      _haveUnit,
      widget.line.onHand,
    );
    // A field nobody changed returns the exact stored fact, not a reparse of
    // rounded display text. That includes a null override and mixed units.
    final Quantity? wanted = needed.edited
        ? _asOverride(needed.value)
        : widget.line.wanted;
    return widget.line.copyWith(
      wanted: wanted,
      clearWanted: wanted == null,
      onHand: have.value,
      clearOnHand: have.value == null,
    );
  }

  bool _validField(TextEditingController field, String initial) =>
      field.text.trim() == initial.trim() ||
      field.text.trim().isEmpty ||
      (parseAmount(field.text) ?? -1) >= 0;

  bool get _valid =>
      _validField(_needed, _neededInitial) && _validField(_have, _haveInitial);

  void _apply() => Navigator.of(context).pop(_draft);

  /// [typed] as a decision of its own, or null when it is only the recipes'
  /// own amount retyped — which should not leave the line wearing an
  /// "edited" mark it did not earn.
  ///
  /// Judged against the settled planned amount rather than the stored total,
  /// because the settled amount is what the field was showing. A number in a
  /// different kind from the recipes' is always a decision: there is nothing
  /// to compare it with.
  Quantity? _asOverride(Quantity? typed) {
    if (typed == null) return null;
    final Quantity? planned = _plannedAmount;
    if (planned == null || planned.kind != typed.kind) return typed;
    final double tolerance = 1e-9 * (planned.canonicalAmount.abs() + 1);
    final bool same =
        (typed.canonicalAmount - planned.canonicalAmount).abs() <= tolerance;
    return same ? null : typed;
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ResolvedShoppingLine preview = ShoppingLineResolver.resolve(
      line: _draft,
      food: widget.food,
    );
    final Quantity? buy = preview.toBuy;
    final Quantity? pack = preview.pack;
    final String? packs =
        buy != null &&
            !buy.isZero &&
            pack != null &&
            pack.canonicalAmount > 0 &&
            buy.kind == pack.kind
        ? '${CartQuantity.forLine(line: preview.line, pack: pack)} × ${QuantityFormat.formatAsAuthored(pack)}'
        : null;
    final bool cannotSubtract =
        preview.onHand != null &&
        preview.line.fullAmount != null &&
        preview.onHand!.kind != preview.line.fullAmount!.kind;
    final bool mixed = _resolved.planned.length > 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(HearthRadius.xl),
            ),
          ),
          // Scrollable rather than fixed: the same content at 200% text is
          // taller than the sheet, and a clipped Done button is a sheet you
          // cannot finish (spec §6.3).
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.line.name, style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.xs),
                Text(
                  _resolved.planned.isEmpty
                      ? 'Needed: no amount set.'
                      : '${widget.line.isManual ? 'Needed' : 'Needed for meals'}: '
                            '${_resolved.planned.map((Quantity q) => FoodQuantityFormat.format(q, food: widget.food)).join(' + ')}',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (mixed) ...<Widget>[
                  const SizedBox(height: HearthSpacing.md),
                  Text(
                    'These amounts use different units with no known conversion. Keep them separate, or set one total needed below.',
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: HearthSpacing.lg),
                _AmountField(
                  controller: _needed,
                  label: 'Total needed',
                  unit: _neededUnit,
                  hint: 'Before subtracting what is at home',
                ),
                const SizedBox(height: HearthSpacing.md),
                _AmountField(
                  controller: _have,
                  label: 'Have at home',
                  // Its own unit, because what is in the cupboard is not
                  // always the same kind as what is needed and nothing here
                  // may convert it without the food's say-so.
                  unit: _haveUnit,
                  hint: 'Leave empty if none',
                ),
                const SizedBox(height: HearthSpacing.lg),
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        !_valid
                            ? 'Enter a valid amount'
                            : buy == null
                            ? 'Buy: ${preview.planned.isEmpty ? 'amount not set' : preview.planned.map((Quantity q) => FoodQuantityFormat.format(q, food: widget.food)).join(' + ')}'
                            : 'Buy ${FoodQuantityFormat.format(buy, food: widget.food)}',
                        style: context.text.sectionHeader,
                      ),
                      if (_valid && packs != null)
                        Text(packs, style: context.text.body),
                      Text(
                        'Total needed minus have at home.',
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (cannotSubtract)
                        Text(
                          'The at-home amount has no known conversion to the needed unit, so it has not been subtracted.',
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      if (widget.line.hasUnquantified)
                        Text(
                          'Plus an amount to taste that is not included in this calculation.',
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      if (widget.line.checked)
                        Text(
                          'Marked bought. These amounts do not change that check.',
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
                // On its own line rather than beside Reset and Done: three
                // buttons in one row overflows at 3x text, which is how the
                // export sheet broke.
                if (widget.onRemove case final Future<void> Function() remove)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: HearthTouch.minTarget,
                      ),
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          remove();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.error,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove from list'),
                      ),
                    ),
                  ),
                const SizedBox(height: HearthSpacing.sm),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        widget.line.copyWith(
                          clearWanted: true,
                          clearOnHand: true,
                        ),
                      ),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: HearthTouch.minTarget,
                      ),
                      child: FilledButton(
                        onPressed: _valid ? _apply : null,
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.unit,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final Unit unit;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String unitLabel = unit.label.isEmpty ? 'item' : unit.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: context.text.label),
        const SizedBox(height: HearthSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Semantics(
                label: '$label in $unitLabel',
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.text,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(amountCharacters),
                  ],
                  style: context.text.body,
                  decoration: InputDecoration(
                    hintText: hint,
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HearthRadius.md),
                      borderSide: BorderSide(color: colors.outline),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: HearthSpacing.sm),
            Text(
              unitLabel,
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
