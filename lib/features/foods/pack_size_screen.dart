import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../data/adapters/photo_picker.dart';
import '../../domain/foods/pack_size_queue.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import 'pack_fill_controller.dart';
import 'read_label_sheet.dart' show canReadLabels;

/// Filling in the pack sizes the library never had (spec §5.7).
///
/// The shopping list counts jars rather than weighing them — "3 × 24 oz", not
/// "4 lb" — because a weight tells you nothing at a shelf. It can only do that
/// for a food that says how big one pack is, and a library that predates the
/// feature has none: every line falls back to a weight and the feature is
/// invisible.
///
/// Three ways in, because no one of them covers the library. A barcode can be
/// asked of the nutrition chain, and most packaged foods have one. A packet
/// in your hand can be photographed. Everything else is typed, and the hard
/// part of typing was never the typing — it was finding which foods needed it.
///
/// **Nothing here writes.** Both automatic paths produce proposals; the save
/// button at the bottom is the only thing that touches a food, and it says how
/// many it is about to change (CLAUDE.md rule 4). A wrong pack size does not
/// fail loudly — it silently buys the wrong amount — so absent beats guessed
/// at every step, and a row with nothing found stays as it was.
class PackSizeScreen extends ConsumerWidget {
  const PackSizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Pack sizes', style: context.text.label),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: ref
              .watch(packSizeQueueProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace s) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(gutter),
                    child: Text(
                      'The library could not be read.\n$e',
                      style: context.text.body,
                    ),
                  ),
                ),
                data: (PackSizeQueue queue) => queue.isEmpty
                    ? _NothingToFill(gutter: gutter)
                    : _Queue(queue: queue, gutter: gutter),
              ),
        ),
      ),
    );
  }
}

class _NothingToFill extends StatelessWidget {
  const _NothingToFill({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return CentredMessage(
      gutter: gutter,
      children: <Widget>[
        Icon(Icons.inventory_2_outlined, size: 40, color: colors.textMuted),
        const SizedBox(height: HearthSpacing.md),
        Text(
          'Every food has a pack size',
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'Your shopping list can count packs for all of them.',
          style: context.text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// One row of the list: a heading, a food, or the block at the top.
///
/// The list is built from a flat array of these rather than from nested
/// `Column`s inside a `ListView`, so it stays lazy. A real library is several
/// hundred foods, and a list that builds all of them to show ten is a list
/// that stutters on the phone it was written for.
sealed class _Item {
  const _Item();
}

class _Intro extends _Item {
  const _Intro();
}

class _Heading extends _Item {
  const _Heading(this.need);
  final PackNeed need;
}

class _Row extends _Item {
  const _Row(this.gap);
  final PackSizeGap gap;
}

class _Queue extends ConsumerWidget {
  const _Queue({required this.queue, required this.gutter});

  final PackSizeQueue queue;
  final double gutter;

  List<_Item> _items() {
    final List<_Item> items = <_Item>[const _Intro()];
    PackNeed? section;
    for (final PackSizeGap gap in queue.gaps) {
      if (gap.need != section) {
        section = gap.need;
        items.add(_Heading(section));
      }
      items.add(_Row(gap));
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<_Item> items = _items();
    final int selected = ref.watch(
      packFillProvider.select((PackFillState s) => s.selectedCount),
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              gutter,
              HearthSpacing.lg,
              gutter,
              HearthSpacing.xxl,
            ),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) =>
                switch (items[index]) {
                  _Intro() => _IntroBlock(queue: queue),
                  _Heading(:final PackNeed need) => Padding(
                    padding: const EdgeInsets.only(
                      top: HearthSpacing.lg,
                      bottom: HearthSpacing.sm,
                    ),
                    child: Text(
                      need.heading,
                      style: context.text.sectionHeader,
                    ),
                  ),
                  _Row(:final PackSizeGap gap) => Padding(
                    padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                    child: _FoodRow(gap: gap),
                  ),
                },
          ),
        ),
        if (selected > 0) _SaveBar(selected: selected, gutter: gutter),
      ],
    );
  }
}

/// What this screen is for, and the one button that acts on all of it.
class _IntroBlock extends ConsumerWidget {
  const _IntroBlock({required this.queue});

  final PackSizeQueue queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final PackSweep? sweep = ref.watch(
      packFillProvider.select((PackFillState s) => s.sweep),
    );
    final int lookupable = queue.lookupable.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          queue.length == 1
              ? '1 food has no pack size'
              : '${queue.length} foods have no pack size',
          style: context.text.body,
        ),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          'A shopping list counts packs instead of weighing them — 3 × 24 oz '
          'rather than 4 lb — for every food that says how big one is.',
          style: context.text.metadata.copyWith(color: colors.textMuted),
        ),
        if (lookupable > 0) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          if (sweep != null && sweep.isRunning)
            // Words, not a bare bar: a progress bar alone says something is
            // happening and never how much is left (§6.3).
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: HearthSpacing.sm),
                Expanded(
                  child: Text(
                    'Checked ${sweep.done} of ${sweep.total}…',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => ref
                    .read(packFillProvider.notifier)
                    .lookUpAll(queue.lookupable),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: Text(
                  lookupable == 1
                      ? 'Look up 1 barcode'
                      : 'Look up $lookupable barcodes',
                ),
              ),
            ),
          const SizedBox(height: HearthSpacing.xs),
          Text(
            'Nothing is saved until you check what came back.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// One food: what is known about its pack, and the ways to find out.
class _FoodRow extends ConsumerWidget {
  const _FoodRow({required this.gap});

  final PackSizeGap gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final Food food = gap.food;
    final PackFillState state = ref.watch(packFillProvider);
    final PackProposal? proposal = state.proposals[food.id];
    final String? miss = state.misses[food.id];
    final bool busy = state.busy.contains(food.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(food.name, style: context.text.body),
            if (food.brand case final String brand)
              Text(
                brand,
                style: context.text.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            if (gap.need == PackNeed.inARecipe && gap.recipeCount > 0)
              Text(
                gap.recipeCount == 1
                    ? 'In 1 recipe'
                    : 'In ${gap.recipeCount} recipes',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            if (busy) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              _Note(
                icon: Icons.hourglass_empty,
                text: 'Asking…',
                colour: colors.textMuted,
              ),
            ] else if (proposal != null) ...<Widget>[
              const SizedBox(height: HearthSpacing.sm),
              _ProposalBlock(proposal: proposal),
            ] else ...<Widget>[
              if (miss != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                _Note(
                  icon: Icons.info_outline,
                  text: miss,
                  colour: colors.textMuted,
                ),
              ],
              const SizedBox(height: HearthSpacing.sm),
              _Ways(gap: gap),
            ],
          ],
        ),
      ),
    );
  }
}

