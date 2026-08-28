import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/local/collection_store.dart';

/// Puts one recipe into cookbooks (spec §5.2).
///
/// Creating a cookbook happens here rather than on a separate management
/// screen: the moment you want a new one is the moment you have a recipe that
/// does not fit the existing ones.
Future<void> showCollectionsSheet(
  BuildContext context, {
  required String recipeId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => _CollectionsSheet(recipeId: recipeId),
);

class _CollectionsSheet extends ConsumerStatefulWidget {
  const _CollectionsSheet({required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<_CollectionsSheet> createState() => _CollectionsSheetState();
}

class _CollectionsSheetState extends ConsumerState<_CollectionsSheet> {
  final TextEditingController _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final String name = _newName.text.trim();
    if (name.isEmpty) return;
    final String id = await ref
        .read(collectionRepositoryProvider)
        .createCollection(name);
    // A cookbook made from inside a recipe is made *for* that recipe — not
    // putting it in would mean naming it and then having to tap it anyway.
    await ref
        .read(collectionRepositoryProvider)
        .toggleMembership(collectionId: id, recipeId: widget.recipeId);
    _newName.clear();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final List<CollectionSummary> collections =
        ref.watch(collectionsProvider).value ?? const <CollectionSummary>[];
    final Set<String> member =
        (ref.watch(recipeCollectionsProvider).value ??
            const <String, Set<String>>{})[widget.recipeId] ??
        const <String>{};

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        child: SafeArea(
          child: Padding(
            // Lifts the sheet clear of the keyboard while naming a cookbook.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  child: Text('Cookbooks', style: context.text.sectionHeader),
                ),
                if (collections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HearthSpacing.lg,
                    ),
                    child: Text(
                      'No cookbooks yet. Name one below to start grouping '
                      'recipes.',
                      style: context.text.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: HearthSpacing.lg,
                      ),
                      children: <Widget>[
                        for (final CollectionSummary collection in collections)
                          _CollectionRow(
                            collection: collection,
                            selected: member.contains(collection.id),
                            onTap: () => ref
                                .read(collectionRepositoryProvider)
                                .toggleMembership(
                                  collectionId: collection.id,
                                  recipeId: widget.recipeId,
                                ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(HearthSpacing.lg),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _newName,
                          style: context.text.body,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _create(),
                          decoration: InputDecoration(
                            hintText: 'New cookbook',
                            hintStyle: context.text.body.copyWith(
                              color: colors.textMuted,
                            ),
                            filled: true,
                            fillColor: colors.surfaceSunken,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                HearthRadius.md,
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: HearthSpacing.sm),
                      FilledButton(
                        onPressed: _create,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HearthSpacing.lg,
                    0,
                    HearthSpacing.lg,
                    HearthSpacing.lg,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.collection,
    required this.selected,
    required this.onTap,
  });

  final CollectionSummary collection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        checked: selected,
        label: '${collection.name}, ${_count(collection.size)}',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.surfaceSunken : colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(
                  color: selected ? colors.outlineStrong : colors.outline,
                ),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: selected ? colors.accent : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Text(
                      collection.name,
                      style: context.text.ingredient,
                    ),
                  ),
                  Text(
                    _count(collection.size),
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _count(int size) => size == 1 ? '1 recipe' : '$size recipes';
}
