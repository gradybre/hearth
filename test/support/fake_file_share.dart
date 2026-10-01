import 'package:hearth/data/adapters/data_export.dart';

/// Records the exact reviewed file without touching an OS share sheet.
class FakeFileShare implements FileShare {
  FakeFileShare({this.outcome = FileShareOutcome.unavailable});

  final FileShareOutcome outcome;
  final List<ExportedFile> files = <ExportedFile>[];

  @override
  Future<FileShareOutcome> share(ExportedFile file) async {
    files.add(file);
    return outcome;
  }
}
