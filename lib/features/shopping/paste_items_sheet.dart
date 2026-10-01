import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/shopping/manual_addition.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';

/// A held draft belongs to the account and household that opened it.
class ShoppingAdditionExpired implements Exception {
  const ShoppingAdditionExpired();

  static const String message =
      'Your account or household changed. Close this draft and start again.';
}

/// One pasted line becomes one editable item. Wording is never interpreted.
Future<List<ManualListItem>?> showPasteItemsSheet(
  BuildContext context, {
  required List<ShoppingLine> currentLines,
  Future<void> Function(List<ManualListItem> items)? onCommit,
  String? Function()? unavailableReason,
}) => showModalBottomSheet<List<ManualListItem>>(
  context: context,
  backgroundColor: context.colors.background,
  isScrollControlled: true,
  // A drag bypasses PopScope, so dismissal uses guarded back/barrier or Cancel.
  enableDrag: false,
  showDragHandle: false,
  constraints: BoxConstraints(
    maxWidth: 560,
    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
  ),
  builder: (BuildContext context) => _PasteItemsSheet(
    currentLines: currentLines,
    onCommit: onCommit,
    unavailableReason: unavailableReason,
  ),
);

/// Blank means no quantity; an explicit amount must survive canonicalization.
String? manualItemAmountError(String text, Unit unit) {
  if (text.trim().isEmpty) return null;
  final double? amount = parseAmount(text);
  final double? canonical = amount == null ? null : amount * unit.toCanonical;
  return canonical != null && canonical.isFinite && canonical > 0
      ? null
      : 'Enter an amount greater than zero, or leave it blank.';
}

/// Reused by a single item and every reviewed pasted row.
class ManualItemAmountFields extends StatelessWidget {
  const ManualItemAmountFields({
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
    required this.keyPrefix,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final Unit unit;
  final ValueChanged<Unit> onUnitChanged;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget amount = TextField(
      key: ValueKey<String>('$keyPrefix-amount'),
      controller: controller,
      enabled: enabled,
      // Fractions need a slash, which the iOS numeric keyboard lacks.
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Amount (optional)',
        hintText: '500, 12, or 1/2',
        errorText: manualItemAmountError(controller.text, unit),
        errorMaxLines: 4,
      ),
    );
    final Widget unitPicker = DropdownButtonFormField<Unit>(
      key: ValueKey<String>('$keyPrefix-unit'),
      initialValue: unit,
      isExpanded: true,
      itemHeight: null,
      decoration: const InputDecoration(labelText: 'Unit'),
      items: <DropdownMenuItem<Unit>>[
        for (final Unit value in <Unit>[
          Units.item,
          ...Units.all.where((Unit value) => value != Units.item),
        ])
          DropdownMenuItem<Unit>(
            value: value,
            child: Text(value == Units.item ? 'items' : value.label),
          ),
      ],
      onChanged: enabled
          ? (Unit? next) {
              if (next != null) onUnitChanged(next);
            }
          : null,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        if (box.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              amount,
              const SizedBox(height: HearthSpacing.md),
              unitPicker,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: amount),
            const SizedBox(width: HearthSpacing.md),
            Expanded(child: unitPicker),
          ],
        );
      },
    );
  }
}

class _DraftItem {
  _DraftItem(this.id, String name) : name = TextEditingController(text: name);

  final int id;
  final TextEditingController name;
  final TextEditingController amount = TextEditingController();
  Unit unit = Units.item;
  bool showAmount = false;

  bool get isValid =>
      name.text.trim().isNotEmpty &&
      manualItemAmountError(amount.text, unit) == null;

  ManualListItem get item => ManualListItem(
    name: name.text.trim(),
    quantity: amount.text.trim().isEmpty
        ? null
        : Quantity.of(parseAmount(amount.text)!, unit),
  );

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _PasteItemsSheet extends StatefulWidget {
  const _PasteItemsSheet({
    required this.currentLines,
    this.onCommit,
    this.unavailableReason,
  });

  final List<ShoppingLine> currentLines;
  final Future<void> Function(List<ManualListItem> items)? onCommit;
  final String? Function()? unavailableReason;

  @override
  State<_PasteItemsSheet> createState() => _PasteItemsSheetState();
}

class _PasteItemsSheetState extends State<_PasteItemsSheet> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_DraftItem> _allRows = <_DraftItem>[];
  List<_DraftItem>? _rows;
  bool _saving = false;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    for (final _DraftItem row in _allRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _review() {
    final List<ManualListItem> items = ManualAdditions.fromText(_text.text);
    if (items.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _rows = <_DraftItem>[
        for (int i = 0; i < items.length; i++) _DraftItem(i, items[i].name),
      ];
      _allRows.addAll(_rows!);
      for (final _DraftItem row in _rows!) {
        row.name.addListener(_changed);
        row.amount.addListener(_changed);
      }
    });
    _scroll.jumpTo(0);
  }

