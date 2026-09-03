import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import '../../domain/foods/produce_plu.dart';
import '../../domain/models/food.dart';
import 'barcode_lookup_controller.dart';
import 'external_food_results.dart';
import 'food_draft.dart';
import 'food_search_controller.dart';
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

  /// Whether asking for an orientation is a question this platform answers.
  ///
  /// Desktop embedders do not implement it, and a MissingPluginException on
  /// the way into a screen is a crash rather than a preference not honoured.
  static bool get _rotationCanBeLocked =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    // Held over a packet, a phone is somewhere between flat and upright and
    // the accelerometer keeps changing its mind. Every flip relays out the
    // frame, moves the scan window under a barcode that has not moved, and
    // restarts the preview — so the one moment the camera needs to be still
    // is the one where the screen is most likely to turn over.
    if (_rotationCanBeLocked) {
      unawaited(
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]),
      );
    }
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
    // Back to whatever Info.plist allows, rather than a list repeated here:
    // an empty list means "the app's own supported set", which is one place
    // to change it and already differs between iPhone and iPad.
    if (_rotationCanBeLocked) {
      unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[]));
    }
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

  /// Reads a packet's label when there is no barcode to read at all.
  ///
  /// A torn wrapper, a deli tub, a multipack split open — the scanner's other
  /// two ways in both need a number, and this is the case where there is none
  /// to type. §5.5's chain ends at manual entry; this is that end of it with
  /// the typing removed, and it lands in the same editor to be checked
  /// (CLAUDE.md rule 4).
  Future<void> _readLabelWithNoBarcode() async {
    // The system camera is about to take over the screen, and two cameras
    // competing for the device is a stall the user reads as a freeze.
    await _pauseCamera();
    if (!mounted) return;

    final LabelReading? reading = await showReadLabelSheet(context);
    if (!mounted) return;
    if (reading == null) {
      await _resumeCamera();
      return;
    }

    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.blank().withLabel(reading),
    );
    if (!mounted) return;
    if (widget.pickFood && saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    await _resumeCamera();
  }

  Future<void> _pauseCamera() async {
    try {
      await _camera?.stop();
    } on Object {
      // Stopping a camera that was never running is not a failure worth
      // showing anyone.
    }
  }

  Future<void> _resumeCamera() async {
    if (_typing) return;
    try {
      await _camera?.start();
    } on Object {
      // Same: the preview coming back is a nicety, not the flow.
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
                      onReadLabel: canReadLabels(ref)
                          ? _readLabelWithNoBarcode
                          : null,
                    )
                  : _CameraView(
                      controller: _camera!,
                      onDetect: _onDetect,
                      onTypeInstead: () => setState(() => _typing = true),
                      onReadLabel: canReadLabels(ref)
                          ? _readLabelWithNoBarcode
                          : null,
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
    this.onReadLabel,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool cameraAvailable;

  /// Null when this build cannot read labels at all — see [canReadLabels].
  final VoidCallback? onReadLabel;

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
                    ? 'For a torn label, or when the camera will not settle. '
                          'A produce sticker works here too — type its four '
                          'or five digits.'
                    : 'This device has no camera to scan with. A produce '
                          "sticker's four or five digits work here too.",
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
                  labelText: 'Barcode or produce code',
                  hintText: '5000157024671, or 4011',
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
              // The one case neither the camera nor this field can answer: a
              // packet whose barcode is torn off, or that never had one. Both
              // other ways in need a number, and here there is none to give.
              if (onReadLabel case final VoidCallback read) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                SizedBox(
                  height: HearthTouch.minTarget,
                  child: TextButton.icon(
                    onPressed: read,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('No barcode? Read the label'),
                  ),
                ),
              ],
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
    this.onReadLabel,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onTypeInstead;

  /// Null when this build cannot read labels at all — see [canReadLabels].
  final VoidCallback? onReadLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Rect frame = _frameFor(constraints.biggest);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: MobileScanner(
                controller: controller,
                onDetect: onDetect,
                scanWindow: frame,
                // Close-up labels in dim kitchen or pantry light are exactly
                // where autofocus struggles most; letting a tap re-focus
                // costs nothing.
                tapToFocus: true,
                errorBuilder: (
                  BuildContext context,
                  MobileScannerException error,
                ) => _CameraUnavailable(onTypeInstead: onTypeInstead),
                overlayBuilder: (BuildContext context, BoxConstraints _) =>
                    _Viewfinder(frame: frame),
              ),
            ),
            // Deliberately outside the scanner's own overlay. mobile_scanner
            // wraps whatever `overlayBuilder` returns in an IgnorePointer
            // whenever `tapToFocus` is on — reasonable, since an overlay is
            // usually a viewfinder — so a button put there is painted
            // perfectly and can never be pressed. It has to sit above the
            // scanner instead, where taps reach it and everything it does not
            // cover still falls through to tap-to-focus.
            Positioned(
              left: 0,
              right: 0,
              top: frame.bottom + HearthSpacing.lg,
              child: _BelowTheFrame(
                controller: controller,
                onReadLabel: onReadLabel,
              ),
            ),
          ],
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
      ],
    );
  }
}

/// The words under the frame, and the way out when there is no barcode at all.
///
/// Hidden while the camera is failing: [_CameraUnavailable] has that whole
/// area then, and instructions for a preview nobody can see would be painted
/// straight over the explanation of why.
class _BelowTheFrame extends StatelessWidget {
  const _BelowTheFrame({required this.controller, this.onReadLabel});

