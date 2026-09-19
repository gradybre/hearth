import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/photo_picker.dart';
import 'label_scan_controller.dart';

/// Reads a nutrition label and/or a package size off up to two photos and
/// hands back what they said (spec §5.5, R11).
///
/// One sheet shared by every entry point. Returns null when the user backed
/// out or gave up.
///
/// Nothing is saved here. The reading goes back to whoever asked, and lands
/// in the food editor to be checked (CLAUDE.md rule 4).
Future<LabelReading?> showReadLabelSheet(BuildContext context) =>
    showModalBottomSheet<LabelReading>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (BuildContext context) => const _ReadLabelSheet(),
    );

/// Whether this build can read labels at all.
bool canReadLabels(WidgetRef ref) => ref.watch(labelReaderProvider) != null;

class _ReadLabelSheet extends ConsumerStatefulWidget {
  const _ReadLabelSheet();

  @override
  ConsumerState<_ReadLabelSheet> createState() => _ReadLabelSheetState();
}

class _ReadLabelSheetState extends ConsumerState<_ReadLabelSheet> {
  LabelScanController? _notifier;
  bool _delivered = false;

  @override
  void dispose() {
    // Closing the sheet leaves nothing behind for the next open to replay.
    try {
      _notifier?.reset();
    } on Object {
      // Already gone with the route; there is nothing left to clear.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final LabelScanState state = ref.watch(labelScanProvider);
    _notifier = ref.read(labelScanProvider.notifier);

    // Handing the reading back is a navigation, so it waits for a frame
    // rather than happening inside build.
    if (state is LabelScanDone && !_delivered) {
      _delivered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(state.reading);
      });
    }

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        // Bounded and scrollable: two slots, an error banner and a keyboard
        // do not fit a short phone at 200% text, and a sheet that overflows
        // hides the one button that gets you out of it (spec §6.3).
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Read the label', style: context.text.sectionHeader),
                  const SizedBox(height: HearthSpacing.xs),
                  Text(
                    'Photograph the Nutrition Facts panel, the package size, '
                    'or both, and Hearth will fill in what it can read for '
                    'you to check.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                  if (state is LabelScanReading) ...<Widget>[
                    const _Reading(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          ref.read(labelScanProvider.notifier).reset();
                          Navigator.of(context).pop();
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                  ] else ...<Widget>[
                    if (state is LabelScanFailed)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: HearthSpacing.md,
                        ),
                        child: _ErrorBanner(message: state.message),
                      ),
                    const _Slot(
                      slot: LabelSlot.nutrition,
                      title: 'Nutrition label (back)',
                    ),
                    const SizedBox(height: HearthSpacing.md),
                    const _Slot(
                      slot: LabelSlot.package,
                      title: 'Package size (front)',
                    ),
                    const SizedBox(height: HearthSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: state.hasAnyPhoto
                            ? () => ref.read(labelScanProvider.notifier).read()
                            : null,
                        child: const Text('Read photos'),
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    // A named way out, rather than only the gesture: typing
                    // it in is a real answer, not a failure to scan.
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () =>
                            Navigator.of(context)
                                .pop(const LabelReading(servings: [])),
                        child: const Text('Enter it manually instead'),
                      ),
                    ),
                  ],
                  const SizedBox(height: HearthSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slot extends ConsumerWidget {
  const _Slot({required this.slot, required this.title});

  final LabelSlot slot;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final bool camera = ref.watch(photoPickerProvider).canUseCamera;
    final LabelScanState state = ref.watch(labelScanProvider);
    final PickedPhoto? photo = slot == LabelSlot.nutrition
        ? state.backPhoto
        : state.frontPhoto;
    final LabelScanController notifier = ref.read(labelScanProvider.notifier);

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
            Text(title, style: context.text.label),
            const SizedBox(height: HearthSpacing.sm),
            if (photo == null)
              Wrap(
                spacing: HearthSpacing.sm,
                children: <Widget>[
                  if (camera)
                    TextButton.icon(
                      key: ValueKey<String>('$slot-camera'),
                      onPressed: () => notifier.pick(slot, PhotoOrigin.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Take a photo'),
                    ),
                  TextButton.icon(
                    key: ValueKey<String>('$slot-library'),
                    onPressed: () => notifier.pick(slot, PhotoOrigin.library),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Choose a photo'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(HearthRadius.sm),
                    child: Image.memory(
                      photo.bytes,
                      height: 112,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      semanticLabel: title,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  Row(
                    children: <Widget>[
                      Icon(Icons.check_circle, size: 18, color: colors.accent),
                      const SizedBox(width: HearthSpacing.sm),
                      Expanded(
                        child: Text(
                          'Photo selected',
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: HearthSpacing.sm,
                    children: <Widget>[
                      TextButton(
                        key: ValueKey<String>('$slot-replace'),
                        onPressed: () => notifier.pick(
                          slot,
                          camera ? PhotoOrigin.camera : PhotoOrigin.library,
                        ),
                        child: const Text('Replace'),
                      ),
                      TextButton.icon(
                        key: ValueKey<String>('$slot-remove'),
                        onPressed: () => notifier.remove(slot),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: HearthSpacing.md),
    child: Row(
      children: <Widget>[
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: HearthSpacing.sm),
        Expanded(
          child: Text(
            'Reading your photos…',
            style: context.text.metadata.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Never colour alone (§6.3).
        Icon(Icons.error_outline, size: 18, color: colors.error),
        const SizedBox(width: HearthSpacing.sm),
        Expanded(child: Text(message, style: context.text.body)),
      ],
    );
  }
}