  Future<void> _save() async {
    if (_saving || _expired) return;
    final List<_DraftItem>? rows = _rows;
    if (rows == null || rows.isEmpty || rows.any((r) => !r.isValid)) return;
    final String? unavailable = widget.unavailableReason?.call();
    if (unavailable != null) {
      setState(() {
        _error = unavailable;
        _expired = true;
      });
      return;
    }
    final List<ManualListItem> items = <ManualListItem>[
      for (final _DraftItem row in rows) row.item,
    ];
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit?.call(items);
      if (!mounted) return;
      final String? reason = widget.unavailableReason?.call();
      if (reason != null) throw const ShoppingAdditionExpired();
      Navigator.of(context).pop(items);
    } on ShoppingAdditionExpired {
      if (!mounted) return;
      setState(() {
        _expired = true;
        _error = ShoppingAdditionExpired.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Could not add these items. Your changes are kept. Try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_DraftItem>? rows = _rows;
    // Invalid names stay editable, but cannot be passed to the domain model.
    // Amounts do not change duplicate identity, so previews need names only.
    final List<_DraftItem> named = <_DraftItem>[
      for (final _DraftItem row in rows ?? <_DraftItem>[])
        if (row.name.text.trim().isNotEmpty) row,
    ];
    final ManualAdditionResult preview = ManualAdditions.apply(
      widget.currentLines,
      <ManualListItem>[
        for (final _DraftItem row in named)
          ManualListItem(name: row.name.text.trim()),
      ],
    );
    final Map<int, ManualAdditionSkipReason> skipped =
        <int, ManualAdditionSkipReason>{
          for (final ManualAdditionSkip skip in preview.skipped)
            named[skip.index].id: skip.reason,
        };
    final bool canSave =
        !_saving &&
        !_expired &&
        rows != null &&
        rows.isNotEmpty &&
        rows.every((_DraftItem row) => row.isValid);
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            key: const ValueKey<String>('paste-items-scroll'),
            controller: _scroll,
            shrinkWrap: true,
            padding: const EdgeInsets.all(HearthSpacing.lg),
            children: <Widget>[
              Text(
                rows == null ? 'Paste items' : 'Review items',
                style: context.text.sectionHeader,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                rows == null
                    ? 'One item per line. Wording stays as pasted; you can '
                          'edit names and add amounts next.'
                    : 'Edit names, remove anything you do not need, and add '
                          'amounts if you know them. Matching items are skipped.',
                style: context.text.body,
              ),
              const SizedBox(height: HearthSpacing.md),
              if (rows == null) ...<Widget>[
                TextField(
                  key: const ValueKey<String>('paste-items-input'),
                  controller: _text,
                  minLines: 4,
                  maxLines: 6,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Items, one per line',
                    hintText: 'Coffee\nEggs\nPaper towels',
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
                FilledButton(
                  key: const ValueKey<String>('paste-items-review'),
                  onPressed: ManualAdditions.fromText(_text.text).isEmpty
                      ? null
                      : _review,
                  child: const Text('Review items'),
                ),
              ] else ...<Widget>[
                Text(
                  '${preview.added.length} ready to add · '
                  '${preview.skipped.length} will be skipped',
                  style: context.text.label,
                ),
                const SizedBox(height: HearthSpacing.md),
                for (int i = 0; i < rows.length; i++)
                  _row(rows[i], i, skipped[rows[i].id]),
                if (rows.isEmpty)
                  const Text('No items left to add. Cancel to start again.'),
                if (_error != null) ...<Widget>[
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: context.text.body),
                  ),
                  const SizedBox(height: HearthSpacing.md),
                ],
                FilledButton(
                  key: const ValueKey<String>('paste-items-save'),
                  onPressed: canSave ? _save : null,
                  child: Text(
                    _saving
                        ? 'Adding…'
                        : _error != null && !_expired
                        ? 'Retry'
                        : 'Add reviewed items',
                  ),
                ),
              ],
              const SizedBox(height: HearthSpacing.sm),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    _DraftItem row,
    int index,
    ManualAdditionSkipReason? skip,
  ) => Card.outlined(
    key: ValueKey<String>('paste-item-${row.id}'),
    margin: const EdgeInsets.only(bottom: HearthSpacing.md),
    child: Padding(
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Item ${index + 1}', style: context.text.label),
              ),
              IconButton(
                key: ValueKey<String>('paste-remove-${row.id}'),
                tooltip:
                    'Remove ${row.name.text.trim().isEmpty ? 'item ${index + 1}' : row.name.text.trim()}',
                onPressed: _saving || _expired
                    ? null
                    : () => setState(() => _rows!.remove(row)),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          TextField(
            key: ValueKey<String>('paste-name-${row.id}'),
            controller: row.name,
            enabled: !_saving && !_expired,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Item name',
              errorText: row.name.text.trim().isEmpty ? 'Enter a name.' : null,
            ),
          ),
          if (skip != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: Text(
                    skip == ManualAdditionSkipReason.alreadyOnList
                        ? 'Already on the list · will skip'
                        : 'Repeated in this paste · will skip',
                    style: context.text.metadata,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: HearthSpacing.sm),
          if (row.showAmount)
            ManualItemAmountFields(
              controller: row.amount,
              unit: row.unit,
              keyPrefix: 'paste-${row.id}',
              enabled: !_saving && !_expired,
              onUnitChanged: (Unit unit) => setState(() => row.unit = unit),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey<String>('paste-add-amount-${row.id}'),
                onPressed: _saving || _expired
                    ? null
                    : () => setState(() => row.showAmount = true),
                icon: const Icon(Icons.straighten),
                label: const Text('Add amount'),
              ),
            ),
        ],
      ),
    ),
  );
}
