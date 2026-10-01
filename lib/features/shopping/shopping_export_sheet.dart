import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/shopping_export.dart';
import '../../data/adapters/walmart_export.dart';
import '../../domain/models/food.dart';
import '../../domain/shopping/cart_quantity.dart';
import '../../domain/shopping/cart_review.dart';
import '../../domain/shopping/shopping_line.dart';

/// A local, trip-only package review before a deliberate external handoff.
///
/// Production callers supply both guards. [readCurrent] reads current local
/// shopping and food data, returning null if unavailable. [isCurrent] is a
/// latched account/household/route guard, checked after every asynchronous
/// boundary and immediately before invoking the platform. Static previews
/// and isolated tests may omit them. No edit in this sheet writes to storage.
Future<void> showShoppingExportSheet(
  BuildContext context,
  List<ShoppingLine> lines, {
  ShoppingExportAdapter adapter = const WalmartExport(),
  Map<String, Food> foods = const <String, Food>{},
  Future<ShoppingExportSource?> Function()? readCurrent,
  bool Function()? isCurrent,
}) {
  final ShoppingExportSource source = ShoppingExportSource(
    lines: lines,
    foods: foods,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _ExportSheet(
      source: source,
      adapter: adapter,
      readCurrent: readCurrent,
      isCurrent: isCurrent,
    ),
  );
}

