import 'dart:async';

import 'package:hearth/data/adapters/archive_file_share.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/food_data_archive.dart';

/// Synthetic facts only: widget tests never create ZIPs or open OS sharing.
class TestFoodArchive extends PreparedFoodArchive {
  TestFoodArchive({
    super.name = 'hearth-readable-2026-10-01.zip',
    String householdId = 'household-1',
    String userId = 'user-1',
    bool photos = false,
    List<String> missing = const <String>[],
  }) : super(
         snapshot: ExportSnapshot(
           file: const ExportedFile(
             name: 'hearth-2026-10-01.json',
             contents: '{}',
           ),
           householdId: householdId,
           userId: userId,
           capturedAt: DateTime.utc(2026, 10, 1, 16),
           counts: const <String, int>{
             'recipes': 2,
             'foods': 5,
             'meal_plan_entries': 4,
             'logged_entries': 3,
             'planned_entries': 1,
             'macro_targets': 2,
           },
           loggedDayStart: DateTime.utc(2026, 9, 28),
           loggedDayEnd: DateTime.utc(2026, 9, 30),
           pendingChanges: 3,
           exclusions: const <String>[
             'Recipe photos are not included in the original JSON.',
             'Other household members’ private food data is not included.',
           ],
           missingReferences: missing,
         ),
         path: '/synthetic-test-only/$name',
         bytes: photos ? 180000 : 4200,
         files: <ArchiveFileFact>[
           const ArchiveFileFact(
             path: 'original/hearth-2026-10-01.json',
             bytes: 2,
           ),
           for (final String name in <String>[
             'logs.csv',
             'plans.csv',
             'targets.csv',
             'foods.csv',
             'recipes/01-chilli.txt',
             'recipes/02-soup.txt',
             'photos-unavailable.csv',
             'READ-ME.txt',
             'archive-manifest.json',
           ])
             ArchiveFileFact(path: name, bytes: 100),
           if (photos)
             const ArchiveFileFact(path: 'photos/01-chilli.jpg', bytes: 180000),
         ],
         photosRequested: photos,
         includedPhotos: photos
             ? const <ArchivePhotoFact>[
                 ArchivePhotoFact(
                   recipeId: 'chilli',
                   recipeTitle: 'Weeknight chilli',
                   path: 'photos/01-chilli.jpg',
                 ),
               ]
             : const <ArchivePhotoFact>[],
         unavailablePhotos: photos
             ? const <ArchivePhotoOmission>[
                 ArchivePhotoOmission(
                   recipeId: 'soup',
                   recipeTitle: 'Sunday soup',
                   reason: 'The photo is offline or unavailable.',
                 ),
               ]
             : const <ArchivePhotoOmission>[],
       );

  final List<Object?> _discardCalls = <Object?>[];
  int get discards => _discardCalls.length;
  @override
  Future<void> discard() async => _discardCalls.add(null);
}

class FakeFoodDataArchive implements FoodDataArchive {
  PreparedFoodArchive? next;
  final List<bool> photoRequests = <bool>[];
  final List<PreparedFoodArchive> prepared = <PreparedFoodArchive>[];
  Completer<PreparedFoodArchive>? gate;
  Object? failure;
  bool Function()? isCurrent;

  @override
  Future<PreparedFoodArchive> prepare({
    required String householdId,
    required String userId,
    bool includePhotos = false,
    void Function(ArchiveProgress)? onProgress,
    bool Function()? isCurrent,
  }) async {
    photoRequests.add(includePhotos);
    this.isCurrent = isCurrent;
    onProgress?.call(const ArchiveProgress(message: 'Preparing test archive'));
    if (failure case final Object error) throw error;
    final PreparedFoodArchive result =
        await (gate?.future ??
            Future.value(
              next ??
                  TestFoodArchive(
                    householdId: householdId,
                    userId: userId,
                    photos: includePhotos,
                  ),
            ));
    prepared.add(result);
    // Deliberately return even when cancelled: the screen also owns a stale
    // completion guard and must discard a result that arrives after Back.
    return result;
  }
}

class FakeArchiveFileShare implements ArchiveFileShare {
  final List<PreparedFoodArchive> archives = <PreparedFoodArchive>[];
  FileShareOutcome outcome = FileShareOutcome.actionSelected;
  Completer<FileShareOutcome>? gate;
  Object? failure;
  bool Function()? isCurrent;

  @override
  Future<FileShareOutcome> shareArchive(
    PreparedFoodArchive archive, {
    bool Function()? isCurrent,
  }) async {
    this.isCurrent = isCurrent;
    archives.add(archive);
    if (failure case final Object error) throw error;
    return gate?.future ?? outcome;
  }
}
