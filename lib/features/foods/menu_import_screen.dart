import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/menu_reader.dart';
import '../../data/adapters/pdf_pages.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
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

  /// True while a picture is being read. Its own flag rather than sharing
  /// `_saving`: they disable different buttons and one can fail while the
  /// other has not started.
  bool _reading = false;

  /// What the model could not read cleanly, kept where the rows it produced
  /// can be seen beside it. The failure that matters here is silent — a value
  /// taken from the wrong column reads perfectly — so an admission of doubt is
  /// worth more than a clean-looking list.
  List<AiUncertainty> _uncertain = const <AiUncertainty>[];

  String? _readError;

  @override
  void dispose() {
    _restaurant.dispose();
    _pasted.dispose();
    super.dispose();
  }

  List<MenuImportLine> get _lines => MenuImport.read(_pasted.text);

  String? get _restaurantError =>
      _restaurant.text.trim().isEmpty ? 'Which restaurant?' : null;

  /// Reads a menu off pictures and puts the result **in the box**.
  ///
  /// Not straight into the library, and not into a list of its own. What the
  /// model produces becomes exactly the text a person would have pasted, and
  /// goes through the same parser and the same live review — so it is
  /// editable before it is saved, and nothing reaches the library along a path
  /// a hand paste could not also take (rule 4).
  Future<void> _read(Future<List<AiImage>> Function() pages) async {
    final MenuReader? reader = ref.read(menuReaderProvider);
    if (reader == null) return;

    setState(() {
      _reading = true;
      _readError = null;
    });
    try {
      final List<AiImage> images = await pages();
      if (images.isEmpty) return;

      final MenuReading reading = await reader.read(images);
      if (!mounted) return;
      setState(() {
        _pasted.text = MenuImport.write(reading.rows);
        _uncertain = reading.uncertain;
        // Only where the field is still empty: a name already typed is a
        // decision, and a page's own branding is a guess.
        if (_restaurant.text.trim().isEmpty && reading.restaurant != null) {
          _restaurant.text = reading.restaurant!;
        }
      });
    } on RecipeAiException catch (error) {
      if (mounted) setState(() => _readError = error.message);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<List<AiImage>> _photos() async {
    final List<PickedPhoto> picked = await ref
        .read(photoPickerProvider)
        .pickMultiple(max: 6);
    return <AiImage>[
      for (final PickedPhoto photo in picked)
        AiImage(
          bytes: photo.bytes,
          mediaType: photo.extension == 'png' ? 'image/png' : 'image/jpeg',
        ),
    ];
  }

  Future<List<AiImage>> _pdf() async {
    final RenderedPdf? rendered = await ref.read(pdfPagesProvider).pick();
    if (rendered == null) return const <AiImage>[];
    return <AiImage>[
      for (final Uint8List page in rendered.pages)
        AiImage(bytes: page, mediaType: 'image/png'),
    ];
  }

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
            menuGroup: line.section,
            menuOrder: line.order,
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
    // A heading is neither added nor unread — it is the shape of the menu.
    final int unreadable = lines
        .where((MenuImportLine l) => !l.isUsable && !l.isHeading)
        .length;
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
              'row copied out of a table works as it lands.\n\n'
              'A line with no numbers on it is read as a section — paste the '
              'sheet\'s own headings and the menu keeps its shape.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.sm),
            // Above the box, because reading a picture is what fills it —
            // offering it underneath would read as something you do after
            // pasting. Hidden rather than disabled without a backend, the way
            // the label reader's buttons are.
            if (ref.watch(menuReaderProvider) != null) ...<Widget>[
              Wrap(
                spacing: HearthSpacing.sm,
                runSpacing: HearthSpacing.sm,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _reading ? null : () => _read(_photos),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(
                      _reading ? 'Reading…' : 'Read from screenshots',
                    ),
                  ),
                  if (ref.watch(pdfPagesProvider).isSupported)
                    OutlinedButton.icon(
                      onPressed: _reading ? null : () => _read(_pdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Read from a PDF'),
                    ),
                ],
              ),
              const SizedBox(height: HearthSpacing.sm),
              if (_readError case final String message) ...<Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 18, color: colors.error),
                    const SizedBox(width: HearthSpacing.xs),
                    Expanded(
                      child: Text(
                        message,
                        style: context.text.metadata.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HearthSpacing.sm),
              ],
            ],
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
              // What the model would not vouch for, above the rows it
              // produced. A value taken from the wrong column reads perfectly
              // and is wrong in every day it is later logged into, so a
              // flagged doubt is worth more than a clean-looking list.
              if (_uncertain.isNotEmpty) ...<Widget>[
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(HearthRadius.md),
                    border: Border.all(color: colors.overAccent),
                  ),
                  padding: const EdgeInsets.all(HearthSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: colors.overAccent,
                          ),
                          const SizedBox(width: HearthSpacing.xs),
                          Text(
                            'Check these before saving',
                            style: context.text.body,
                          ),
                        ],
                      ),
                      for (final AiUncertainty doubt in _uncertain) ...<Widget>[
                        const SizedBox(height: HearthSpacing.xs),
                        Text(
                          '${doubt.field}: ${doubt.note}',
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
              ],
              Text(
                unreadable == 0
                    ? '$usable to add'
                    : '$usable to add · $unreadable Hearth could not read',
                style: context.text.sectionHeader,
              ),
              const SizedBox(height: HearthSpacing.sm),
              for (final MenuImportLine line in lines) ...<Widget>[
                if (line.isHeading)
                  Padding(
                    padding: const EdgeInsets.only(top: HearthSpacing.sm),
                    child: Text(line.name, style: context.text.sectionHeader),
                  )
                else
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
