import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../domain/models/food.dart';
import 'barcode_lookup_controller.dart';
import 'food_draft.dart';

/// Scanning a barcode to add or log a food (spec §5.5).
///
/// The camera is one way in, not the only one. Typing the number is always
/// available — a torn label, a device with no camera, a simulator — and the
/// rest of the flow does not care which was used. That is also what makes the
/// whole path testable without hardware.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  final TextEditingController _typed = TextEditingController();
  MobileScannerController? _camera;
  bool _typing = false;

  /// The last code handed to the lookup, so a camera pointed steadily at one
  /// label does not fire the same lookup dozens of times a second.
  String? _lastDetected;

  /// Read once, in initState: whether a camera exists cannot change while the
  /// screen is open, and rebuilding the controller on a rebuild would restart
  /// the camera mid-scan.
  late final bool _cameraIsPossible = ref.read(cameraScanningAvailableProvider);

  @override
  void initState() {
    super.initState();
    if (_cameraIsPossible) {
      _camera = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        // Retail product symbologies only: a QR code on a menu is not food,
        // and narrowing what the detector accepts makes it settle faster on a
        // shelf full of labels.
        formats: const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
      );
    } else {
      _typing = true;
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    _camera?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final Barcode barcode in capture.barcodes) {
      final String? value = barcode.rawValue;
      if (value == null || value == _lastDetected) continue;
      _lastDetected = value;
      HapticFeedback.mediumImpact();
      ref.read(barcodeLookupProvider.notifier).lookUp(value);
      return;
    }
  }

  void _submitTyped() {
    final String value = _typed.text.trim();
    if (value.isEmpty) return;
    _lastDetected = value;
    ref.read(barcodeLookupProvider.notifier).lookUp(value);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final BarcodeLookupState state = ref.watch(barcodeLookupProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Scan a barcode', style: context.text.label),
        actions: <Widget>[
          if (_cameraIsPossible)
            IconButton(
              icon: Icon(
                _typing ? Icons.photo_camera_outlined : Icons.keyboard,
              ),
              tooltip: _typing ? 'Use the camera' : 'Type the number',
              onPressed: () => setState(() => _typing = !_typing),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _typing || _camera == null
                  ? _TypeItIn(
                      controller: _typed,
                      onSubmit: _submitTyped,
                      cameraAvailable: _cameraIsPossible,
                    )
                  : MobileScanner(
                      controller: _camera!,
                      onDetect: _onDetect,
                      errorBuilder:
                          (
                            BuildContext context,
                            MobileScannerException error,
                          ) => _CameraUnavailable(
                            onTypeInstead: () => setState(() => _typing = true),
                          ),
                    ),
            ),
            _ResultPanel(
              state: state,
              onRetry: () => ref.read(barcodeLookupProvider.notifier).retry(),
              onClear: () {
                _lastDetected = null;
                _typed.clear();
                ref.read(barcodeLookupProvider.notifier).reset();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The always-available way in.
class _TypeItIn extends StatelessWidget {
  const _TypeItIn({
    required this.controller,
    required this.onSubmit,
    required this.cameraAvailable,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool cameraAvailable;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Type the number', style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                cameraAvailable
                    ? 'For a torn label, or when the camera will not settle.'
                    : 'This device has no camera to scan with.',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: HearthSpacing.lg),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                onSubmitted: (_) => onSubmit(),
                style: context.text.body,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  hintText: '5000157024671',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(HearthRadius.md),
                    borderSide: BorderSide(color: colors.outline),
                  ),
                ),
              ),
              const SizedBox(height: HearthSpacing.md),
              SizedBox(
                height: HearthTouch.minTarget,
                child: FilledButton(
                  onPressed: onSubmit,
                  child: const Text('Look it up'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.onTypeInstead});

  final VoidCallback onTypeInstead;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.no_photography_outlined, color: colors.textMuted),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'The camera is not available.',
              style: context.text.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Hearth needs camera access to scan. You can type the number '
              'instead.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.md),
            FilledButton(
              onPressed: onTypeInstead,
              child: const Text('Type the number'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the lookup found, and what to do about it.
///
/// Every outcome is a sentence, not a spinner that stops: found, found but
/// worth checking, nobody has it, or that is not a product code. §5.5 treats
/// the miss as a first-class path, so it gets a button rather than an apology.
class _ResultPanel extends ConsumerWidget {
  const _ResultPanel({
    required this.state,
    required this.onRetry,
    required this.onClear,
  });

  final BarcodeLookupState state;
  final VoidCallback onRetry;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state is BarcodeIdle) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: switch (state) {
          BarcodeIdle() => const SizedBox.shrink(),
          BarcodeSearching(:final String barcode) => _Searching(
            barcode: barcode,
          ),
          BarcodeNotAProduct(:final String barcode) => _Message(
            icon: Icons.help_outline,
            title: 'That is not a product barcode',
            detail:
                '"$barcode" is not a shape any retail barcode takes. Try '
                'again, or type the number under the lines.',
            actionLabel: 'Try again',
            onAction: onClear,
          ),
          BarcodeMissing(:final String barcode) => _Message(
            icon: Icons.add_circle_outline,
            title: 'Nobody has heard of this one',
            detail:
                'Add it yourself and Hearth will remember it — every future '
                'scan of $barcode finds it first.',
            actionLabel: 'Add it by hand',
            onAction: () => _addByHand(context, barcode),
            secondaryLabel: 'Try again',
            onSecondary: onRetry,
          ),
          BarcodeFound(:final NutritionMatch match) => _Found(
            match: match,
            onDiscard: onClear,
            onReviewed: onClear,
          ),
        },
      ),
    );
  }

  Future<void> _addByHand(BuildContext context, String barcode) async {
    // Straight into the food editor with the barcode already attached, so the
    // food that comes out of a miss is found by the next scan (spec §5.5).
    await context.push<void>('/food/new', extra: FoodDraft.forBarcode(barcode));
    onClear();
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.barcode});

  final String barcode;

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
          child: Text('Looking up $barcode…', style: context.text.body),
        ),
      ),
    ],
  );
}

