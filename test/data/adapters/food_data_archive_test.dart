import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/archive_photo_reader.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/food_data_archive.dart';
import 'package:hearth/data/adapters/readable_archive_rows.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<PreparedFoodArchive> prepare(
    ExportSnapshot snapshot, {
    bool includePhotos = false,
    ArchivePhotoReader? photos,
    bool Function()? isCurrent,
    void Function(ArchiveProgress)? onProgress,
    Duration photoReadTimeout = const Duration(seconds: 15),
  }) =>
      FoodDataArchive(
        dataExport: _Export(snapshot),
        photos: photos,
        temporaryDirectory: () async => directory,
        photoReadTimeout: photoReadTimeout,
      ).prepare(
        householdId: 'home',
        userId: 'me',
        includePhotos: includePhotos,
        isCurrent: isCurrent,
        onProgress: onProgress,
      );

  test(
    'ZIP carries byte-identical original JSON and counted readable members',
    () async {
      final ExportSnapshot snapshot = _snapshot(_data());
      final PreparedFoodArchive result = await prepare(snapshot);
      final Map<String, List<int>> files = await _unzip(result);
      expect(
        files['original/hearth-2026-10-01.json'],
        utf8.encode(snapshot.file.contents),
      );
      expect(
        files.keys,
        containsAll(<String>[
          'logs.csv',
          'plans.csv',
          'targets.csv',
          'foods.csv',
          'READ-ME.txt',
          'photos-unavailable.csv',
          'archive-manifest.json',
        ]),
      );
      expect(result.bytes, await File(result.path).length());
      expect(result.files.length, files.length);
      for (final ArchiveFileFact fact in result.files) {
        expect(fact.bytes, files[fact.path]!.length, reason: fact.path);
      }
      expect(result.photosRequested, isFalse);
      expect(result.includedPhotos, isEmpty);
      expect(result.unavailablePhotos, isEmpty);
      expect(
        utf8.decode(files['READ-ME.txt']!),
        contains('not an import or restore feature'),
      );
      final String owned = result.path;
      await result.discard();
      await result.discard();
      expect(await File(owned).exists(), isFalse);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('frozen names, exact portions, unknowns and distinct dates survive current definitions', () async {
    final Map<String, Object?> data = _data();
    final PreparedFoodArchive result = await prepare(
      _snapshot(data, deleted: {'log': true}),
    );
    final Map<String, String> row = _csvRows(
      utf8.decode((await _unzip(result))['logs.csv']!),
    ).single;
    expect(row['name'], 'Old oats');
    expect(row['kcal'], '90.0');
    expect(row['fiber_g'], '');
    expect(row['sodium_mg'], '0.0');
    expect(row['fiber_coverage'], 'unknown');
    expect(row['sodium_coverage'], 'complete');
    expect(row['cholesterol_coverage'], 'partial');
    expect(row['is_deleted'], 'true');
    expect(row['entered_amount'], '37.123456789');
    expect(row['entered_unit'], 'g');
    expect(row['nutrition_serving_amount'], '100.0');
    expect(row['nutrition_serving_unit'], 'g');
    expect(row['diary_date'], '2026-09-29');
    expect(row['logged_at_utc'], '2026-10-01T01:00:00.000Z');
    expect(
      row['snapshot_captured_at_as_recorded'],
      '2026-09-30T23:30:00-04:00',
    );
    expect(row['uses_approximate_package_nutrition'], 'true');
    final Map<String, String> food = _csvRows(
      utf8.decode((await _unzip(result))['foods.csv']!),
    ).single;
    expect(food['name'], 'New oats');
    expect(food['kcal'], '999');
  });

  for (final String evidence in <String>[
    'legacy',
    'future',
    'stale',
    'invalidated',
  ]) {
    test(
      '$evidence portion does not fabricate raw units or lose raw JSON',
      () async {
        final Map<String, Object?> data = _data();
        final Map<String, Object?> raw = _rawSnapshot(data);
        if (evidence == 'legacy') {
          raw.remove('logged_portion');
          raw.remove('coverage');
          raw.remove('uses_approximate_package_nutrition');
        } else if (evidence == 'stale') {
          raw['servings'] = 2.0;
        } else {
          final Map<String, Object?> portion =
              raw['logged_portion']! as Map<String, Object?>;
          portion[evidence == 'future' ? 'version' : 'invalidated'] =
              evidence == 'future' ? 999 : true;
          raw['future_evidence'] = <String, Object?>{
            'keep': <Object?>['all', 7],
          };
        }
        final ExportSnapshot snapshot = _snapshot(data);
        final PreparedFoodArchive result = await prepare(snapshot);
        final Map<String, List<int>> files = await _unzip(result);
        final Map<String, String> row = _csvRows(
          utf8.decode(files['logs.csv']!),
        ).single;
        expect(row['entered_amount'], '');
        expect(row['entered_unit'], '');
        expect(row['nutrition_serving_label'], '');
        expect(
          row['portion_evidence'],
          evidence == 'legacy'
              ? 'not recorded'
              : 'unavailable; see original JSON',
        );
        expect(row['is_deleted'], 'not recorded');
        expect(
          files['original/hearth-2026-10-01.json'],
          utf8.encode(snapshot.file.contents),
        );
        if (evidence == 'legacy') {
          expect(row['fiber_coverage'], 'notRecorded');
          expect(row['uses_approximate_package_nutrition'], '');
        }
      },
    );
  }

  test(
    'target boundaries, stops and null/zero distinctions stay authored',
    () async {
      final Map<String, Object?> data = _data();
      data['macro_targets'] = <Object?>[
        <String, Object?>{
          'id': 'weekly',
          'week_start_date': '2026-09-28',
          'kcal': 2000,
          'fiber_g': null,
          'sodium_mg': 0,
        },
      ];
      data['ongoing_macro_targets'] = <Object?>[
        <String, Object?>{
          'id': 'ongoing',
          'week_start_date': '2026-09-21',
          'is_stopped': false,
          'kcal': 2100,
        },
        <String, Object?>{
          'id': 'stop',
          'week_start_date': '2026-10-05',
          'is_stopped': true,
        },
      ];
      final PreparedFoodArchive result = await prepare(_snapshot(data));
      final List<Map<String, String>> rows = _csvRows(
        utf8.decode((await _unzip(result))['targets.csv']!),
      );
      expect(rows.length, 3);
      expect(rows[0]['record_type'], 'exact week');
      expect(rows[0]['fiber_g'], '');
      expect(rows[0]['sodium_mg'], '0');
      expect(rows[1]['record_type'], 'from this week onward');
      expect(rows[2]['record_type'], 'stop carrying forward');
      expect(rows[2]['kcal'], '');
    },
  );

  test(
    'recipe text preserves authored cups and directions with safe unique names',
    () async {
      final Map<String, Object?> data = _data();
      final Map<String, Object?> recipe = <String, Object?>{
        'id': 'recipe-1',
        'household_id': 'home',
        'title': '../../CON: Soup 🥣',
        'servings': 4,
        'sections': <Object?>[
          <String, Object?>{'id': 'section', 'name': 'Soup'},
        ],
        'ingredients': <Object?>[
          <String, Object?>{
            'section_id': 'section',
            'name': 'stock',
            'quantity_canonical': Units.cup.toCanonical * 2,
            'quantity_kind': 'volume',
            'quantity_unit': Units.cup.id,
            'raw_text': '2 cups stock',
          },
        ],
        'steps': <Object?>[
          <String, Object?>{
            'section_id': 'section',
            'step_number': 1,
            'body': 'Simmer gently.',
            'timer_seconds': 600,
          },
        ],
        'notes': 'Freezes well.',
      };
      data['recipes'] = <Object?>[
        recipe,
        <String, Object?>{...recipe, 'id': 'recipe-2'},
      ];
      final PreparedFoodArchive result = await prepare(_snapshot(data));
      final Map<String, List<int>> files = await _unzip(result);
      final List<String> names = files.keys
          .where((String path) => path.startsWith('recipes/'))
          .toList();
      expect(names.length, 2);
      expect(names.toSet().length, 2);
      for (final String path in names) {
        expect(path, matches(r'^recipes/[0-9]+-[A-Za-z0-9-]+\.txt$'));
        final String body = utf8.decode(files[path]!);
        expect(body, contains('2.0 cup stock'));
        expect(body, contains('Original wording: 2 cups stock'));
        expect(body, contains('Simmer gently.'));
        expect(body, contains('Freezes well.'));
      }
    },
  );

  test(
    'CSV quotes embedded commas/newlines/quotes and neutralizes formulas',
    () {
      final String csv = archiveCsv(<List<Object?>>[
        <Object?>['name', 'amount'],
        <Object?>['a,"b"\r\nc', 0],
        <Object?>[' \t=SUM(1,2)', -2],
        <Object?>['+cmd', 1],
        <Object?>['-cmd', 1],
        <Object?>['@cmd', 1],
      ]).join();
      expect(csv, startsWith('\uFEFF"name","amount"\r\n'));
      expect(csv, contains('"a,""b""\r\nc","0"\r\n'));
      final List<Map<String, String>> rows = _csvRows(csv);
      expect(rows[0]['name'], 'a,"b"\r\nc');
      expect(rows[1]['name'], "' \t=SUM(1,2)");
      expect(rows[1]['amount'], '-2');
      for (final Map<String, String> row in rows.skip(2)) {
        expect(row['name'], startsWith("'"));
      }
    },
  );

  test('photos default off without even calling the photo reader', () async {
    final _Photos reader = _Photos(
      (ExportPhotoReference ref) async => throw StateError('must not read'),
    );
    final PreparedFoodArchive result = await prepare(
      _snapshot(_data(), photos: <ExportPhotoReference>[_reference()]),
      photos: reader,
    );
    expect(reader.calls, 0);
    expect(result.photosRequested, isFalse);
  });

  test('optional photos are sequential, and every omission is reviewed and archived', () async {
    final Map<String, Object?> data = _data();
    data['recipes'] = <Object?>[
      for (int i = 1; i <= 3; i++)
        <String, Object?>{
          'id': 'recipe-$i',
          'household_id': 'home',
          'title': 'Photo $i',
        },
    ];
    final List<ExportPhotoReference> photos = <ExportPhotoReference>[
      for (int i = 1; i <= 3; i++) _reference(id: 'recipe-$i'),
    ];
    final _Photos reader = _Photos((ExportPhotoReference ref) async {
      await Future<void>.delayed(Duration.zero);
      return ref.recipeId == 'recipe-2'
          ? const ArchivePhotoRead.unavailable('Offline photo')
          : ArchivePhotoRead.available(
              Uint8List.fromList(<int>[1, 2, 3]),
              'jpg',
            );
    });
    final PreparedFoodArchive result = await prepare(
      _snapshot(data, photos: photos),
      includePhotos: true,
      photos: reader,
    );
    expect(reader.maxActive, 1);
    expect(result.includedPhotos.length, 2);
    expect(result.unavailablePhotos.single.recipeId, 'recipe-2');
    final Map<String, List<int>> files = await _unzip(result);
    for (final ArchivePhotoFact photo in result.includedPhotos) {
      expect(files[photo.path], <int>[1, 2, 3]);
    }
    expect(
      _csvRows(utf8.decode(files['photos-unavailable.csv']!)).single['reason'],
      'Offline photo',
    );
    expect(utf8.decode(files['archive-manifest.json']!), contains('recipe-2'));
  });

  test('foreign photo evidence is omitted before a reader is called', () async {
    final _Photos reader = _Photos(
      (ExportPhotoReference ref) async => throw StateError('foreign'),
    );
    final PreparedFoodArchive result = await prepare(
      _snapshot(
        _data(),
        photos: <ExportPhotoReference>[_reference(home: 'other')],
      ),
      includePhotos: true,
      photos: reader,
    );
    expect(reader.calls, 0);
    expect(result.unavailablePhotos, hasLength(1));
  });

  test(
    'cancellation while a photo is pending removes every unshared temp file',
    () async {
      bool current = true;
      final Completer<ArchivePhotoRead> pending = Completer<ArchivePhotoRead>();
      final Completer<void> started = Completer<void>();
      final _Photos reader = _Photos((ExportPhotoReference ref) {
        started.complete();
        return pending.future;
      });
      final Map<String, Object?> data = _data();
      data['recipes'] = <Object?>[
        <String, Object?>{
          'id': 'recipe-1',
          'household_id': 'home',
          'title': 'Recipe',
        },
      ];
      final Future<PreparedFoodArchive> work = prepare(
        _snapshot(data, photos: <ExportPhotoReference>[_reference()]),
        includePhotos: true,
        photos: reader,
        isCurrent: () => current,
      );
      final Future<void> expectation = expectLater(
        work,
        throwsA(isA<ArchivePreparationCancelled>()),
      );
      await started.future;
      current = false;
      pending.complete(
        ArchivePhotoRead.available(Uint8List.fromList(<int>[1]), 'jpg'),
      );
      await expectation;
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'cancellation after file creation also cleans up without photo work',
    () async {
      bool current = true;
      await expectLater(
        prepare(
          _snapshot(_data()),
          isCurrent: () => current,
          onProgress: (ArchiveProgress p) {
            if (p.message == 'Writing readable food data') current = false;
          },
        ),
        throwsA(isA<ArchivePreparationCancelled>()),
      );
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'cancelling a stalled photo releases the partial archive promptly',
    () async {
      final Completer<void> started = Completer<void>();
      final Completer<ArchivePhotoRead> pending = Completer<ArchivePhotoRead>();
      bool current = true;
      final Map<String, Object?> data = _data()
        ..['recipes'] = <Object?>[
          <String, Object?>{
            'id': 'recipe-1',
            'household_id': 'home',
            'title': 'Recipe',
          },
        ];
      final Future<PreparedFoodArchive> work = prepare(
        _snapshot(data, photos: <ExportPhotoReference>[_reference()]),
        includePhotos: true,
        photos: _Photos((_) {
          started.complete();
          return pending.future;
        }),
        isCurrent: () => current,
      );
      final Future<void> expectation = expectLater(
        work.timeout(const Duration(seconds: 2)),
        throwsA(isA<ArchivePreparationCancelled>()),
      );
      await started.future;
      current = false;
      await expectation;
      expect(await directory.list().toList(), isEmpty);
      // Deliberately never complete the remote download. Cancellation owns
      // local cleanup independently of whether that request ever returns.
    },
  );

  for (final bool lateError in <bool>[false, true]) {
    test(
      'a timed-out photo is listed and its late result cannot change the ZIP ($lateError)',
      () async {
        final Completer<ArchivePhotoRead> pending =
            Completer<ArchivePhotoRead>();
        final Map<String, Object?> data = _data()
          ..['recipes'] = <Object?>[
            <String, Object?>{
              'id': 'recipe-1',
              'household_id': 'home',
              'title': 'Recipe',
            },
          ];
        final PreparedFoodArchive result = await prepare(
          _snapshot(data, photos: <ExportPhotoReference>[_reference()]),
          includePhotos: true,
          photos: _Photos((_) => pending.future),
          photoReadTimeout: const Duration(milliseconds: 20),
        );
        expect(result.includedPhotos, isEmpty);
        expect(result.unavailablePhotos.single.reason, contains('timed out'));
        final List<int> original = await File(result.path).readAsBytes();
        if (lateError) {
          pending.completeError(StateError('late download failure'));
        } else {
          pending.complete(
            ArchivePhotoRead.available(Uint8List.fromList(<int>[1]), 'jpg'),
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(await File(result.path).readAsBytes(), original);
        await result.discard();
        expect(await directory.list().toList(), isEmpty);
      },
    );
  }

  test(
    'same-day preparations own separate immutable files and facts',
    () async {
      final PreparedFoodArchive first = await prepare(_snapshot(_data()));
      final List<int> original = await File(first.path).readAsBytes();
      final PreparedFoodArchive second = await prepare(
        _snapshot(<String, Object?>{}),
      );
      expect(first.name, second.name);
      expect(first.path, isNot(second.path));
      await second.discard();
      expect(await File(first.path).readAsBytes(), original);
      expect(first.files.clear, throwsUnsupportedError);
      expect(first.includedPhotos.clear, throwsUnsupportedError);
      expect(first.unavailablePhotos.clear, throwsUnsupportedError);
    },
  );
}

class _Export extends Fake implements DataExport {
  _Export(this.snapshot);
  final ExportSnapshot snapshot;
  @override
  Future<ExportSnapshot> prepare({
    required String householdId,
    required String userId,
  }) async => snapshot;
}

class _Photos implements ArchivePhotoReader {
  _Photos(this.action);
  final Future<ArchivePhotoRead> Function(ExportPhotoReference) action;
  int calls = 0;
  int active = 0;
  int maxActive = 0;
  @override
  Future<ArchivePhotoRead> read(
    ExportPhotoReference reference, {
    bool Function()? isCurrent,
  }) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return await action(reference);
    } finally {
      active--;
    }
  }
}

ExportPhotoReference _reference({
  String id = 'recipe-1',
  String home = 'home',
}) => ExportPhotoReference(
  householdId: home,
  recipeId: id,
  recipeTitle: 'Recipe',
  remotePath: '$id/object.jpg',
);

ExportSnapshot _snapshot(
  Map<String, Object?> data, {
  Map<String, bool> deleted = const <String, bool>{},
  List<ExportPhotoReference> photos = const <ExportPhotoReference>[],
}) => ExportSnapshot(
  file: ExportedFile(
    name: 'hearth-2026-10-01.json',
    contents: const JsonEncoder.withIndent('  ').convert(data),
  ),
  householdId: 'home',
  userId: 'me',
  capturedAt: DateTime.utc(2026, 10, 1, 12),
  counts: const <String, int>{},
  loggedDayStart: null,
  loggedDayEnd: null,
  pendingChanges: 2,
  exclusions: const <String>[],
  missingReferences: const <String>['food:missing'],
  entryDeletionStates: deleted,
  photoReferences: photos,
);

Map<String, Object?> _data() {
  final serving = aServing(
    id: 'serving',
    label: '100 g',
    amount: 100,
    unit: Units.gram,
    macros: Macros.zero,
  );
  final LoggedPortion portion = LoggedPortion.tryCapture(
    amount: 37.123456789,
    unit: const PortionUnit.raw(Units.gram),
    servings: 0.37123456789,
    standard: serving,
  )!;
  final Map<String, Object?> frozen = PlanMapper.snapshotToJson(
    MacroSnapshot(
      macros: const Macros(
        kcal: 90,
        proteinG: 3,
        carbG: 12,
        fatG: 2,
        sodiumMg: 0,
        cholesterolMg: 1,
      ),
      servings: portion.servings,
      capturedAt: DateTime.utc(2026),
      label: 'Old oats',
      loggedPortion: portion,
      coverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
        MinorNutrient.fiber: MinorCoverage.unknown,
        MinorNutrient.sodium: MinorCoverage.complete,
        MinorNutrient.cholesterol: MinorCoverage.partial,
      }),
      usesApproximatePackageNutrition: true,
    ),
  );
  frozen['captured_at'] = '2026-09-30T23:30:00-04:00';
  return <String, Object?>{
    'format': 'hearth-export',
    'version': 2,
    'meal_plan_days': <Object?>[
      <String, Object?>{'id': 'day', 'day': '2026-09-29'},
    ],
    'meal_plan_entries': <Object?>[
      <String, Object?>{
        'id': 'log',
        'meal_plan_day_id': 'day',
        'ref_type': 'food',
        'ref_id': 'food',
        'meal_slot': 'breakfast',
        'is_logged': true,
        'is_planned': false,
        'servings': portion.servings,
        'logged_at': '2026-10-01T01:00:00.000Z',
        'macro_snapshot': frozen,
      },
    ],
    'foods': <Object?>[
      <String, Object?>{
        'id': 'food',
        'name': 'New oats',
        'is_global': false,
        'serving_options': <Object?>[
          <String, Object?>{
            'id': 'serving',
            'label': '100 g',
            'amount_canonical': 100,
            'amount_kind': 'mass',
            'amount_unit': 'g',
            'kcal': 999,
          },
        ],
      },
    ],
  };
}

Map<String, Object?> _rawSnapshot(Map<String, Object?> data) =>
    ((data['meal_plan_entries']! as List<Object?>).single!
            as Map<String, Object?>)['macro_snapshot']!
        as Map<String, Object?>;

Future<Map<String, List<int>>> _unzip(PreparedFoodArchive prepared) async =>
    <String, List<int>>{
      for (final ArchiveFile file in ZipDecoder().decodeBytes(
        await File(prepared.path).readAsBytes(),
      ))
        file.name: file.readBytes()!,
    };

List<Map<String, String>> _csvRows(String source) {
  final String text = source.startsWith('\uFEFF')
      ? source.substring(1)
      : source;
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  StringBuffer cell = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (ch == ',' || ch == '\n')) {
      row.add(cell.toString());
      cell = StringBuffer();
      if (ch == '\n') {
        rows.add(row);
        row = <String>[];
      }
    } else if (quoted || ch != '\r') {
      cell.write(ch);
    }
  }
  if (rows.isEmpty) return <Map<String, String>>[];
  return <Map<String, String>>[
    for (final List<String> values in rows.skip(1))
      <String, String>{
        for (int i = 0; i < rows.first.length; i++) rows.first[i]: values[i],
      },
  ];
}