enum _Handoff { cart, copy, search }

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.source,
    required this.adapter,
    required this.readCurrent,
    required this.isCurrent,
  });
  final ShoppingExportSource source;
  final ShoppingExportAdapter adapter;
  final Future<ShoppingExportSource?> Function()? readCurrent;
  final bool Function()? isCurrent;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ShoppingExportSource _source;
  late List<ShoppingExportItem> _items;
  final Map<String, TextEditingController> _counts =
      <String, TextEditingController>{};
  final Set<String> _skipped = <String>{};
  final Set<String> _confirmedCaps = <String>{};
  final ScrollController _scroll = ScrollController();
  String? _message;
  bool _busy = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.source);
  }

  void _load(ShoppingExportSource source) {
    for (final TextEditingController controller in _counts.values) {
      controller.dispose();
    }
    _counts.clear();
    _skipped.clear();
    _confirmedCaps.clear();
    _source = source;
    _items = exportableLines(source.lines, foods: source.foods);
    for (final ShoppingExportItem item in _items) {
      if (item.canChooseCartQuantity) {
        _counts[item.lineKey!] = TextEditingController(
          text: item.quantity?.toString() ?? '',
        );
      }
    }
    _revision++;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final TextEditingController controller in _counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _count(ShoppingExportItem item) {
    if (!item.canChooseCartQuantity || _skipped.contains(item.lineKey)) {
      return null;
    }
    final int? count = int.tryParse(_counts[item.lineKey]?.text ?? '');
    return count != null && count >= 1 && count <= CartQuantity.cap
        ? count
        : null;
  }

  bool _needsReview(ShoppingExportItem item) =>
      item.canChooseCartQuantity &&
      !_skipped.contains(item.lineKey) &&
      (_count(item) == null ||
          (item.wasCapped && !_confirmedCaps.contains(item.lineKey)));

  Map<String, int> get _productCounts =>
      CartReviewCounts.combine(<({String productId, int count})>[
        for (final ShoppingExportItem item in _items)
          if (_count(item) case final int count)
            (productId: item.productId!, count: count),
      ]);

  bool get _overProductCap =>
      _productCounts.values.any((int count) => count > CartQuantity.cap);

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final int included = _productCounts.length;
    final int pending = _items.where(_needsReview).length;
    final int excluded = _items
        .where(
          (ShoppingExportItem i) =>
              !i.canChooseCartQuantity || _skipped.contains(i.lineKey),
        )
        .length;
    final int unquantified = _items
        .where(
          (ShoppingExportItem i) => i.hasUnquantified || i.hasUnresolvedAmount,
        )
        .length;
    final double available =
        MediaQuery.sizeOf(context).height * .85 -
        MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(0, available)),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_message != null) ...<Widget>[
                    Semantics(liveRegion: true, child: Text(_message!)),
                    const SizedBox(height: HearthSpacing.md),
                  ],
                  Text(
                    'Take the list with you',
                    style: context.text.sectionHeader,
                  ),
                  const SizedBox(height: HearthSpacing.xs),
                  Text(
                    _items.isEmpty
                        ? 'Everything on the list is ticked off.'
                        : '${_items.length} ${_items.length == 1 ? 'item' : 'items'} still to buy. Ticked items are left out.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  if (_items.isNotEmpty) ...<Widget>[
                    const SizedBox(height: HearthSpacing.lg),
                    Text(
                      'Review package counts',
                      style: context.text.sectionHeader,
                    ),
                    const SizedBox(height: HearthSpacing.xs),
                    const Text(
                      'Need is what remains after the amount at home. Counts are for this trip only; your foods and shopping list stay as saved.',
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    const Text(
                      'Maximum 24 packages per product in this handoff.',
                    ),
                    if (unquantified > 0) ...<Widget>[
                      const SizedBox(height: HearthSpacing.sm),
                      Text(
                        unquantified == 1
                            ? '1 item still has an amount to check. It stays in the copied list and is left out of the basket.'
                            : '$unquantified items still have amounts to check. They stay in the copied list and are left out of the basket.',
                      ),
                    ],
                    for (final ShoppingExportItem item in _items) _row(item),
                    const SizedBox(height: HearthSpacing.md),
                    Text(
                      '$included ${included == 1 ? 'product' : 'products'} in this handoff. $excluded left out.',
                    ),
                    if (pending > 0)
                      Text(
                        '$pending ${pending == 1 ? 'item needs' : 'items need'} a quantity or review. Choose a count or Skip.',
                      ),
                    for (final MapEntry<String, int> product
                        in _productCounts.entries)
                      if (product.value > CartQuantity.cap)
                        Text(
                          'Rows for product ${product.key} total ${product.value} packages. Reduce or skip a count to stay within 24.',
                        ),
                    const SizedBox(height: HearthSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _busy ||
                                included == 0 ||
                                pending > 0 ||
                                _overProductCap
                            ? null
                            : () => _handoff(_Handoff.cart),
                        icon: const Icon(Icons.open_in_new),
                        label: Text('Review at ${widget.adapter.displayName}'),
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    Text(
                      'Confirm stock, prices and substitutions at ${widget.adapter.displayName}. Opening a link does not mark anything bought.',
                    ),
                    const SizedBox(height: HearthSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _handoff(_Handoff.copy),
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Copy the list'),
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _handoff(_Handoff.search),
                        icon: const Icon(Icons.search),
                        label: Text('Search ${widget.adapter.displayName}'),
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    const Text(
                      'Copy keeps the whole remaining list, including skipped items. Search opens the first item.',
                    ),
                  ],
                  const SizedBox(height: HearthSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ShoppingExportItem item) {
    final String key = item.lineKey!;
    final bool skipped = _skipped.contains(key);
    final int? count = _count(item);
    final String? pack = item.packLabel;
    final String purchase = count == null
        ? 'Choose quantity'
        : pack == null
        ? '$count ${count == 1 ? 'package' : 'packages'} (size not saved)'
        : '$count × $pack ${count == 1 ? 'pack' : 'packs'}';
    return Padding(
      key: ValueKey<String>('cart-row-$_revision-$key'),
      padding: const EdgeInsets.only(top: HearthSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(),
          Text(item.name, style: context.text.sectionHeader),
          if (item.productId != null) ...<Widget>[
            Text(
              'Saved product: ${item.productName ?? item.name}${item.productBrand == null || item.productBrand!.isEmpty ? '' : ' · ${item.productBrand}'}',
            ),
            Text(
              '${widget.adapter.displayName} item ${item.productId}',
              style: context.text.metadata,
            ),
          ],
          if (item.canChooseCartQuantity) ...<Widget>[
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'Need ${item.needLabel ?? 'amount not set'} → ${skipped ? 'Skipped this trip' : purchase}',
            ),
            if (item.quantity == null && !skipped)
              const Text(
                'Package conversion is unknown. Choose a count or Skip.',
              ),
            if (item.wasCapped && !skipped) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              const Text(
                'The calculated need exceeds 24 packages. The suggested count was limited to 24; check it before continuing.',
              ),
            ],
            const SizedBox(height: HearthSpacing.sm),
            TextField(
              key: ValueKey<String>('cart-count-$key'),
              controller: _counts[key],
              enabled: !_busy && !skipped,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                label: Text(
                  'Packages',
                  semanticsLabel: 'Packages for ${item.name}',
                ),
                helperText: '1–24 packages',
                helperMaxLines: 3,
                errorMaxLines: 3,
                errorText:
                    !skipped && _counts[key]!.text.isNotEmpty && count == null
                    ? 'Enter a whole number from 1 to 24.'
                    : null,
              ),
              onChanged: (_) => setState(() => _confirmedCaps.remove(key)),
            ),
            if (item.wasCapped && !skipped)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'I reviewed this limited count',
                  semanticsLabel:
                      'I reviewed the limited count for ${item.name}',
                ),
                value: _confirmedCaps.contains(key),
                onChanged: _busy
                    ? null
                    : (bool? value) => setState(() {
                        if (value == true) {
                          _confirmedCaps.add(key);
                        } else {
                          _confirmedCaps.remove(key);
                        }
                      }),
              ),
            CheckboxListTile(
              key: ValueKey<String>('cart-skip-$key'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Skip for this trip',
                semanticsLabel: 'Skip ${item.name} for this trip',
              ),
              value: skipped,
              onChanged: _busy
                  ? null
                  : (bool? value) => setState(() {
                      if (value == true) {
                        _skipped.add(key);
                      } else {
                        _skipped.remove(key);
                      }
                    }),
            ),
          ] else ...<Widget>[
            Text(
              'Need ${item.needLabel ?? item.quantityLabel ?? 'amount not set'}',
            ),
            Text(
              item.hasUnquantified || item.hasUnresolvedAmount
                  ? 'Left out: the complete amount is not measured. Copy or search for this item.'
                  : 'Left out: no saved ${widget.adapter.displayName} product. Copy or search for this item.',
            ),
          ],
        ],
      ),
    );
  }

  bool get _current => mounted && (widget.isCurrent?.call() ?? true);

  Future<bool> _checkSource() async {
    if (!_current) {
      _showMessage(
        'This review is no longer current. Close it and open your shopping list again.',
      );
      return false;
    }
    if (widget.readCurrent == null) return true;
    final ShoppingExportSource? source = await widget.readCurrent!();
    if (!_current) {
      _showMessage(
        'This review is no longer current. Close it and open your shopping list again.',
      );
      return false;
    }
    if (source == null) {
      _showMessage('The current list could not be checked. Try again.');
      return false;
    }
    if (source.fingerprint != _source.fingerprint) {
      setState(() {
        _load(source);
        _message = 'List or product changed. Your trip-only choices were reset. Review the new counts.';
      });
      _showFeedback();
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    if (mounted) {
      setState(() => _message = message);
      _showFeedback();
    }
  }

  void _showFeedback() {
    // The action is at the bottom of a potentially long review. Resetting
    // its source must bring the explanation into view, not leave it above
    // the viewport while a refreshed handoff button stays under the finger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _handoff(_Handoff action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (!await _checkSource()) return;
      if (action == _Handoff.cart &&
          (_items.any(_needsReview) || _overProductCap)) {
        return;
      }
      final List<ShoppingExportItem> reviewed = <ShoppingExportItem>[
        for (final ShoppingExportItem item in _items)
          item.withCartQuantity(_count(item)),
      ];
      final ShoppingExportResult result = await widget.adapter.export(reviewed);
      // A delayed adapter must not carry an old review past a source or
      // account change. Refreshing never continues the original tap.
      if (!await _checkSource() || !_current) return;
      if (action == _Handoff.copy) {
        if (result.clipboardText == null) return;
        await Clipboard.setData(ClipboardData(text: result.clipboardText!));
        if (!mounted || !_current) return;
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('List copied.')));
      } else {
        final Uri? link = action == _Handoff.cart
            ? result.cartLink
            : result.deepLinks.firstOrNull;
        if (link == null) return;
        final bool opened = await launchUrl(
          link,
          mode: LaunchMode.externalApplication,
        );
        if (!mounted || !_current) return;
        if (opened) {
          Navigator.of(context).pop();
        } else {
          _showMessage(
            'That link could not be opened. Try again or copy the list.',
          );
        }
      }
    } catch (_) {
      _showMessage(
        'The handoff could not be prepared. Try again or copy the list.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
