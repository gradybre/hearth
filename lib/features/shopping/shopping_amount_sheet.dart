import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';

/// Setting what to buy, and how much of it you already have (spec §5.7).
///
/// Two numbers, one sheet, because they answer the same question from either
/// end: 1.5 lb of beef is two packets, and one of them is already in the
/// freezer. Neither touches the recipe — the recipes' own number stays on
/// screen throughout, so the difference is visible rather than silently
/// resolved.
/// [onRemove], when given, puts a Remove action in the sheet — the path to
/// taking a line off the list that does not need a swipe. Someone who cannot
/// make a confident horizontal drag still has to be able to do it (§6.3).
Future<ShoppingLine?> showShoppingAmountSheet(
  BuildContext context,
  ShoppingLine line, {
  VoidCallback? onRemove,
}) => showModalBottomSheet<ShoppingLine>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) =>
      _AmountSheet(line: line, onRemove: onRemove),
);

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.line, this.onRemove});

  final ShoppingLine line;

  /// Null where removal is not this sheet's business to offer.
  final VoidCallback? onRemove;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final Unit _unit =
      widget.line.fullAmount?.preferredUnit ??
      (widget.line.planned.isEmpty
          ? Units.item
          : widget.line.planned.first.preferredUnit ?? Units.item);

  late final TextEditingController _buy = TextEditingController(
    text: _initial(widget.line.fullAmount),
  );
  late final TextEditingController _have = TextEditingController(
    text: _initial(widget.line.onHand),
  );

  String _initial(Quantity? quantity) => quantity == null
      ? ''
      : QuantityFormat.formatAmount(quantity.amountIn(_unit), _unit);

  @override
  void dispose() {
    _buy.dispose();
    _have.dispose();
    super.dispose();
  }

  Quantity? _read(TextEditingController field) {
    final double? amount = parseAmount(field.text);
    if (amount == null || amount < 0) return null;
    return Quantity.of(amount, _unit);
  }

  void _apply() {
    final Quantity? buy = _read(_buy);
    final Quantity? have = _read(_have);
    final Quantity? was = widget.line.fullAmount;

    // "Wanted" is only recorded when it actually differs from the recipes.
    // Re-typing the same number should not leave the line wearing an "edited"
    // mark it did not earn.
    final bool changed =
        buy != null &&
        (was == null ||
            (buy.canonicalAmount - was.canonicalAmount).abs() > 1e-9);

    Navigator.of(context).pop(
      widget.line.copyWith(
        wanted: changed ? buy : null,
        clearWanted: !changed,
        onHand: have,
        clearOnHand: have == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool measurable = widget.line.isMeasurable;

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
          child: Padding(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.line.name, style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.xs),
                Text(
                  widget.line.planned.isEmpty
                      ? 'Added by hand.'
                      : 'The recipes call for '
                            '${widget.line.planned.map(QuantityFormat.format).join(' + ')}.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (!measurable) ...<Widget>[
                  const SizedBox(height: HearthSpacing.md),
                  // Two units at once and no density to reconcile them, so
                  // there is no single number to work from. Settling one by
                  // hand is the way out, and the tick still works meanwhile.
                  Text(
                    'This one is written two ways at once, so give it a single '
                    'amount to work from.',
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: HearthSpacing.lg),
                _AmountField(
                  controller: _buy,
                  label: 'Buy',
                  unit: _unit,
                  hint: 'How much to get',
                ),
                const SizedBox(height: HearthSpacing.md),
                _AmountField(
                  controller: _have,
                  label: 'Already have',
                  unit: _unit,
                  hint: 'Leave empty if none',
                ),
                const SizedBox(height: HearthSpacing.md),
                // On its own line rather than beside Reset and Done: three
                // buttons in one row overflows at 3x text, which is how the
                // export sheet broke.
                if (widget.onRemove case final VoidCallback remove)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: HearthTouch.minTarget,
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
                    SizedBox(
                      height: HearthTouch.minTarget,
                      child: FilledButton(
                        onPressed: _apply,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            // Text, not number: a shop measures in halves and quarters, and
            // the numeric keyboard has no way to type "1/2".
            keyboardType: TextInputType.text,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(amountCharacters),
            ],
            style: context.text.body,
            decoration: InputDecoration(
              labelText: label,
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
        const SizedBox(width: HearthSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: HearthSpacing.md),
          child: Text(
            unit.label.isEmpty ? 'item' : unit.label,
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
