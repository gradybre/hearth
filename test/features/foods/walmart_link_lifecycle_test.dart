import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/walmart_link_reader.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/features/foods/walmart_link_controller.dart';

PickedPhoto aPhoto() =>
    PickedPhoto(bytes: Uint8List.fromList([1]), extension: 'jpg');

class Picker implements PhotoPicker {
  Completer<PickedPhoto?>? pending;
  @override
  bool get canUseCamera => false;
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      pending == null ? aPhoto() : pending!.future;
  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => [];
}

class BigPicker implements PhotoPicker {
  @override
  bool get canUseCamera => false;
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: Uint8List(6 * 1024 * 1024), extension: 'jpg');
  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => [];
}

class Reader implements WalmartLinkReader {
  final Completer<WalmartLinkReading> pending = Completer<WalmartLinkReading>();
  int calls = 0;
  @override
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images) {
    calls++;
    return pending.future;
  }
}

class FlakyReader implements WalmartLinkReader {
  int calls = 0;
  @override
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images) async {
    calls++;
    if (calls == 1) {
      throw Exception('blip');
    }
    return WalmartLinkReading.fromJson(<String, Object?>{
      'status': 'found',
      'url': 'https://www.walmart.com/ip/98765',
      'source': 'screenshot',
    });
  }
}

void main() {
  test(
    'unsupported photo extension is rejected before it can be mislabeled jpeg',
    () async {
      final picker = Picker()..pending = Completer<PickedPhoto?>();
      final reader = Reader();
      final container = ProviderContainer(
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          walmartLinkReaderProvider.overrideWithValue(reader),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(walmartLinkScanProvider, (_, _) {});
      addTearDown(sub.close);
      final ctrl = container.read(walmartLinkScanProvider.notifier);
      final picked = ctrl.pick();
      picker.pending!.complete(
        PickedPhoto(bytes: Uint8List.fromList([1]), extension: 'heic'),
      );
      await picked;
      expect(
        container.read(walmartLinkScanProvider),
        isA<WalmartLinkScanFailed>(),
      );
      expect(container.read(walmartLinkScanProvider).hasPhoto, isFalse);
      expect(reader.calls, 0);
    },
  );

  test('choosing a photo never triggers a read on its own', () async {
    final Picker picker = Picker();
    final Reader reader = Reader();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        walmartLinkReaderProvider.overrideWithValue(reader),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    expect(reader.calls, 0);
    expect(container.read(walmartLinkScanProvider), isA<WalmartLinkScanIdle>());
  });

  test('a duplicate read while one is in flight is a no-op', () async {
    final Picker picker = Picker();
    final Reader reader = Reader();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        walmartLinkReaderProvider.overrideWithValue(reader),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    final Future<void> first = ctrl.read();
    final Future<void> second = ctrl.read();
    expect(reader.calls, 1);
    reader.pending.complete(const WalmartLinkReading.notFound());
    await first;
    await second;
  });

  test('cancelling the picker keeps a previously selected photo', () async {
    final Picker picker = Picker();
    final ProviderContainer container = ProviderContainer(
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    picker.pending = Completer<PickedPhoto?>();
    final Future<void> picking = ctrl.pick();
    picker.pending!.complete(null);
    await picking;
    expect(container.read(walmartLinkScanProvider).hasPhoto, isTrue);
  });

  test(
    'a stale success after a replacement does not overwrite state',
    () async {
      final Picker picker = Picker();
      final Reader reader = Reader();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          walmartLinkReaderProvider.overrideWithValue(reader),
        ],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(walmartLinkScanProvider.notifier);
      await ctrl.pick();
      final Future<void> readFuture = ctrl.read();
      final Future<void> pickFuture = ctrl.pick();
      reader.pending.complete(
        WalmartLinkReading.fromJson(<String, Object?>{
          'status': 'found',
          'url': 'https://www.walmart.com/ip/12345',
          'source': 'screenshot',
        }),
      );
      await readFuture;
      await pickFuture;
      expect(
        container.read(walmartLinkScanProvider),
        isNot(isA<WalmartLinkScanFound>()),
      );
    },
  );

  test(
    'a picker finishing after reset cannot restore a dismissed photo',
    () async {
      final Picker picker = Picker()..pending = Completer<PickedPhoto?>();
      final ProviderContainer container = ProviderContainer(
        overrides: [photoPickerProvider.overrideWithValue(picker)],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(walmartLinkScanProvider.notifier);
      final Future<void> picking = ctrl.pick();
      ctrl.reset();
      picker.pending!.complete(aPhoto());
      await picking;
      expect(container.read(walmartLinkScanProvider).hasPhoto, isFalse);
    },
  );

  test(
    'disposing while a read is pending does not crash or mutate state',
    () async {
      final Picker picker = Picker();
      final Reader reader = Reader();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          photoPickerProvider.overrideWithValue(picker),
          walmartLinkReaderProvider.overrideWithValue(reader),
        ],
      );
      final ctrl = container.read(walmartLinkScanProvider.notifier);
      await ctrl.pick();
      final Future<void> readFuture = ctrl.read();
      container.dispose();
      reader.pending.complete(const WalmartLinkReading.notFound());
      await readFuture;
    },
  );

  test('nonretryable failure clears screenshot bytes', () async {
    final Picker picker = Picker();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        walmartLinkReaderProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    await ctrl.read();
    final WalmartLinkScanState state = container.read<WalmartLinkScanState>(
      walmartLinkScanProvider,
    );
    expect(state, isA<WalmartLinkScanFailed>());
    expect((state as WalmartLinkScanFailed).canRetry, isFalse);
    expect(state.hasPhoto, isFalse);
  });

  test('an oversize photo is rejected before sending', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [photoPickerProvider.overrideWithValue(BigPicker())],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    final WalmartLinkScanState state = container.read<WalmartLinkScanState>(
      walmartLinkScanProvider,
    );
    expect(state, isA<WalmartLinkScanFailed>());
    expect(state.hasPhoto, isFalse);
  });

  test('retrying after a failure reuses the original photo', () async {
    final Picker picker = Picker();
    final FlakyReader reader = FlakyReader();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        walmartLinkReaderProvider.overrideWithValue(reader),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    await ctrl.read();
    WalmartLinkScanState state = container.read<WalmartLinkScanState>(
      walmartLinkScanProvider,
    );
    expect(state, isA<WalmartLinkScanFailed>());
    expect((state as WalmartLinkScanFailed).canRetry, isTrue);
    expect(state.hasPhoto, isTrue);
    await ctrl.read();
    state = container.read<WalmartLinkScanState>(walmartLinkScanProvider);
    expect(state, isA<WalmartLinkScanFound>());
    expect(reader.calls, 2);
    expect(state.hasPhoto, isFalse);
  });

  test('a completed miss clears transient screenshot bytes', () async {
    final Picker picker = Picker();
    final Reader reader = Reader();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        walmartLinkReaderProvider.overrideWithValue(reader),
      ],
    );
    addTearDown(container.dispose);
    final ctrl = container.read(walmartLinkScanProvider.notifier);
    await ctrl.pick();
    final Future<void> readFuture = ctrl.read();
    reader.pending.complete(const WalmartLinkReading.notFound());
    await readFuture;
    final WalmartLinkScanState state = container.read<WalmartLinkScanState>(
      walmartLinkScanProvider,
    );
    expect(state, isA<WalmartLinkScanMiss>());
    expect((state as WalmartLinkScanMiss).status, WalmartLinkStatus.notFound);
    expect(state.hasPhoto, isFalse);
  });
}
