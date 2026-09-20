import 'dart:io';

import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/walmart_link_reader.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';

class WalmartFixtureReader implements LabelReader, WalmartLinkReader {
  int calls = 0;
  @override
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images) async {
    calls++;
    return WalmartLinkReading.fromJson({
      'status': 'found',
      'url': 'https://www.walmart.com/ip/10450479',
      'source': 'screenshot',
    });
  }

  @override
  Future<LabelReading> read(List<AiImage> images) async =>
      const LabelReading(servings: []);
  @override
  Future<PackReading> readPack(List<AiImage> images) async =>
      const PackReading();
}

class WalmartFixturePicker implements PhotoPicker {
  @override
  bool get canUseCamera => false;
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async => PickedPhoto(
    bytes: File('test/fixtures/walmart/walmart-link.png').readAsBytesSync(),
    extension: 'png',
  );
  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => [];
}
