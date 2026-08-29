import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/models/food_profile.dart';
import 'ai_recipe_mapper.dart';
import 'recipe_chat_controller.dart';
import 'recipe_import_controller.dart';

/// Writing a recipe by talking about it (spec §5.4).
///
/// Private to you — the conversation is never a household surface, even though
/// the recipe becomes shared the moment it is saved. Saving goes through the
/// same editor as everything else, so a generated recipe is read before it
/// lands and its macros come from real data rather than the model's.
class RecipeChatScreen extends ConsumerStatefulWidget {
  const RecipeChatScreen({super.key});

  @override
  ConsumerState<RecipeChatScreen> createState() => _RecipeChatScreenState();
}

class _RecipeChatScreenState extends ConsumerState<RecipeChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() {});
    await ref.read(recipeChatProvider.notifier).send(text);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Into the editor, which is where a recipe is read before it is saved.
  Future<void> _save(AiRecipe recipe) async {
    await context.push<void>(
      '/recipe/new',
      extra: RecipeImportResult(
        draft: AiRecipeMapper.toDraft(recipe),
        uncertain: recipe.uncertain,
        estimates: recipe.estimates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final RecipeChatState state = ref.watch(recipeChatProvider);
    final RecipeChatController controller = ref.read(
      recipeChatProvider.notifier,
    );
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    final bool busy = state is RecipeChatThinking;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Write me a recipe', style: context.text.sectionHeader),
        actions: <Widget>[
          if (state.messages.isNotEmpty)
            TextButton(
              onPressed: busy ? null : controller.reset,
              child: const Text('Start over'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: state.messages.isEmpty
                  ? _Opening(gutter: gutter)
                  : ListView(
                      controller: _scroll,
                      padding: EdgeInsets.all(gutter),
                      children: <Widget>[
                        for (final ChatMessage message in state.messages)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: HearthSpacing.md,
                            ),
                            child: _Bubble(
                              message: message,
                              onSave: message.recipe == null
                                  ? null
                                  : () => _save(message.recipe!),
                            ),
                          ),
                        if (busy) const _Thinking(),
                        if (state is RecipeChatFailed)
                          _Failed(
                            message: state.message,
                            onRetry: state.canRetry ? controller.retry : null,
                          ),
                      ],
                    ),
            ),
            _Composer(
              controller: _input,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// What to say first, and what Hearth already knows.
class _Opening extends ConsumerWidget {
  const _Opening({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final FoodProfile profile =
        ref.watch(foodProfileProvider).value ?? FoodProfile.empty('');

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(gutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Describe what you want', style: context.text.recipeTitle),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                '"A high-protein weeknight pasta for two." Then change your '
                'mind as often as you like — make it spicier, swap the '
                'chicken, cut the carbs.',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: HearthSpacing.xl),
              // Says what is already known so it does not get restated, and
              // so nobody has to wonder whether an allergy was remembered.
              if (profile.isEmpty)
                const _Note(
                  icon: Icons.person_outline,
                  text:
                      'Your food profile is empty. Fill it in and Hearth '
                      'will keep to your allergies and dislikes without being '
                      'asked.',
                )
              else ...<Widget>[
                if (profile.allergies.isNotEmpty)
                  _Note(
                    icon: Icons.block,
                    text: 'Never uses ${profile.allergies.join(', ')}.',
                  ),
                if (profile.dislikes.isNotEmpty)
                  _Note(
                    icon: Icons.thumb_down_outlined,
                    text: 'Avoids ${profile.dislikes.join(', ')}.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: context.colors.textMuted),
        const SizedBox(width: HearthSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.metadata.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onSave});

  final ChatMessage message;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AiRecipe? recipe = message.recipe;

    return Align(
      alignment: message.fromUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: message.fromUser ? colors.surfaceSunken : colors.surface,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            border: Border.all(color: colors.outline),
          ),
          padding: const EdgeInsets.all(HearthSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message.text, style: context.text.body),
              if (recipe != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                Text(recipe.title, style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.xxs),
                Text(
                  _summarise(recipe),
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
                SizedBox(
                  height: HearthTouch.minTarget,
                  child: FilledButton(
                    onPressed: onSave,
                    child: const Text('Read it and save'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _summarise(AiRecipe recipe) {
    final int lines = recipe.sections.fold(
      0,
      (int total, AiSection section) =>
          total +
          section.ingredientsText
              .split('\n')
              .where((String l) => l.trim().isNotEmpty)
              .length,
    );
    return <String>[
      if (recipe.servings != null) 'serves ${recipe.servings!.round()}',
      '$lines ingredients',
      // "in the oven" was wrong the first time it was seen: a stir-fry is not
      // baked, and the model does not say which it is.
      if (recipe.cookMinutes != null) '${recipe.cookMinutes} min cooking',
    ].join(' · ');
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.md),
    child: Row(
      children: <Widget>[
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: HearthSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            'Writing…',
            style: context.text.metadata.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A failure that left the conversation exactly where it was (spec §5.4).
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool canSend = enabled && controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      padding: const EdgeInsets.all(HearthSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onChanged,
              onSubmitted: (_) => canSend ? onSend() : null,
              style: context.text.body,
              decoration: const InputDecoration(
                hintText: 'What would you like?',
                isDense: false,
              ),
            ),
          ),
          const SizedBox(width: HearthSpacing.sm),
          Semantics(
            button: true,
            label: 'Send',
            onTap: canSend ? onSend : null,
            excludeSemantics: true,
            child: IconButton.filled(
              icon: const Icon(Icons.arrow_upward),
              onPressed: canSend ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
