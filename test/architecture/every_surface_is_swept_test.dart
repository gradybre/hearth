import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/swept_surfaces.dart';

/// A sweep cannot miss what it was never told about (spec §6.3).
///
/// The accessibility sweep is a list of journeys somebody wrote down. Three
/// times in one package a surface was put behind an interaction — the rings
/// behind Details, the log sheet's confirm view, the ways to add a recipe —
/// and each time it left the swept surface without a sound, because nothing
/// anywhere said it should have been added.
///
/// Extending the sweep by hand each time treats the symptom. This makes the
/// omission itself the failure: anything in `lib/` that puts a sheet or a
/// dialog on the screen must be named in [sweptSurfaces] or in [notSweptYet],
/// and the second one costs you a sentence explaining why.
void main() {
  test('every sheet and dialog is either swept or written down', () {
    final Directory lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'lib/ should exist; is the test running from the repo root?',
    );

    final RegExp opener = RegExp(r'\b(showModalBottomSheet|showDialog)\b');
    final Set<String> declared = <String>{
      for (final SweptSurface surface in sweptSurfaces) surface.opensFrom,
      ...notSweptYet.keys,
    };

    final List<String> unaccounted = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (!opener.hasMatch(entity.readAsStringSync())) continue;
      if (declared.contains(entity.path)) continue;
      unaccounted.add(entity.path);
    }

    expect(
      unaccounted,
      isEmpty,
      reason:
          'These put a sheet or a dialog on the screen and no sweep visits '
          'them. Add a SweptSurface for each in test/support/'
          'swept_surfaces.dart, or an entry in notSweptYet saying why not:\n'
          '${unaccounted.join('\n')}',
    );
  });

  test('and nothing is written down that no longer opens one', () {
    // The other direction. An entry left behind after its sheet is gone reads
    // as coverage that does not exist, and an excuse for a file that no
    // longer needs one is worse than no excuse at all.
    final RegExp opener = RegExp(r'\b(showModalBottomSheet|showDialog)\b');
    final List<String> stale = <String>[
      for (final String path in <String>[
        ...sweptSurfaces.map((SweptSurface s) => s.opensFrom),
        ...notSweptYet.keys,
      ])
        if (!File(path).existsSync() ||
            !opener.hasMatch(File(path).readAsStringSync()))
          path,
    ];

    expect(
      stale,
      isEmpty,
      reason:
          'These are listed as opening a sheet or dialog and no longer do:\n'
          '${stale.join('\n')}',
    );
  });

  test('every swept surface says how to tell it arrived', () {
    // "No exception" is equally true of a journey that never left the screen
    // it started on. Three of this sweep's first flows reported success from
    // exactly there.
    for (final SweptSurface surface in sweptSurfaces) {
      expect(
        surface.arrived,
        isNotNull,
        reason: '${surface.name} has no way to tell it got there',
      );
    }
  });
}
