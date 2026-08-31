import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
import 'ai_recipe_mapper.dart';
import 'recipe_import_controller.dart';

/// Bringing a recipe in from screenshots, a photo, or a link (spec §5.3).
///
/// The migration path off MacrosFirst, where a recipe spans two or three
/// screens — so several pictures make *one* recipe, not several. What comes
/// back opens in the editor to be read before it is saved; nothing is written
/// on the strength of an extraction alone (CLAUDE.md rule 4).
class RecipeImportScreen extends ConsumerStatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  ConsumerState<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

class _RecipeImportScreenState extends ConsumerState<RecipeImportScreen> {
  final TextEditingController _url = TextEditingController();

  /// Whether the review screen is already open for this extraction.
  ///
  /// Belt and braces alongside listening for the transition rather than the
  /// state: opening the review twice saves the recipe twice, and this screen
  /// has already done that once.
  bool _reviewing = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Hands the extraction to the editor, which is the review screen.
  Future<void> _review(AiRecipe recipe) async {
    if (_reviewing) return;
    _reviewing = true;

    final RecipeImportController controller = ref.read(
      recipeImportProvider.notifier,
    );
    try {
      final String? saved = await context.push<String>(
        '/recipe/new',
        extra: RecipeImportResult(
          draft: AiRecipeMapper.toDraft(recipe),
          uncertain: recipe.uncertain,
        ),
      );
      if (!mounted) return;

      if (saved == null) {
        // Backed out of the review. Leave the pictures where they are so a
        // second look, or a different set, does not start from nothing.
        controller.clearResult();
        return;
      }

      controller.reset();
      _url.clear();
      if (mounted) Navigator.of(context).maybePop();
    } finally {
      _reviewing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final RecipeImportState state = ref.watch(recipeImportProvider);
    final RecipeImportController controller = ref.read(
      recipeImportProvider.notifier,
    );
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    // Listened for rather than read out of the state, because this navigates.
    //
    // Scheduling the push from build() meant every rebuild that happened while
    // the state was Done pushed another review — a keyboard dismissing during
    // the transition was enough — and importing two images once produced three
    // identical recipes. ref.listen fires on the *change* into Done, which
    // happens exactly once per reading.
    ref.listen<RecipeImportState>(recipeImportProvider, (
      RecipeImportState? previous,
      RecipeImportState next,
    ) {
      if (next is RecipeImportDone && previous is! RecipeImportDone) {
        _review(next.recipe);
      }
    });

    final bool busy = state is RecipeImportReading;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Import a recipe', style: context.text.sectionHeader),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            Text('From your screen', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Up to ${RecipeImportController.maxImages} pictures of the same '
              'recipe — a recipe that runs over two screens is two pictures, '
              'not two recipes.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: HearthSpacing.md),
            _PickedStrip(
              images: state.images,
              onRemove: busy ? null : controller.removePhoto,
            ),
            // The strip scrolls sideways, so past about four pictures you can
            // no longer see how many you have — which matters at ten in a way
            // it never did at three.
            if (state.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: HearthSpacing.xs),
                child: Text(
                  '${state.images.length} of '
                  '${RecipeImportController.maxImages} pictures',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
            if (state.images.length < RecipeImportController.maxImages)
              Padding(
                padding: const EdgeInsets.only(top: HearthSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => controller.addPhotos(PhotoOrigin.library),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose pictures'),
                      ),
                    ),
                    if (ref.read(photoPickerProvider).canUseCamera) ...<Widget>[
                      const SizedBox(width: HearthSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => controller.addPhotos(PhotoOrigin.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Take one'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: HearthSpacing.xl),
            Text('From a link', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.sm),
            TextField(
              controller: _url,
              enabled: !busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: controller.setUrl,
              style: context.text.body,
              decoration: InputDecoration(
                hintText: 'https://…',
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.xl),
            SizedBox(
              height: HearthTouch.minTarget,
              child: FilledButton(
                onPressed: busy || !state.hasSomethingToRead
                    ? null
                    : controller.read,
                child: Text(busy ? 'Reading…' : 'Read the recipe'),
              ),
            ),
            if (state is RecipeImportReading) ...<Widget>[
              const SizedBox(height: HearthSpacing.lg),
              _Reading(what: state.what),
            ],
            if (state is RecipeImportFailed) ...<Widget>[
              const SizedBox(height: HearthSpacing.lg),
              _Failed(
                message: state.message,
                onRetry: state.canRetry ? controller.retry : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickedStrip extends StatelessWidget {
  const _PickedStrip({required this.images, required this.onRemove});

  final List<PickedPhoto> images;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: HearthSpacing.sm),
        itemBuilder: (BuildContext context, int index) => Stack(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              child: Image.memory(
                images[index].bytes,
                width: 84,
                height: 108,
                fit: BoxFit.cover,
                // A format Flutter cannot decode — HEIC on desktop, say — is
                // still a picture the reader may cope with. Showing a tile
                // rather than throwing keeps the import available.
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        Container(
                          width: 84,
                          height: 108,
                          color: context.colors.surfaceSunken,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_outlined,
                            color: context.colors.textMuted,
                          ),
                        ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: 'Remove picture ${index + 1}',
                onTap: onRemove == null ? null : () => onRemove!(index),
                excludeSemantics: true,
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.cancel),
                  color: context.colors.textPrimary,
                  onPressed: onRemove == null ? null : () => onRemove!(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.what});

  final String what;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: HearthSpacing.md),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(
            'Reading $what. This takes a few seconds.',
            style: context.text.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    ],
  );
}

/// A failure that kept everything the user chose (spec §5.3's fail-soft).
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Never colour alone (§6.3).
              Icon(Icons.error_outline, size: 18, color: colors.error),
              const SizedBox(width: HearthSpacing.sm),
              Expanded(child: Text(message, style: context.text.body)),
            ],
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: HearthSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
