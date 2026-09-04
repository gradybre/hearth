import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/repositories/food_repository.dart';
import '../../domain/foods/menu_import.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/units/quantity.dart';

/// Adding a whole restaurant menu by pasting it (spec §5.2).
///
/// The alternative is the food editor thirty times over, which is how a
/// perfectly good feature goes unused.
///
/// **The review is the screen**, not a step after it. What was read is under
/// the box being read from, updating as you paste, so a line the parser could
/// not understand is visible while the text that caused it is still in front
/// of you. That satisfies rule 4 more honestly than a second screen would:
/// nothing is written until Save, and what Save will write is what is on
/// screen.
class MenuImportScreen extends ConsumerStatefulWidget {
  const MenuImportScreen({super.key});

  @override
  ConsumerState<MenuImportScreen> createState() => _MenuImportScreenState();
}

class _MenuImportScreenState extends ConsumerState<MenuImportScreen> {
  final TextEditingController _restaurant = TextEditingController();
  final TextEditingController _pasted = TextEditingController();
  bool _saving = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _restaurant.dispose();
    _pasted.dispose();
    super.dispose();
  }

  List<MenuImportLine> get _lines => MenuImport.read(_pasted.text);

  String? get _restaurantError =>
      _restaurant.text.trim().isEmpty ? 'Which restaurant?' : null;

  Future<void> _save() async {
    final List<MenuImportLine> usable = <MenuImportLine>[
      for (final MenuImportLine line in _lines)
        if (line.isUsable) line,
    ];
    if (usable.isEmpty || _restaurantError != null) {
      setState(() => _showErrors = true);
      return;
    }

    setState(() => _saving = true);
    try {
      const Uuid uuid = Uuid();
      final String restaurant = _restaurant.text.trim();
      final FoodRepository repository = ref.read(foodRepositoryProvider);

      for (final MenuImportLine line in usable) {
        final Quantity portion = line.portion!;
        await repository.save(
          Food(
            id: uuid.v4(),
            name: line.name,
            brand: restaurant,
            source: FoodSource.restaurant,
            servingOptions: <ServingOption>[
              ServingOption(
                id: uuid.v4(),
                label: QuantityFormat.format(portion),
                amount: portion,
                macros: line.macros,
              ),
            ],
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(usable.length);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final List<MenuImportLine> lines = _lines;
    final int usable = MenuImport.usableIn(lines);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Paste a menu', style: context.text.sectionHeader),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: HearthSpacing.sm),
            child: SizedBox(
              height: HearthTouch.minTarget,
              child: FilledButton(
                onPressed: _saving || usable == 0 ? null : _save,
                child: Text(
                  _saving ? 'Saving…' : 'Save $usable',
                  style: context.text.label,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            TextField(
              controller: _restaurant,
              textCapitalization: TextCapitalization.words,
              onChanged: (String _) => setState(() {}),
              style: context.text.body,
              decoration: InputDecoration(
                labelText: 'Restaurant',
                hintText: 'Chipotle',
                errorText: _showErrors ? _restaurantError : null,
              ),
            ),
            const SizedBox(height: HearthSpacing.lg),
            Text(
              'One item per line: name, portion, calories, protein, carbs, '
              'fat — then fibre, sodium and cholesterol if the sheet gives '
              'them. Commas, tabs or a couple of spaces all separate, so a '
              'row copied out of a table works as it lands.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.sm),
            TextField(
              controller: _pasted,
              maxLines: 8,
              minLines: 4,
              onChanged: (String _) => setState(() {}),
              style: context.text.body,
              decoration: const InputDecoration(
                hintText: 'Chicken, 4 oz, 180, 32, 0, 7',
              ),
            ),
            const SizedBox(height: HearthSpacing.lg),
            if (lines.isEmpty)
              Text(
                'Nothing pasted yet.',
                style: context.text.body.copyWith(color: colors.textMuted),
              )
            else ...<Widget>[
              Text(
                usable == lines.length
                    ? '$usable to add'
                    : '$usable to add · ${lines.length - usable} Hearth '
                          'could not read',
                style: context.text.sectionHeader,
              ),
              const SizedBox(height: HearthSpacing.sm),
              for (final MenuImportLine line in lines) ...<Widget>[
                _LineRow(line: line),
                const SizedBox(height: HearthSpacing.sm),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// One read line, and what became of it.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final MenuImportLine line;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool ok = line.isUsable;

    return Semantics(
      label: ok
          ? '${line.name}, ${_summary()}'
          : '${line.raw}. Not read: ${line.problem}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          border: Border.all(color: ok ? colors.outline : colors.error),
        ),
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Icon and words, never colour alone (§6.3).
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
              color: ok ? colors.goodAccent : colors.error,
            ),
            const SizedBox(width: HearthSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ok ? line.name : line.raw.trim(),
                    style: context.text.ingredient,
                  ),
                  const SizedBox(height: HearthSpacing.xxs),
                  Text(
                    ok ? _summary() : line.problem!,
                    style: context.text.metadata.copyWith(
                      color: ok ? colors.textMuted : colors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this line will be saved as, in the words the food will wear.
  String _summary() {
    final String portion = QuantityFormat.format(line.portion!);
    final List<String> parts = <String>[
      '${line.macros.kcal.round()} kcal',
      '${line.macros.proteinG.round()}g protein',
      '${line.macros.carbG.round()}g carbs',
      '${line.macros.fatG.round()}g fat',
    ];
    return '$portion · ${parts.join(' · ')}';
  }
}
