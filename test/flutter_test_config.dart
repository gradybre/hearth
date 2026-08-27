import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads Hearth's bundled fonts before any test runs.
///
/// Without this, widget and golden tests render in the default test fallback
/// face regardless of what the theme asks for — so a golden would happily
/// "pass" while showing type that is nothing like the shipped app, and any
/// layout assertion about text size would be measuring the wrong font.
///
/// `flutter_test_config.dart` is picked up automatically by `flutter test` for
/// every test in this directory tree.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await _loadFont('Fraunces', 'assets/fonts/Fraunces.ttf');
  await _loadFont('SourceSans3', 'assets/fonts/SourceSans3.ttf');

  await testMain();
}

Future<void> _loadFont(String family, String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Font asset missing: $path. Fonts are committed to the repo because the '
      'app must work offline (spec §7.1); if this file is gone, the bundle is '
      'broken, not just the tests.',
    );
  }
  final FontLoader loader = FontLoader(family)
    ..addFont(
      file.readAsBytes().then(
        (List<int> bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
      ),
    );
  await loader.load();
}