  final MobileScannerController controller;
  final VoidCallback? onReadLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (BuildContext context, MobileScannerState state, Widget? _) {
        if (state.error != null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.xl),
          child: Column(
            children: <Widget>[
              // The shape carries the idea, but §6.3 still applies, so it is
              // never the only thing saying it. Excluded from semantics all
              // the same: it describes a preview a screen reader user cannot
              // see, and the barcode field's own semantics carry the workflow.
              ExcludeSemantics(
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
              // Offered here rather than only after a miss: a torn or missing
              // barcode never gets as far as a miss, and this is where
              // somebody holding one is standing.
              if (onReadLabel case final VoidCallback read) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                SizedBox(
                  height: HearthTouch.minTarget,
                  child: TextButton.icon(
                    onPressed: read,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('No barcode? Read the label'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
          ProduceFound(:final ProduceItem produce) => _Produce(
            produce: produce,
            pickFood: pickFood,
            onClear: onClear,
          ),
          ProduceUnknown(:final String code) => _Message(
            icon: Icons.help_outline,
            title: 'Produce code $code is not one I know',
            detail:
                'The sticker codes are a long list and this one is not in it '
                'yet. Add the food by hand and Hearth will keep it against '
                'this code.',
            actionLabel: 'Add it by hand',
            onAction: () => _addByHand(context, code),
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

/// A produce code, resolved to what it names (spec §5.5).
///
/// It stops at the name on purpose. A PLU identifies a commodity, not a
/// product — 4011 is "bananas", not anybody's particular bananas — so there
/// are no macros to show and nothing to save yet. The name is what goes out to
/// the sources, and the household picks from what comes back.
class _Produce extends ConsumerStatefulWidget {
  const _Produce({
    required this.produce,
    required this.pickFood,
    required this.onClear,
  });

  final ProduceItem produce;
  final bool pickFood;
  final VoidCallback onClear;

  @override
  ConsumerState<_Produce> createState() => _ProduceState();
}

class _ProduceState extends ConsumerState<_Produce> {
  @override
  void initState() {
    super.initState();
    // The code has already said what it is, so the search for it runs without
    // being asked for — there is no second question to put to the user here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(foodSearchProvider.notifier).search(widget.produce.name);
      }
    });
  }

  /// A food saved from here carries the sticker's code, so typing it again
  /// finds this one first — the same property a barcode has (§5.5).
  Future<void> _addByHand() async {
    final String? saved = await context.push<String>(
      '/food/new',
      extra: FoodDraft.forBarcode(widget.produce.code)
          .copyWith(name: widget.produce.label),
    );
    if (!mounted) return;
    if (widget.pickFood && saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.eco_outlined, size: 18, color: colors.textSecondary),
            const SizedBox(width: HearthSpacing.sm),
            Expanded(
              child: Text(
                widget.produce.label,
                style: context.text.sectionHeader,
              ),
            ),
            Text(
              'Produce code ${widget.produce.code}',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          'A sticker says what the food is, not whose it is. Pick the closest '
          'match, or add it yourself.',
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        // Bounded: this sits in a panel over a camera, and the results are a
        // shortlist rather than a library to browse.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: ExternalFoodResults(
              query: widget.produce.name,
              onSaved: widget.pickFood
                  ? (String id) => Navigator.of(context).pop(id)
                  : (String id) => widget.onClear(),
            ),
          ),
        ),
        const SizedBox(height: HearthSpacing.sm),
        SizedBox(
          width: double.infinity,
          height: HearthTouch.minTarget,
          child: OutlinedButton(
            onPressed: _addByHand,
            child: const Text('Add it by hand'),
          ),
        ),
      ],
    );
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
class _Found extends ConsumerWidget {
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

  /// Whether the packet in your hand can say more than the database just did.
  ///
  /// Open Food Facts answers with a name and no numbers constantly, and the
  /// old panel could only say so: "this entry looks incomplete, check the
  /// numbers", with the box being held and no way to point a camera at it.
  ///
  /// Only for a stranger's entry. A food already in the library has its own
  /// id, and reading a label into a *new* draft would file a second copy of
  /// something the household already keeps — its editor has the same button,
  /// which is where that correction belongs.
  bool get _labelWouldHelp =>
      !match.fromLibrary &&
      (match.food.needsAttention || match.isLowConfidence);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final ServingOption? first = match.food.defaultServing;

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
        if (first != null) ...<Widget>[
          const SizedBox(height: HearthSpacing.sm),
          Text(
            '${first.label} · ${first.macros.kcal.round()} kcal · '
            '${first.macros.proteinG.round()} g protein',
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ],
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
        if (_labelWouldHelp && canReadLabels(ref)) ...<Widget>[
          SizedBox(
            width: double.infinity,
            height: HearthTouch.minTarget,
            child: OutlinedButton.icon(
              onPressed: () => _readLabel(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Read the label'),
            ),
          ),
          const SizedBox(height: HearthSpacing.sm),
        ],
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

  /// Keeps what the database got right and lets the packet supply the rest.
  ///
  /// Starting from the lookup rather than from blank: the name, brand, and
  /// barcode are usually the part it had, and the numbers are the part it did
  /// not. [FoodDraft.withLabel] fills blanks only, so nothing the database
  /// knew is overwritten by the photo.
  Future<void> _readLabel(BuildContext context) async {
    final LabelReading? reading = await showReadLabelSheet(context);
    if (reading == null || !context.mounted) return;
    await _review(context, reading: reading);
  }

  Future<void> _review(BuildContext context, {LabelReading? reading}) async {
    final FoodDraft draft = FoodDraft.fromLookup(match.food);
    final String? saved = await context.push<String>(
      '/food/new',
      extra: reading == null ? draft : draft.withLabel(reading),
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
            FoodSource.restaurant => 'Restaurant menu',
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
