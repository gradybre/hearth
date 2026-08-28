import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/local/recipe_photo_store.dart';

/// A recipe's hero photo, wherever it is shown (spec §5.2).
///
/// Renders nothing at all when there is no photo. A grey placeholder box on
/// every recipe would make an unphotographed library look broken rather than
/// simply unphotographed.
class RecipePhoto extends ConsumerWidget {
  const RecipePhoto({
    required this.recipeId,
    required this.width,
    required this.height,
    this.borderRadius,
    super.key,
  });

  final String recipeId;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? fileName =
        (ref.watch(recipePhotoNamesProvider).value ??
        const <String, String>{})[recipeId];
    final Directory? dir = ref.watch(recipePhotoDirectoryProvider).value;
    if (fileName == null || dir == null) return const SizedBox.shrink();

    final File file = File('${dir.path}/$fileName');
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(HearthRadius.lg),
      child: Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // The row can outlive its file — a reinstall moves the container, and
        // the database comes back before the images do. Say nothing rather
        // than throw a red box into the middle of a recipe.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            const SizedBox.shrink(),
      ),
    );
  }
}

/// Whether a recipe has a photo, for callers deciding on layout.
bool hasRecipePhoto(WidgetRef ref, String recipeId) =>
    (ref.watch(recipePhotoNamesProvider).value ?? const <String, String>{})
        .containsKey(recipeId);

/// The editor's photo control: add one, replace it, or take it away.
class RecipePhotoField extends ConsumerStatefulWidget {
  const RecipePhotoField({required this.recipeId, super.key});

  /// Null until the recipe has been saved once — a photo needs something to
  /// belong to.
  final String? recipeId;

  @override
  ConsumerState<RecipePhotoField> createState() => _RecipePhotoFieldState();
}

class _RecipePhotoFieldState extends ConsumerState<RecipePhotoField> {
  bool _busy = false;

  Future<void> _choose(PhotoOrigin origin) async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null || _busy) return;

    setState(() => _busy = true);
    try {
      final PickedPhoto? picked = await ref
          .read(photoPickerProvider)
          .pick(origin);
      if (picked == null) return;

      await ref
          .read(recipePhotoStoreProvider)
          .save(
            recipeId: recipeId,
            bytes: picked.bytes,
            extension: picked.extension,
            now: DateTime.now(),
          );
    } on PhotoTooLarge {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That photo is too large. Try a smaller one.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null) return;
    await ref.read(recipePhotoStoreProvider).remove(recipeId);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String? recipeId = widget.recipeId;

    if (recipeId == null) {
      return Text(
        'Save the recipe to add a photo.',
        style: context.text.metadata.copyWith(color: colors.textMuted),
      );
    }

    final bool hasPhoto = hasRecipePhoto(ref, recipeId);
    final bool canUseCamera = ref.read(photoPickerProvider).canUseCamera;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasPhoto) ...<Widget>[
          RecipePhoto(recipeId: recipeId, width: double.infinity, height: 200),
          const SizedBox(height: HearthSpacing.sm),
        ],
        Wrap(
          spacing: HearthSpacing.sm,
          runSpacing: HearthSpacing.sm,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _choose(PhotoOrigin.library),
              icon: const Icon(Icons.photo_outlined, size: 18),
              label: Text(hasPhoto ? 'Replace photo' : 'Add a photo'),
            ),
            if (canUseCamera)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _choose(PhotoOrigin.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take a photo'),
              ),
            if (hasPhoto)
              TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }
}
