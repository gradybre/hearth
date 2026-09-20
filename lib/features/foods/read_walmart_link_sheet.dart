import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/photo_picker.dart';
import '../../domain/shopping/walmart_link_reading.dart';
import 'walmart_link_controller.dart';

/// Reads a Walmart product link off one screenshot (D-WALMART-001, plan
/// P-HEARTH-WALMART-001).
///
/// Returns the found reading on success. Returns null if the user backed
/// out or chose to enter the link by hand instead — nothing is saved here,
/// the food editor reviews the result.
Future<WalmartLinkReading?> showReadWalmartLinkSheet(BuildContext context) =>
    showModalBottomSheet<WalmartLinkReading>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (BuildContext context) => const _ReadWalmartLinkSheet(),
    );

class _ReadWalmartLinkSheet extends ConsumerStatefulWidget {
  const _ReadWalmartLinkSheet();

  @override
  ConsumerState<_ReadWalmartLinkSheet> createState() =>
      _ReadWalmartLinkSheetState();
}

class _ReadWalmartLinkSheetState extends ConsumerState<_ReadWalmartLinkSheet> {
  WalmartLinkScanController? _notifier;
  bool _delivered = false;

  void _dismiss() {
    if (_delivered) return;
    _delivered = true;
    _notifier?.reset();
    Navigator.of(context).pop();
  }

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
    final WalmartLinkScanState state = ref.watch(walmartLinkScanProvider);
    _notifier = ref.read(walmartLinkScanProvider.notifier);

    // Handing the reading back is a navigation, so it waits for a frame
    // rather than happening inside build, and only ever fires once.
    if (state is WalmartLinkScanFound && !_delivered) {
      _delivered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop(state.reading);
        }
      });
    }

    final bool reading = state is WalmartLinkScanReading;
    final bool picking = state is WalmartLinkScanPicking;
    final bool showRetry = state is WalmartLinkScanFailed && state.canRetry;
    final bool showRead =
        state is WalmartLinkScanIdle || state is WalmartLinkScanPicking;
    final PickedPhoto? photo = state.photo;

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        // Bounded and scrollable so a preview, a banner and a keyboard do
        // not push the one button that gets you out of it off screen at
        // large text sizes (spec §6.3).
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Read Walmart link',
                          style: context.text.sectionHeader,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close link reader',
                        onPressed: _dismiss,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: HearthSpacing.xs),
                  Text(
                    'Choose a screenshot that shows the full Walmart '
                    'product link.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                  if (state is WalmartLinkScanMiss)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
                      child: _Banner(message: _missMessage(state.status)),
                    ),
                  if (state is WalmartLinkScanFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HearthSpacing.md),
                      child: _Banner(message: state.message),
                    ),
                  if (reading)
                    Semantics(
                      liveRegion: true,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: HearthSpacing.md,
                        ),
                        child: _ReadingRow(),
                      ),
                    )
                  else ...<Widget>[
                    if (photo != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: HearthSpacing.md,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(HearthRadius.sm),
                          child: Image.memory(
                            photo.bytes,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            // No filename or path — just what it is.
                            semanticLabel: 'Selected screenshot',
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              HearthRadius.sm,
                            ),
                          ),
                        ),
                        onPressed: picking ? null : () => _notifier?.pick(),
                        child: Text(
                          photo == null && state is! WalmartLinkScanMiss
                              ? 'Choose screenshot'
                              : 'Choose another screenshot',
                        ),
                      ),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                    if (showRetry)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: HearthSpacing.sm,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _notifier?.read(),
                            child: const Text('Try again'),
                          ),
                        ),
                      )
                    else if (showRead)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: HearthSpacing.sm,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: photo != null && !picking
                                ? () => _notifier?.read()
                                : null,
                            child: const Text('Read link'),
                          ),
                        ),
                      ),
                  ],
                  // A named way out, rather than only the gesture: typing
                  // the link in is a real answer, not a failure to scan.
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _dismiss,
                      child: const Text('Enter it manually instead'),
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _missMessage(WalmartLinkStatus status) => switch (status) {
    WalmartLinkStatus.ambiguous =>
      'More than one Walmart product link was found. Crop to the one '
          'you want, or paste it instead.',
    _ =>
      'No complete Walmart product link could be read. Choose a '
          'screenshot with the full link, or paste it instead.',
  };
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow();

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: HearthSpacing.sm),
      Expanded(
        child: Text(
          'Reading the link…',
          style: context.text.metadata.copyWith(
            color: context.colors.textMuted,
          ),
        ),
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // Never colour alone (§6.3), and announced as it appears.
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.error),
          const SizedBox(width: HearthSpacing.sm),
          Expanded(child: Text(message, style: context.text.body)),
        ],
      ),
    );
  }
}