/// A hit, with where it came from and whether to trust it.
class _Found extends StatelessWidget {
  const _Found({
    required this.match,
    required this.onDiscard,
    required this.onReviewed,
  });

  final NutritionMatch match;
  final VoidCallback onDiscard;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ServingOption first = match.food.servingOptions.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(match.food.name, style: context.text.sectionHeader),
                  if (match.food.brand != null)
                    Text(
                      match.food.brand!,
                      style: context.text.metadata.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            _SourceBadge(source: match.source, fromLibrary: match.fromLibrary),
          ],
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          '${first.label} · ${first.macros.kcal.round()} kcal · '
          '${first.macros.proteinG.round()} g protein',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (match.isLowConfidence) ...<Widget>[
          const SizedBox(height: HearthSpacing.md),
          // Flagged, never silently accepted: a wrong macro corrupts a day's
          // numbers invisibly (spec §5.3).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.warning_amber_outlined, size: 18, color: colors.error),
              const SizedBox(width: HearthSpacing.sm),
              Expanded(
                child: Text(
                  'This entry looks incomplete. Check the numbers before you '
                  'save it.',
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (match.fromLibrary) ...<Widget>[
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'Already in your library',
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: HearthSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: HearthTouch.minTarget,
                child: match.fromLibrary
                    // Saving again would duplicate a food the household may
                    // already have corrected, and "user overrides win" is the
                    // reason the library is asked first at all (§5.5).
                    ? FilledButton(
                        onPressed: () => _open(context),
                        child: const Text('Open it'),
                      )
                    : FilledButton(
                        onPressed: () => _review(context),
                        child: const Text('Review and save'),
                      ),
              ),
            ),
            const SizedBox(width: HearthSpacing.sm),
            TextButton(
              onPressed: onDiscard,
              child: Text(match.fromLibrary ? 'Done' : 'Discard'),
            ),
          ],
        ),
      ],
    );
  }

  /// Nothing reaches the library without a look first (CLAUDE.md rule 4).
  ///
  /// The editor is the review screen rather than a second, read-only one: a
  /// packet's own numbers are sometimes wrong, and the place you notice that
  /// should be the place you can fix it.
  Future<void> _open(BuildContext context) async {
    await context.push<void>('/food/${match.food.id}');
    onReviewed();
  }

  Future<void> _review(BuildContext context) async {
    await context.push<void>(
      '/food/new',
      extra: FoodDraft.fromLookup(match.food),
    );
    onReviewed();
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source, required this.fromLibrary});

  final FoodSource source;
  final bool fromLibrary;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // Who answered comes first. A food saved from Open Food Facts keeps that
    // provenance for life, so showing it alone would tell the user the packet
    // was just fetched when in fact it was already theirs.
    final String label = fromLibrary
        ? 'Your library'
        : switch (source) {
            FoodSource.openFoodFacts => 'Open Food Facts',
            FoodSource.usda => 'USDA',
            FoodSource.manual => 'Your library',
            FoodSource.aiEstimate => 'AI estimate',
          };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.sm),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HearthSpacing.sm,
          vertical: HearthSpacing.xxs,
        ),
        child: Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 18, color: colors.textSecondary),
            const SizedBox(width: HearthSpacing.sm),
            Expanded(child: Text(title, style: context.text.sectionHeader)),
          ],
        ),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          detail,
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: HearthSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: HearthTouch.minTarget,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
            ),
            if (secondaryLabel != null) ...<Widget>[
              const SizedBox(width: HearthSpacing.sm),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ],
    );
  }
}
