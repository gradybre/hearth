import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../domain/models/food.dart';
import 'barcode_lookup_controller.dart';
import 'food_draft.dart';
import 'read_label_sheet.dart';

/// Scanning a barcode to add or log a food (spec §5.5).
///
/// The camera is one way in, not the only one. Typing the number is always
/// available — a torn label, a device with no camera, a simulator — and the
/// rest of the flow does not care which was used. That is also what makes the
/// whole path testable without hardware.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({this.pickFood = false, super.key});

  /// Whether the screen was opened to *choose* a food rather than to file one.
  ///
  /// Set when a recipe ingredient is being matched (spec §5.5's in-recipe
  /// capture). The lookup is identical; what changes is where the flow ends —
  /// the chosen food's id is handed back to the caller instead of the user
  /// being left on the scanner.
  final bool pickFood;

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
          if (_cameraIsPossible && !_typing && _camera != null)
            _TorchButton(controller: _camera!),
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
                  : _CameraView(
                      controller: _camera!,
                      onDetect: _onDetect,
                      onTypeInstead: () => setState(() => _typing = true),
                    ),
            ),
            _ResultPanel(
              state: state,
              pickFood: widget.pickFood,
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

/// The live preview, a frame to line the barcode up against, and detection
/// restricted to what that frame actually shows.
///
/// A bare full-screen preview leaves it to guesswork how close to hold a
/// package and where in it the label needs to sit. The frame is not just
/// decoration — [MobileScanner.scanWindow] is set to the same rectangle, so a
/// second barcode elsewhere in frame (a shelf, a multipack) is genuinely
/// ignored rather than a plausible source of a wrong match.
class _CameraView extends StatelessWidget {
  const _CameraView({
    required this.controller,
    required this.onDetect,
    required this.onTypeInstead,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onTypeInstead;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Rect frame = _frameFor(constraints.biggest);
        return MobileScanner(
          controller: controller,
          onDetect: onDetect,
          scanWindow: frame,
          // Close-up labels in dim kitchen or pantry light are exactly where
          // autofocus struggles most; letting a tap re-focus costs nothing.
          tapToFocus: true,
          errorBuilder: (BuildContext context, MobileScannerException error) =>
              _CameraUnavailable(onTypeInstead: onTypeInstead),
          overlayBuilder: (BuildContext context, BoxConstraints _) =>
              _Viewfinder(frame: frame),
        );
      },
    );
  }

  /// Wide rather than square: every symbology scanned here (EAN/UPC) is a
  /// horizontal strip, so a square window either crops the sides of a
  /// close-up label or leaves most of itself unused.
  static Rect _frameFor(Size layout) {
    final double width = math.min(layout.width * 0.82, 360);
    final double height = width * 0.5;
    return Rect.fromCenter(
      center: layout.center(Offset.zero),
      width: width,
      height: height,
    );
  }
}

/// The frame itself: a dimmed scrim outside it, an open window inside it, and
/// an instruction below in words — the shape carries the idea, but §6.3 still
/// applies, so it is never the only thing saying it.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.frame});

  final Rect frame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          // Purely visual guidance over a preview a screen reader user cannot
          // see anyway; the barcode field's own semantics carry the workflow.
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _ViewfinderPainter(
                frame: frame,
                accent: context.colors.accent,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: frame.bottom + HearthSpacing.lg,
          child: ExcludeSemantics(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HearthSpacing.xl,
                ),
                child: Text(
                  'Line up the barcode inside the frame',
                  textAlign: TextAlign.center,
                  style: context.text.body.copyWith(
                    color: Colors.white,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 6, color: Colors.black87),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.frame, required this.accent});

  final Rect frame;
  final Color accent;

  static const double _cornerLength = 28;
  static const double _cornerStroke = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect hole = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(HearthRadius.lg),
    );
    final Path scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = const Color(0x8C000000));

    final Paint bracket = Paint()
      ..color = accent
      ..strokeWidth = _cornerStroke
      ..strokeCap = StrokeCap.round;

    void corner(Offset origin, Offset horizontal, Offset vertical) {
      canvas.drawLine(origin, origin + horizontal, bracket);
      canvas.drawLine(origin, origin + vertical, bracket);
    }

    const Offset h = Offset(_cornerLength, 0);
    const Offset v = Offset(0, _cornerLength);
    corner(frame.topLeft, h, v);
    corner(frame.topRight, -h, v);
    corner(frame.bottomLeft, h, -v);
    corner(frame.bottomRight, -h, -v);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.accent != accent;
}

