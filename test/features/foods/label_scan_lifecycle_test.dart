import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/features/foods/label_scan_controller.dart';

PickedPhoto aPhoto() =>
    PickedPhoto(bytes: Uint8List.fromList([1]), extension: 'jpg');

class Picker implements PhotoPicker {
  Completer<PickedPhoto?>? pending;

  /// A gate per origin, so two picks can be open at once — which is the
  /// whole question when one slot is worked on while the other is waiting.
  final Map<PhotoOrigin, Completer<PickedPhoto?>> gates =
      <PhotoOrigin, Completer<PickedPhoto?>>{};
  @override
  bool get canUseCamera => true;
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    final Completer<PickedPhoto?>? gate = gates[origin] ?? pending;
    return gate == null ? aPhoto() : gate.future;
  }

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => [];
}

class Reader implements LabelReader {
  final Completer<LabelReading> pending = Completer<LabelReading>();
  List<AiImage> received = [];
  int calls = 0;
  @override
  Future<LabelReading> read(List<AiImage> images) {
    calls++;
    received = images;
    return pending.future;
  }

  @override
  Future<PackReading> readPack(List<AiImage> images) async =>
      const PackReading();
}

void main() {
  test('repeated Read while pending makes one label request', () async {
    final reader = Reader();
    final container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(Picker()),
        labelReaderProvider.overrideWithValue(reader),
      ],
    );
    final sub = container.listen(labelScanProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
    });
    final ctrl = container.read(labelScanProvider.notifier);
    await ctrl.pick(LabelSlot.nutrition, PhotoOrigin.library);
    final first = ctrl.read();
    await ctrl.read();
    expect(reader.calls, 1);
    reader.pending.complete(
      const LabelReading(servings: [LabelServing(amount: 30, unitId: 'g')]),
    );
    await first;
  });
  for (final bool replace in [true, false]) {
    test(
      'a ${replace ? 'replacement' : 'removal'} invalidates a pending read',
      () async {
        final Picker picker = Picker();
        final Reader reader = Reader();
        final ProviderContainer container = ProviderContainer(
          overrides: [
            photoPickerProvider.overrideWithValue(picker),
            labelReaderProvider.overrideWithValue(reader),
          ],
        );
        final sub = container.listen(labelScanProvider, (_, _) {});
        addTearDown(() {
          sub.close();
          container.dispose();
        });
        final ctrl = container.read(labelScanProvider.notifier);
        await ctrl.pick(LabelSlot.nutrition, PhotoOrigin.camera);
        final read = ctrl.read();
        expect(reader.received.single.role, 'nutrition');
        if (replace) {
          await ctrl.pick(LabelSlot.nutrition, PhotoOrigin.library);
        } else {
          ctrl.remove(LabelSlot.nutrition);
        }
        reader.pending.complete(
          const LabelReading(
            servings: [LabelServing(amount: 1, unitId: 'cup')],
          ),
        );
        await read;
        expect(container.read(labelScanProvider), isA<LabelScanIdle>());
      },
    );
  }
  test(
    'a picker finishing after reset cannot restore a dismissed photo',
    () async {
      final Picker picker = Picker()..pending = Completer<PickedPhoto?>();
      final container = ProviderContainer(
        overrides: [photoPickerProvider.overrideWithValue(picker)],
      );
      final sub = container.listen(labelScanProvider, (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });
      final ctrl = container.read(labelScanProvider.notifier);
      final picking = ctrl.pick(LabelSlot.nutrition, PhotoOrigin.camera);
      ctrl.reset();
      picker.pending!.complete(
        PickedPhoto(bytes: Uint8List.fromList([1]), extension: 'jpg'),
      );
      await picking;
      expect(container.read(labelScanProvider).hasAnyPhoto, isFalse);
    },
  );

  test(
    'clearing one slot leaves an in-flight pick for the other alone',
    () async {
      final Picker picker = Picker()
        ..gates[PhotoOrigin.camera] = Completer<PickedPhoto?>();
      final container = ProviderContainer(
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          labelReaderProvider.overrideWithValue(Reader()),
        ],
      );
      final sub = container.listen(labelScanProvider, (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });
      final ctrl = container.read(labelScanProvider.notifier);
      await ctrl.pick(LabelSlot.package, PhotoOrigin.library);
      final picking = ctrl.pick(LabelSlot.nutrition, PhotoOrigin.camera);
      // While the system picker is still open for the back label.
      ctrl.remove(LabelSlot.package);
      picker.gates[PhotoOrigin.camera]!.complete(aPhoto());
      await picking;
      final LabelScanState state = container.read(labelScanProvider);
      expect(
        state.backPhoto,
        isNotNull,
        reason: 'the other slot must not cancel this one',
      );
      expect(state.frontPhoto, isNull);
    },
  );

  test('two picks open at once each land in their own slot', () async {
    final Picker picker = Picker()
      ..gates[PhotoOrigin.camera] = Completer<PickedPhoto?>()
      ..gates[PhotoOrigin.library] = Completer<PickedPhoto?>();
    final container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        labelReaderProvider.overrideWithValue(Reader()),
      ],
    );
    final sub = container.listen(labelScanProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
    });
    final ctrl = container.read(labelScanProvider.notifier);
    final back = ctrl.pick(LabelSlot.nutrition, PhotoOrigin.camera);
    final front = ctrl.pick(LabelSlot.package, PhotoOrigin.library);
    picker.gates[PhotoOrigin.library]!.complete(aPhoto());
    picker.gates[PhotoOrigin.camera]!.complete(aPhoto());
    await Future.wait(<Future<void>>[back, front]);
    final LabelScanState state = container.read(labelScanProvider);
    expect(state.backPhoto, isNotNull);
    expect(state.frontPhoto, isNotNull);
  });

  test('a reset still invalidates every slot at once', () async {
    final Picker picker = Picker()
      ..gates[PhotoOrigin.camera] = Completer<PickedPhoto?>()
      ..gates[PhotoOrigin.library] = Completer<PickedPhoto?>();
    final container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        labelReaderProvider.overrideWithValue(Reader()),
      ],
    );
    final sub = container.listen(labelScanProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
    });
    final ctrl = container.read(labelScanProvider.notifier);
    final back = ctrl.pick(LabelSlot.nutrition, PhotoOrigin.camera);
    final front = ctrl.pick(LabelSlot.package, PhotoOrigin.library);
    ctrl.reset();
    picker.gates[PhotoOrigin.camera]!.complete(aPhoto());
    picker.gates[PhotoOrigin.library]!.complete(aPhoto());
    await Future.wait(<Future<void>>[back, front]);
    expect(container.read(labelScanProvider).hasAnyPhoto, isFalse);
  });
}