/// A found pack size, and the tick that would save it.
class _ProposalBlock extends ConsumerWidget {
  const _ProposalBlock({required this.proposal});

  final PackProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final String size = QuantityFormat.formatAsAuthored(proposal.size);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Merged, so a screen reader reads "Use 24 oz, from Open Food Facts,
        // checkbox, checked" as one thing rather than as a control with no
        // label beside a sentence with no control.
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: proposal.selected,
                onChanged: (bool? _) => ref
                    .read(packFillProvider.notifier)
                    .toggle(proposal.food.id),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: HearthSpacing.md),
                  child: Text(
                    'Use $size, from ${proposal.from}',
                    style: context.text.body,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (proposal.isFlagged)
          // Never colour alone: the warning carries an icon and the reader's
          // own words (§6.3). It also arrives unticked, so the flag is a state
          // of the row rather than only a decoration on it.
          _Note(
            icon: Icons.warning_amber_outlined,
            text: proposal.uncertain.first.note,
            colour: colors.error,
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () =>
                ref.read(packFillProvider.notifier).discard(proposal.food.id),
            child: Semantics(
              label: 'Discard the pack size found for ${proposal.food.name}',
              excludeSemantics: true,
              child: const Text('Discard'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The three ways in, for one food.
///
/// A [Wrap] rather than a Row: three labelled buttons are wider than a small
/// phone at three times the text, and honouring dynamic type means the layout
/// gives way rather than the words (§6.3).
class _Ways extends ConsumerWidget {
  const _Ways({required this.gap});

  final PackSizeGap gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Food food = gap.food;
    final bool canPhotograph = canReadLabels(ref);
    final bool camera = ref.watch(photoPickerProvider).canUseCamera;

    return Wrap(
      spacing: HearthSpacing.sm,
      children: <Widget>[
        if (gap.canBeLookedUp)
          TextButton.icon(
            onPressed: () => ref.read(packFillProvider.notifier).lookUpOne(gap),
            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
            label: Semantics(
              label: 'Look up the pack size for ${food.name}',
              excludeSemantics: true,
              child: const Text('Look it up'),
            ),
          ),
        // Hidden rather than disabled when this build has no reader: offering
        // a camera that leads nowhere is worse than not offering one.
        if (canPhotograph)
          TextButton.icon(
            onPressed: () => ref
                .read(packFillProvider.notifier)
                .photograph(
                  food,
                  camera ? PhotoOrigin.camera : PhotoOrigin.library,
                ),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Semantics(
              label: 'Photograph the package of ${food.name}',
              excludeSemantics: true,
              child: Text(camera ? 'Photograph it' : 'Choose a photo'),
            ),
          ),
        TextButton.icon(
          onPressed: () => context.push('/food/${food.id}'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Semantics(
            label: 'Type the pack size for ${food.name}',
            excludeSemantics: true,
            child: const Text('Type it in'),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.colour});

  final IconData icon;
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 16, color: colour),
      const SizedBox(width: HearthSpacing.xs),
      Expanded(
        child: Text(text, style: context.text.metadata.copyWith(color: colour)),
      ),
    ],
  );
}

/// The only thing on this screen that writes.
class _SaveBar extends ConsumerStatefulWidget {
  const _SaveBar({required this.selected, required this.gutter});

  final int selected;
  final double gutter;

  @override
  ConsumerState<_SaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends ConsumerState<_SaveBar> {
  bool _saving = false;

  Future<void> _save() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final int saved = await ref.read(packFillProvider.notifier).saveSelected();
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved == 1 ? '1 pack size saved' : '$saved pack sizes saved',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.gutter,
          HearthSpacing.md,
          widget.gutter,
          HearthSpacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              widget.selected == 1
                  ? 'Save 1 pack size'
                  : 'Save ${widget.selected} pack sizes',
            ),
          ),
        ),
      ),
    );
  }
}
