import 'data_export.dart';
import 'food_data_archive.dart';

/// Binary hand-off is separate from the existing standalone JSON contract.
abstract interface class ArchiveFileShare {
  Future<FileShareOutcome> shareArchive(
    PreparedFoodArchive archive, {
    bool Function()? isCurrent,
  });
}