/// Torch on/off, hidden entirely on hardware that has none rather than shown
/// disabled — a control nobody's device can ever act on is not a control.
class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (BuildContext context, MobileScannerState state, Widget? _) {
        if (state.torchState == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final bool on = state.torchState == TorchState.on;
        return IconButton(
          icon: Icon(on ? Icons.flash_on : Icons.flash_off),
          tooltip: on ? 'Turn off the flashlight' : 'Turn on the flashlight',
          onPressed: controller.toggleTorch,
        );
      },
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
    required this.pickFood,
    required this.onRetry,
    required this.onClear,
  });

  final BarcodeLookupState state;
  final bool pickFood;
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
            // The packet is in your hand at exactly this moment, which is why
            // reading its label leads and typing is the fallback behind it.
            // §5.5 treats the miss as a first-class path; this is the fastest
            // way off it.
            leadingLabel: canReadLabels(ref) ? 'Read the label' : null,
            leadingIcon: Icons.document_scanner_outlined,
            onLeading: () => _readLabel(context, ref, barcode),
            actionLabel: 'Add it by hand',
            onAction: () => _addByHand(context, barcode),
            secondaryLabel: 'Try again',
            onSecondary: onRetry,
          ),
          BarcodeFound(:final NutritionMatch match) => _Found(
            match: match,
            pickFood: pickFood,
            onDiscard: onClear,
            onReviewed: onClear,
          ),
        },
      ),
    );
  }

  /// Reads the packet's own label and opens the editor already filled in.
  ///
  /// The same destination as adding by hand, and deliberately so: this is
  /// manual entry with the typing removed, not a way around the review
  /// (CLAUDE.md rule 4).
  Future<void> _readLabel(
    BuildContext context,
    WidgetRef ref,
    String barcode,
  ) async {
    final LabelReading? reading = await showReadLabelSheet(context);
    if (reading == null || !context.mounted) return;

    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.forBarcode(barcode).withLabel(reading),
    );
    if (!context.mounted) return;
    if (pickFood && saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    onClear();
  }

  Future<void> _addByHand(BuildContext context, String barcode) async {
    // Straight into the food editor with the barcode already attached, so the
    // food that comes out of a miss is found by the next scan (spec §5.5).
    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.forBarcode(barcode),
    );
    if (!context.mounted) return;
    // A miss during ingredient matching still ends in a match: the food the
    // user just typed in is the one the line wanted.
    if (pickFood && saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
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
    required this.pickFood,
    required this.onDiscard,
    required this.onReviewed,
  });

  final NutritionMatch match;
  final bool pickFood;
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
                child: FilledButton(
                  onPressed: () => _primaryAction(context),
                  child: Text(_primaryLabel),
                ),
              ),
            ),
            const SizedBox(width: HearthSpacing.sm),
            TextButton(
              onPressed: onDiscard,
              child: Text(match.fromLibrary && !pickFood ? 'Done' : 'Discard'),
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
  /// What the primary button says, and it says what will happen.
  ///
  /// Four outcomes, because the two questions are independent: is this food
  /// already ours, and is the user filing it or choosing it for an ingredient?
  String get _primaryLabel => switch ((match.fromLibrary, pickFood)) {
    (true, true) => 'Use it',
    (true, false) => 'Open it',
    (false, true) => 'Check and use',
    (false, false) => 'Review and save',
  };

  Future<void> _primaryAction(BuildContext context) {
    // A library food already has an id, so choosing it for an ingredient needs
    // no review — the household has already vouched for these numbers.
    if (match.fromLibrary) {
      if (pickFood) {
        Navigator.of(context).pop(match.food.id);
        return Future<void>.value();
      }
      return _open(context);
    }
    return _review(context);
  }

  Future<void> _open(BuildContext context) async {
    await context.push<void>('/food/${match.food.id}');
    onReviewed();
  }

  Future<void> _review(BuildContext context) async {
    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.fromLookup(match.food),
    );
    if (!context.mounted) return;
    if (pickFood && saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
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
    this.leadingLabel,
    this.leadingIcon,
    this.onLeading,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// An action above the others, for when there is a faster way out than the
  /// one this message was originally written around.
  final String? leadingLabel;
  final IconData? leadingIcon;
  final VoidCallback? onLeading;

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
        if (leadingLabel != null) ...<Widget>[
          SizedBox(
            width: double.infinity,
            height: HearthTouch.minTarget,
            child: FilledButton.icon(
              onPressed: onLeading,
              icon: Icon(leadingIcon, size: 18),
              label: Text(leadingLabel!),
            ),
          ),
          const SizedBox(height: HearthSpacing.sm),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: HearthTouch.minTarget,
                child: leadingLabel == null
                    ? FilledButton(
                        onPressed: onAction,
                        child: Text(actionLabel),
                      )
                    : OutlinedButton(
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
