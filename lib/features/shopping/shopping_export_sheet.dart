import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/shopping_export.dart';
import '../../data/adapters/walmart_export.dart';
import '../../domain/shopping/shopping_line.dart';

/// Handing the finished list to a shop (spec §5.7).
///
/// The list is fully editable up to this point and nothing has left the app;
/// this is the deliberate hand-off, and it says plainly what it can and cannot
/// do rather than promising a cart it has no way to fill.
Future<void> showShoppingExportSheet(
  BuildContext context,
  List<ShoppingLine> lines, {
  ShoppingExportAdapter adapter = const WalmartExport(),
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) =>
      _ExportSheet(lines: lines, adapter: adapter),
);

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.lines, required this.adapter});

  final List<ShoppingLine> lines;
  final ShoppingExportAdapter adapter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // What is left to buy. A ticked line and one you already have enough of
    // are the same thing to somebody in a shop: nothing to pick up.
    final List<ShoppingExportItem> items = exportableLines(lines);

    return SafeArea(
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
              Text('Take the list with you', style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.xs),
              Text(
                items.isEmpty
                    ? 'Everything on the list is ticked off.'
                    : '${items.length} ${items.length == 1 ? 'item' : 'items'} '
                          'still to buy. Ticked items are left out.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              if (items.isNotEmpty) ...<Widget>[
                const SizedBox(height: HearthSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _copy(context, items),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy the list'),
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openFirst(context, items),
                    icon: const Icon(Icons.open_in_new),
                    label: Text('Search ${adapter.displayName}'),
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
                // Said plainly rather than discovered: a button called
                // "Walmart" that opens a search page instead of filling a
                // basket should say so before it is pressed.
                Text(
                  '${adapter.displayName} has no public way for an app to fill '
                  'a basket, so this opens a search for the first item. '
                  'Copying the list is usually quicker.',
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: HearthSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    List<ShoppingExportItem> items,
  ) async {
    final ShoppingExportResult result = await adapter.export(items);
    final String? text = result.clipboardText;
    if (text == null || !context.mounted) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('List copied.')));
  }

  Future<void> _openFirst(
    BuildContext context,
    List<ShoppingExportItem> items,
  ) async {
    final ShoppingExportResult result = await adapter.export(items);
    if (result.deepLinks.isEmpty || !context.mounted) return;

    final bool opened = await launchUrl(
      result.deepLinks.first,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That link could not be opened.')),
      );
    }
  }
}
