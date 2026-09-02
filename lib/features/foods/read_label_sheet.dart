import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/photo_picker.dart';
import 'label_scan_controller.dart';

/// Reads a nutrition label off a photo and hands back what it said
/// (spec §5.5).
///
/// One sheet shared by every entry point — the food editor, a barcode miss, a
/// flagged ingredient, the Foods list — because they all want the same thing
/// and none of them should be the place a retry is implemented for the fourth
/// time. Returns null when the user backed out or gave up.
///
/// Nothing is saved here. The reading goes back to whoever asked, and lands in
/// the food editor to be checked (CLAUDE.md rule 4): a misread panel looks
/// exactly as confident as a correct one.
Future<LabelReading?> showReadLabelSheet(BuildContext context) =>
    showModalBottomSheet<LabelReading>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // A photo picker takes over the screen; dismissing the sheet by
      // accident while it is open would lose the whole flow.
      isDismissible: true,
      builder: (BuildContext context) => const _ReadLabelSheet(),
    );

/// Whether this build can read labels at all.
///
/// The Claude key lives in an Edge Function, so an unconfigured build has no
/// way to. The buttons hide rather than fail on tap — offering a camera that
/// leads nowhere is worse than not offering one.
bool canReadLabels(WidgetRef ref) => ref.watch(labelReaderProvider) != null;

class _ReadLabelSheet extends ConsumerStatefulWidget {
  const _ReadLabelSheet();

  @override
  ConsumerState<_ReadLabelSheet> createState() => _ReadLabelSheetState();
}

class _ReadLabelSheetState extends ConsumerState<_ReadLabelSheet> {
  // Nothing to reset here: labelScanProvider is auto-disposed, so a sheet
  // opens on a controller that has never read anything. Resetting from
  // initState was a frame too late — the first build had already seen the
  // previous reading and scheduled a pop with it.

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final LabelScanState state = ref.watch(labelScanProvider);

    // Handing the reading back is a navigation, so it waits for a frame
    // rather than happening inside build.
    if (state is LabelScanDone) {
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
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Read the label', style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.xs),
              Text(
                'Photograph the Nutrition Facts panel and Hearth will fill in '
                'the serving sizes and macros for you to check.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: HearthSpacing.lg),
              switch (state) {
                LabelScanReading() => const _Reading(),
                LabelScanFailed(:final String message, :final bool canRetry) =>
                  _Failed(message: message, canRetry: canRetry),
                _ => const _Choices(),
              },
              const SizedBox(height: HearthSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choices extends ConsumerWidget {
  const _Choices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Desktop has no camera, and a camera button that opens a file dialog is
    // worse than not offering one.
    final bool camera = ref.watch(photoPickerProvider).canUseCamera;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (camera)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => ref
                  .read(labelScanProvider.notifier)
                  .readFrom(PhotoOrigin.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
          ),
        if (camera) const SizedBox(height: HearthSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: camera
              ? OutlinedButton.icon(
                  onPressed: () => ref
                      .read(labelScanProvider.notifier)
                      .readFrom(PhotoOrigin.library),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose a photo'),
                )
              : FilledButton.icon(
                  onPressed: () => ref
                      .read(labelScanProvider.notifier)
                      .readFrom(PhotoOrigin.library),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose a photo'),
                ),
        ),
      ],
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
        Text(
          'Reading the panel…',
          style: context.text.metadata.copyWith(
            color: context.colors.textMuted,
          ),
        ),
      ],
    ),
  );
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.message, required this.canRetry});

  final String message;
  final bool canRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;

    return Column(
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
        const SizedBox(height: HearthSpacing.md),
        Row(
          children: <Widget>[
            if (canRetry)
              // The photo is still here, so a retry does not mean taking it
              // again.
              FilledButton(
                onPressed: () => ref.read(labelScanProvider.notifier).read(),
                child: const Text('Try again'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => ref.read(labelScanProvider.notifier).reset(),
              child: const Text('Use another photo'),
            ),
          ],
        ),
      ],
    );
  }
}
