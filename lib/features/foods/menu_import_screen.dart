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
import '../../domain/foods/pdf_batches.dart';
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

  /// The PDF being read, once one has been chosen.
  ///
  /// Held rather than re-picked so a second batch does not send somebody back
  /// to the file dialog to find the same document again.
  PickedPdf? _pdfFile;

  /// Which of its pages have been read, by number.
  ///
  /// A set rather than a count, because a page that would not render is not
  /// read and must come round again — a high-water mark would step over it
  /// and never look back.
  final Set<int> _pagesRead = <int>{};

  /// What the last read of this document actually looked at, and what it
  /// could not. Said afterwards in the same terms it was offered in, because
  /// "read pages 7–12" and "read pages 7, 8, 10 and 11" are different facts
  /// and only one of them is true.
  String? _pagesReadSaid;
  List<int> _pagesFailed = const <int>[];

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
      // Backing out of the picker. Not an error, and — the point of doing
      // this here rather than above — not a reason to throw away the review
      // work already on screen: opening a dialog and changing your mind used
      // to clear the doubts belonging to rows still sitting in the box.
      if (images.isEmpty) return;

      final MenuReading reading = await reader.read(images);
      if (!mounted) return;
      setState(() {
        // A doubt belongs to the rows it came with. Left standing over a new
        // read, it points at an item no longer on the screen. Cleared here,
        // where a read has actually happened, rather than on the way to one.
        _uncertain = const <AiUncertainty>[];
        // Added to, not over. A guide is read a page at a time, and a
        // hand-typed correction sits in the same box — overwriting destroys
        // both, with no undo.
        final String had = _pasted.text.trimRight();
        final String read = MenuImport.write(reading.rows);
        _pasted.text = had.isEmpty ? read : '$had\n$read';
        _uncertain = reading.uncertain;
        // Only where the field is still empty: a name already typed is a
        // decision, and a page's own branding is a guess.
        if (_restaurant.text.trim().isEmpty && reading.restaurant != null) {
          _restaurant.text = reading.restaurant!;
        }
      });
    } on RecipeAiException catch (error) {
      if (mounted) setState(() => _readError = error.message);
    } on Object {
      // A file dialog refused a permission, a PDF would not open, a picker
      // threw. None of those are a RecipeAiException, and catching only that
      // left the button snapping back with nothing said.
      if (mounted) {
        setState(() => _readError = 'Could not read that. Try again.');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<List<AiImage>> _photos() async {
    final List<PickedPhoto> picked = await ref
        .read(photoPickerProvider)
        .pickMultiple(max: 6);
    return <AiImage>[
      for (final PickedPhoto photo in picked) AiImage.ofPhoto(photo),
    ];
  }

  /// Chooses a PDF and reads its first batch of pages.
  ///
  /// Choosing and reading are two steps because they cost differently:
  /// opening the file to count its pages is free, and every page rendered
  /// after that is an image sent to the model. Knowing the length before
  /// paying for six pages is what lets the screen offer the other twelve
  /// instead of quietly calling six of eighteen "the menu".
  Future<List<AiImage>> _pdf() async {
    final PickedPdf? picked = await ref.read(pdfPagesProvider).pick();
    // Backed out of the dialog. Not an error, and nothing on screen changes.
    if (picked == null) return const <AiImage>[];

    setState(() {
      _pdfFile = picked;
      _pagesRead.clear();
      _pagesReadSaid = null;
      _pagesFailed = const <int>[];
    });
    return _renderBatch(picked);
  }

  /// Reads the next unread pages of the PDF already chosen.
  Future<List<AiImage>> _nextPdfBatch() {
    final PickedPdf? picked = _pdfFile;
    if (picked == null) return Future<List<AiImage>>.value(const <AiImage>[]);
    return _renderBatch(picked);
  }

  Future<List<AiImage>> _renderBatch(PickedPdf picked) async {
    final List<int> wanted = PdfBatches.next(
      pageCount: picked.pageCount,
      alreadyRead: _pagesRead,
    );
    if (wanted.isEmpty) return const <AiImage>[];

    final RenderedPdf rendered = await ref
        .read(pdfPagesProvider)
        .render(picked, pages: wanted);

    if (mounted) {
      setState(() {
        // Only what rendered counts as read. A page that failed stays unread
        // so the next batch offers it again rather than stepping over it.
        _pagesRead.addAll(rendered.numbers);
        _pagesFailed = rendered.failed;
        _pagesReadSaid = PdfBatches.describe(
          rendered.numbers,
          pageCount: picked.pageCount,
        );
      });
    }

    // Every page of the batch failed. Silent here, that is indistinguishable
    // from backing out of the dialog — and it is the opposite fact.
    if (rendered.pages.isEmpty) {
      throw RecipeAiException(
        'None of ${PdfBatches.describe(wanted, pageCount: picked.pageCount)} '
        'would render. Try screenshots of those pages instead.',
        isRetryable: false,
      );
    }

    return <AiImage>[
      for (final RenderedPage page in rendered.pages)
        AiImage(bytes: page.bytes, mediaType: 'image/png'),
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
            // The minus sign is the declaration (spec §5.2). A row the sheet
            // prints as a deduction is saved as one, which is also what lets
            // the negatives through the hosted checks at all.
            isModifier: line.isModifier,
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
              onChanged: (String _) =>
                  setState(() => _uncertain = const <AiUncertainty>[]),
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
                      label: Text(
                        _pdfFile == null
                            ? 'Read from a PDF'
                            : 'Read a different PDF',
                      ),
                    ),
                  // The rest of the document, offered explicitly and one batch
                  // at a time. Not automatic: every page is an image sent to
                  // the model, and a forty-page guide read whole without being
                  // asked is a bill nobody agreed to.
                  if (_pdfFile case final PickedPdf picked)
                    if (PdfBatches.next(
                          pageCount: picked.pageCount,
                          alreadyRead: _pagesRead,
                        )
                        case final List<int> next when next.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _reading ? null : () => _read(_nextPdfBatch),
                        icon: const Icon(Icons.more_horiz, size: 18),
                        label: Text(
                          'Read ${PdfBatches.describe(next, pageCount: picked.pageCount).toLowerCase()}',
                        ),
                      ),
                ],
              ),
              const SizedBox(height: HearthSpacing.sm),
              // What was read, in the document's own terms. The whole reason
              // this is here: six pages of eighteen is a fine offer, and six
              // pages of eighteen described as "the menu" is a wrong answer
              // with no way to notice.
              if (_pdfFile case final PickedPdf picked) ...<Widget>[
                Text(
                  <String>[
                    picked.name,
                    if (_pagesReadSaid case final String said)
                      '$said read'
                    else
                      '${picked.pageCount} pages',
                    if (PdfBatches.remaining(
                          pageCount: picked.pageCount,
                          alreadyRead: _pagesRead,
                        )
                        case final int left
                        when left > 0 && _pagesRead.isNotEmpty)
                      '$left not read yet',
                  ].join(' · '),
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (_pagesFailed.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // An icon as well as the colour, never colour alone
                      // (spec §6.3).
                      Icon(
                        Icons.report_problem_outlined,
                        size: 18,
                        color: colors.error,
                      ),
                      const SizedBox(width: HearthSpacing.xs),
                      Expanded(
                        child: Text(
                          '${PdfBatches.describe(_pagesFailed, pageCount: picked.pageCount)} '
                          'would not render, so nothing on it was read. It '
                          'will be offered again, or screenshot it instead.',
                          style: context.text.metadata.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: HearthSpacing.sm),
              ],
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
              onChanged: (String _) =>
                  setState(() => _uncertain = const <AiUncertainty>[]),
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
  /// A real minus sign rather than a hyphen, and the word as well as the
  /// sign: a deduction has to read as one to a screen reader too (§6.3).
  static String _signed(double value, String suffix) =>
      value < 0 ? '−${value.abs().round()}$suffix' : '${value.round()}$suffix';

  String _summary() {
    final String portion = QuantityFormat.format(line.portion!);
    final List<String> parts = <String>[
      _signed(line.macros.kcal, ' kcal'),
      _signed(line.macros.proteinG, 'g protein'),
      _signed(line.macros.carbG, 'g carbs'),
      _signed(line.macros.fatG, 'g fat'),
    ];
    final String head = line.isModifier ? 'Takes away · ' : '';
    return '$head$portion · ${parts.join(' · ')}';
  }
}
