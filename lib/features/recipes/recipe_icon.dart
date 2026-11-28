import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/hearth_sketch.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/sketch_icon.dart';
import 'recipe_icon_controller.dart';

/// A recipe's little hand-drawn sketch, wherever it is shown (spec §5.2).
///
/// Renders nothing at all when there is no icon, or when the markup does not
/// survive [SketchIcon.parse]. A placeholder box on every recipe would make an
/// undrawn library look broken rather than simply undrawn — the same choice
/// [RecipePhoto] makes.
///
/// Decorative, and marked as such. The recipe's name is what carries the
/// meaning; a screen reader announcing "sketch of a bowl" in front of
/// "Chicken noodle soup" would be reading the decoration twice and the recipe
/// once (spec §6.3).
///
/// The drawing takes its colour here rather than from the markup. §6.1 gives
/// the app one warm neutral and one accent and ships light and dark from day
/// one; an icon with baked-in colours would be wrong in one of them, so every
/// colour the model wrote is discarded and this supplies one.
class RecipeIcon extends StatelessWidget {
  const RecipeIcon({
    required this.svg,
    required this.size,
    this.color,
    super.key,
  });

  /// The stored markup, or null for a recipe that has no icon.
  final String? svg;

  final double size;

  /// Defaults to the body text colour: a sketch beside a title is structure,
  /// not an action, and the single accent belongs to things you can press.
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      HearthSketch(svg: svg, size: size, color: color);

  /// Whether [svg] is something this would actually draw.
  ///
  /// For callers deciding on layout before they build — a library row leaves
  /// no gap where an icon was never going to appear.
  ///
  /// The parse is memoised in [SketchIcon.cached] rather than here, because
  /// this is not the only layer that reads the same document: the pull
  /// validates every row it takes in, and a library row rebuilds on every
  /// scroll frame besides. One cache down in the domain means finding out
  /// whether an icon is drawable costs once per distinct icon, not once per
  /// layer per frame.
  static bool canDraw(String? svg) => SketchIcon.cached(svg) != null;
}

/// The editor's icon control: see the sketch, redraw it, or be rid of it
/// (spec §5.2).
///
/// This control is the reason writing an icon without a review screen is
/// defensible at all (see [RecipeIconController]). The rule behind rule 4 is
/// that the user stays in charge of what lands in their library; for a
/// decorative, reversible drawing, staying in charge means being able to
/// throw it away and ask for another — which is exactly this.
class RecipeIconField extends ConsumerStatefulWidget {
  const RecipeIconField({
    required this.recipeId,
    required this.svg,
    required this.onCleared,
    super.key,
  });

  /// Null until the recipe has been saved once — an icon needs something to
  /// belong to, the same way a photo does.
  final String? recipeId;

  final String? svg;

  /// Told when the icon goes, so the form stops carrying it into the next
  /// save. Without this the editor's own draft would put it straight back.
  final VoidCallback onCleared;

  @override
  ConsumerState<RecipeIconField> createState() => _RecipeIconFieldState();
}

class _RecipeIconFieldState extends ConsumerState<RecipeIconField> {
  bool _drawing = false;

  /// Why the last drawing the *user asked for* did not arrive, if it did not.
  ///
  /// The background draw after a save is deliberately silent: the recipe is
  /// already safe and nobody asked for a picture. This is the other case —
  /// somebody pressed a button and is waiting — and it used to be just as
  /// silent, so a spent picture budget, a missing network and markup that
  /// failed validation all looked identical to a button that un-disabled
  /// itself and did nothing.
  String? _failure;

  static const String _failureMessage =
      'Hearth could not draw one just now. Try again in a moment.';

  Future<void> _redraw() async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null || _drawing) return;

    setState(() {
      _drawing = true;
      _failure = null;
    });
    bool drawn = false;
    try {
      drawn = await ref
          .read(recipeIconControllerProvider)
          .drawFor(recipeId: recipeId, title: _title());
    } finally {
      if (mounted) {
        setState(() {
          _drawing = false;
          _failure = drawn ? null : _failureMessage;
        });
        // An explicit request refreshes what it changed rather than waiting on
        // the library stream to notice, so the new sketch appears under the
        // button that asked for it.
        if (drawn) ref.invalidate(recipeByIdProvider(recipeId));
      }
    }
  }

  /// The title as saved, which is what the icon is drawn from.
  ///
  /// Read back from the store rather than from the form: an unsaved rename is
  /// not what the recipe is called yet, and drawing from it would leave an
  /// icon that matches nothing anybody can see. Empty when the store has not
  /// answered yet, and the draw then fails and says so rather than returning
  /// quietly for a reason nobody could guess at.
  String _title() =>
      ref.read(recipeByIdProvider(widget.recipeId!)).value?.title ?? '';

  Future<void> _remove() async {
    final String? recipeId = widget.recipeId;
    if (recipeId == null) return;
    await ref.read(recipeIconControllerProvider).clear(recipeId);
    if (mounted) setState(() => _failure = null);
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String? recipeId = widget.recipeId;
    if (recipeId == null ||
        !ref.watch(recipeIconControllerProvider).isAvailable) {
      return const SizedBox.shrink();
    }

    // The stored icon, not the one the form opened with: a background drawing
    // that landed while the editor was open should show. The store wins as
    // soon as it has answered at all, rather than only when it answers with
    // an icon — falling back on a null would show the partner's removal as a
    // sketch that is no longer there. Until it answers, the form's own value
    // is the best guess going.
    final AsyncValue<Recipe?> stored = ref.watch(recipeByIdProvider(recipeId));
    final String? svg = stored.hasValue ? stored.value?.iconSvg : widget.svg;
    final bool hasIcon = RecipeIcon.canDraw(svg);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasIcon) ...<Widget>[
          RecipeIcon(svg: svg, size: 48),
          const SizedBox(width: HearthSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                hasIcon
                    ? 'Hearth sketched this from the title.'
                    : 'Hearth sketches a little icon from the title when you '
                          'save.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: HearthSpacing.sm),
              Wrap(
                spacing: HearthSpacing.sm,
                runSpacing: HearthSpacing.sm,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _drawing ? null : _redraw,
                    icon: const Icon(Icons.gesture, size: 18),
                    label: Text(hasIcon ? 'Draw another' : 'Draw one now'),
                  ),
                  if (hasIcon)
                    TextButton.icon(
                      onPressed: _drawing ? null : _remove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove icon'),
                    ),
                ],
              ),
              // Icon as well as words, never colour alone (spec §6.3).
              if (_failure case final String failure) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 18, color: colors.error),
                    const SizedBox(width: HearthSpacing.sm),
                    Expanded(
                      child: Text(
                        failure,
                        style: context.text.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
