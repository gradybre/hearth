import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/data_export.dart';
import '../../data/adapters/food_data_archive.dart';
import '../../data/auth/auth_gateway.dart';
import 'export_review_sync.dart';
import 'settings_kit.dart';

/// Options, an immutable local archive review, then an explicit OS handoff.
class FoodArchiveScreen extends ConsumerStatefulWidget {
  const FoodArchiveScreen({required this.account, super.key});

  final HearthAccount account;

  @override
  ConsumerState<FoodArchiveScreen> createState() => _FoodArchiveScreenState();
}

class _FoodArchiveScreenState extends ConsumerState<FoodArchiveScreen> {
  PreparedFoodArchive? _archive;
  PreparedFoodArchive? _sharingArchive;
  bool _discardAfterShare = false;
  bool _includePhotos = false;
  bool _options = true;
  bool _expired = false;
  bool _closed = false;
  bool _error = false;
  String? _busy;
  String? _message;
  ArchiveProgress? _progress;
  FileShareOutcome? _receipt;
  ExportReviewSync? _sync;
  int _generation = 0;
  int _pageVersion = 0;

  bool _matches(HearthAccount? account) =>
      account?.userId == widget.account.userId &&
      account?.householdId == widget.account.householdId;

  @override
  void initState() {
    super.initState();
    ref.listenManual(accountProvider, (_, AsyncValue<HearthAccount?> next) {
      if (next.hasValue && !_matches(next.value)) _expire();
    });
  }

  void _expire() {
    if (_expired || !mounted || _closed) return;
    _generation++;
    _sync?.cancel();
    _release(_archive);
    setState(() {
      _expired = true;
      _archive = null;
      _receipt = null;
      _busy = _sharingArchive == null ? null : _busy;
      _pageVersion++;
    });
  }

  /// The share adapter first copies the prepared file. Keep its source alive
  /// even if an account change or route teardown occurs during that copy.
  void _release(PreparedFoodArchive? archive) {
    if (archive == null) return;
    if (identical(archive, _sharingArchive)) {
      _discardAfterShare = true;
    } else {
      unawaited(_discard(archive));
    }
  }

  Future<void> _discard(PreparedFoodArchive archive) async {
    try {
      await archive.discard();
    } on Object {
      // Temporary-file cleanup cannot change a platform sharing receipt.
    }
  }

  void _abandon() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _sync?.cancel();
    _release(_archive);
    _archive = null;
  }

  @override
  void dispose() {
    _abandon();
    super.dispose();
  }

  bool _current([int? operation]) {
    if (!mounted || _closed || _expired) return false;
    if (operation != null && operation != _generation) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    // The observed identity works offline; no server account lookup is needed.
    if (!_matches(ref.read(accountProvider).value)) {
      _expire();
      return false;
    }
    return true;
  }

  int _start(String message) {
    final int operation = ++_generation;
    setState(() {
      _busy = message;
      _message = null;
      _progress = null;
    });
    return operation;
  }

  void _finish(int operation) {
    if (mounted && !_closed && operation == _generation) {
      setState(() {
        _busy = null;
        _progress = null;
      });
    }
  }

  Future<bool> _buildReview(int operation) async {
    final PreparedFoodArchive result = await ref
        .read(foodDataArchiveProvider)
        .prepare(
          householdId: widget.account.householdId,
          userId: widget.account.userId,
          includePhotos: _includePhotos,
          isCurrent: () => _current(operation),
          onProgress: (ArchiveProgress progress) {
            if (_current(operation)) setState(() => _progress = progress);
          },
        );
    if (!_current(operation)) {
      await _discard(result);
      return false;
    }
    if (result.snapshot.userId != widget.account.userId ||
        result.snapshot.householdId != widget.account.householdId) {
      await _discard(result);
      throw StateError('Archive identity does not match this review.');
    }
    final PreparedFoodArchive? previous = _archive;
    setState(() {
      _archive = result;
      _includePhotos = result.photosRequested;
      _options = false;
      _receipt = null;
      _pageVersion++;
    });
    if (!identical(previous, result)) _release(previous);
    return true;
  }

  Future<void> _prepare() async {
    if (_busy != null || !_current()) return;
    final int operation = _start('Preparing archive…');
    try {
      await _buildReview(operation);
    } on ArchivePreparationCancelled {
      // Leaving this review cancels preparation without a handoff.
    } on Object {
      if (_current(operation)) {
        setState(() {
          _message =
              'Could not prepare the archive. Nothing has been shared. '
              'Try again${_archive == null ? '.' : ' or return to your earlier review.'}';
          _error = true;
        });
      }
    } finally {
      _finish(operation);
    }
  }

  Future<void> _share() async {
    final PreparedFoodArchive? archive = _archive;
    if (_busy != null || archive == null || _options || !_current()) return;
    final int operation = _start('Opening sharing…');
    _sharingArchive = archive;
    try {
      final FileShareOutcome outcome = await ref
          .read(archiveFileShareProvider)
          .shareArchive(archive, isCurrent: () => _current(operation));
      if (_current(operation)) {
        setState(() {
          _receipt = outcome;
          _pageVersion++;
        });
      }
    } on Object {
      if (_current(operation)) {
        setState(() {
          _message =
              'Could not open sharing. This reviewed archive is still '
              'here; try exporting it again.';
          _error = true;
        });
      }
    } finally {
      _sharingArchive = null;
      if (_discardAfterShare) {
        _discardAfterShare = false;
        await _discard(archive);
      }
      if (mounted && !_closed && _expired) setState(() => _busy = null);
      _finish(operation);
    }
  }

  Future<void> _syncFirst() async {
    if (_busy != null || !_current()) return;
    final int operation = _start('Syncing before a fresh review…');
    final ExportReviewSync sync = ExportReviewSync(
      readStatus: () => ref.read(syncControllerProvider),
      request: () => ref.read(syncControllerProvider.notifier).sync(),
      listen: (onStatus) {
        final subscription = ref.listenManual(
          syncControllerProvider,
          (_, next) => onStatus(next),
        );
        return subscription.close;
      },
    );
    _sync = sync;
    try {
      final ExportSyncAttempt attempt = await sync.run(
        canSync: () => _current(operation) && ref.read(supabaseReadyProvider),
      );
      if (!_current(operation)) return;
      if (attempt.canRefresh && !await _buildReview(operation)) return;
      if (!_current(operation)) return;
      setState(() {
        _message = _syncMessage(attempt);
        _error = switch (attempt.outcome) {
          ExportSyncOutcome.failed ||
          ExportSyncOutcome.abandoned ||
          ExportSyncOutcome.timedOut => true,
          _ => false,
        };
      });
    } on ArchivePreparationCancelled {
      // The user left or changed identity while making the new review.
    } on Object {
      if (_current(operation)) {
        setState(() {
          _message =
              'Could not refresh this review. The earlier archive is '
              'unchanged. Try Sync first again, or export the archive already reviewed.';
          _error = true;
        });
      }
    } finally {
      if (identical(_sync, sync)) _sync = null;
      _finish(operation);
    }
  }

  void _close() {
    if (_sharingArchive != null) return;
    _abandon();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountProvider);
    return PopScope(
      canPop: _sharingArchive == null,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop) _abandon();
      },
      child: SettingsPage(
        key: ValueKey<int>(_pageVersion),
        title: 'Your data',
        children: _expired
            ? <Widget>[
                _heading(context, 'Review expired'),
                const SizedBox(height: HearthSpacing.lg),
                const SettingsMessage(
                  text:
                      'Your account or household changed. Return to Your data '
                      'and prepare a new archive before exporting.',
                  isError: true,
                ),
                const SizedBox(height: HearthSpacing.lg),
                FilledButton(
                  onPressed: _sharingArchive == null ? _close : null,
                  child: const Text('Back to your data'),
                ),
              ]
            : _receipt != null
            ? _receiptContent(_archive!, _receipt!)
            : _options || _archive == null
            ? _optionsContent()
            : _reviewContent(_archive!),
      ),
    );
  }

  List<Widget> _optionsContent() => <Widget>[
    _heading(context, 'Readable food archive'),
    const SizedBox(height: HearthSpacing.md),
    const Text(
      'A ZIP you can open outside Hearth: your original JSON, '
      'spreadsheet-friendly logs, plans, targets and foods, readable recipes, '
      'and a guide to the contents.',
    ),
    const SizedBox(height: HearthSpacing.lg),
    const _ArchiveSection(
      title: 'Your copy includes',
      children: <Widget>[
        Text(
          'Your personal food data and your household’s shared library and '
          'shopping data. Your partner’s private diary is left out.',
        ),
        SizedBox(height: HearthSpacing.md),
        Text(
          'Saved log names, portions and nutrition stay as they were recorded. '
          'This is a food-data copy; Hearth cannot restore it into the app.',
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    SettingsGroup(
      children: <Widget>[
        Material(
          color: context.colors.surface,
          child: CheckboxListTile(
            key: const Key('archive-include-photos'),
            value: _includePhotos,
            onChanged: _busy == null
                ? (bool? value) =>
                      setState(() => _includePhotos = value ?? false)
                : null,
            title: const Text('Include recipe photos'),
            controlAffinity: ListTileControlAffinity.leading,
            isThreeLine: false,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(HearthSpacing.lg),
          child: Text(
            'May download photos from household storage and make a '
            'larger file. Missing or offline photos will be listed in the review.',
          ),
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    const Text(
      'Prepare first, then review the contents before choosing where '
      'the archive goes. Nothing is shared yet.',
    ),
    ..._status(),
    FilledButton(
      key: const Key('archive-prepare'),
      onPressed: _busy == null ? _prepare : null,
      child: const Text('Prepare archive', textAlign: TextAlign.center),
    ),
    if (_archive != null) ...<Widget>[
      const SizedBox(height: HearthSpacing.md),
      OutlinedButton(
        onPressed: _busy == null
            ? () => setState(() {
                _includePhotos = _archive!.photosRequested;
                _options = false;
                _message = null;
                _pageVersion++;
              })
            : null,
        child: const Text(
          'Return to reviewed archive',
          textAlign: TextAlign.center,
        ),
      ),
    ],
    const SizedBox(height: HearthSpacing.md),
    TextButton(onPressed: _close, child: const Text('Cancel')),
  ];

  List<Widget> _reviewContent(PreparedFoodArchive archive) {
    final ExportSnapshot snapshot = archive.snapshot;
    return <Widget>[
      _heading(context, 'Review food archive'),
      const SizedBox(height: HearthSpacing.md),
      _ArchiveSection(
        title: 'This prepared file',
        children: <Widget>[
          Text(archive.name),
          const SizedBox(height: HearthSpacing.sm),
          Text('${_size(archive.bytes)} · ${archive.files.length} files'),
          Text('Captured ${_captureTime(context, snapshot.capturedAt)}'),
          const SizedBox(height: HearthSpacing.md),
          const Text(
            'These contents stay fixed while you review them. Export '
            'shares this exact archive; Sync first prepares a new review.',
          ),
        ],
      ),
      const SizedBox(height: HearthSpacing.lg),
      _ArchiveSection(
        title: 'Inside the ZIP',
        children: <Widget>[
          const Text(
            'Original JSON · logs.csv · plans.csv · targets.csv · '
            'foods.csv · readable recipe files · contents guide and manifest',
          ),
          const SizedBox(height: HearthSpacing.md),
          for (final MapEntry<String, int> count in snapshot.counts.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
              child: Text('${_countLabel(count.key)}: ${count.value}'),
            ),
          Text(_loggedDays(context, snapshot)),
          const SizedBox(height: HearthSpacing.md),
          const Text(
            'Counts include any deleted records retained on this device. '
            'Deleted plans and logs that are no longer cached are unavailable. '
            'Planned and logged entries are parts of the total plan and log entries. '
            'The spreadsheets label local record status.',
          ),
        ],
      ),
      const SizedBox(height: HearthSpacing.lg),
      _ArchiveSection(
        title: 'Recipe photos',
        children: <Widget>[
          if (!archive.photosRequested)
            const Text('Not requested. This archive contains no recipe photos.')
          else ...<Widget>[
            Text(
              '${archive.includedPhotos.length} included · '
              '${archive.unavailablePhotos.length} unavailable',
            ),
            if (archive.includedPhotos.isEmpty &&
                archive.unavailablePhotos.isEmpty)
              const Text('No recipe photos were recorded in this snapshot.'),
            for (final ArchivePhotoOmission photo in archive.unavailablePhotos)
              Padding(
                padding: const EdgeInsets.only(top: HearthSpacing.md),
                child: Text('${photo.recipeTitle}: ${photo.reason}'),
              ),
            const SizedBox(height: HearthSpacing.md),
            const Text(
              'Photos are separate files in this ZIP. The unchanged '
              'original JSON contains photo references only. Unavailable '
              'photos are also listed in photos-unavailable.csv.',
            ),
          ],
        ],
      ),
      const SizedBox(height: HearthSpacing.lg),
      _ArchiveSection(
        title: 'Whose data and what is left out',
        children: <Widget>[
          const Text(
            'Your personal plans, logs, targets, saved weeks, favourites '
            'and food profile; your household’s shared recipes, foods, '
            'collections, shopping data and ingredient matches.',
          ),
          const SizedBox(height: HearthSpacing.md),
          for (final String exclusion in snapshot.exclusions)
            if (!exclusion.toLowerCase().startsWith('recipe photos'))
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                child: Text(exclusion),
              ),
          const Text(
            'This is a food-data copy, not a full app backup. Hearth '
            'cannot restore it into the app.',
          ),
        ],
      ),
      const SizedBox(height: HearthSpacing.lg),
      _ArchiveSection(
        title: 'This device at capture',
        children: <Widget>[
          Text(
            snapshot.pendingChanges == 0
                ? 'No unsynced changes were queued on this device. This does not '
                      'confirm that every record from the server is here.'
                : '${snapshot.pendingChanges} unsynced changes were queued across '
                      'this device. Some may be outside this archive.',
          ),
          const SizedBox(height: HearthSpacing.md),
          const Text(
            'Records that have not reached this device are not in the '
            'archive. You can sync first or export this local copy.',
          ),
          const SizedBox(height: HearthSpacing.md),
          if (snapshot.localReferencesComplete)
            const Text(
              'All local references in this snapshot could be resolved.',
            )
          else ...<Widget>[
            const SettingsMessage(
              text:
                  'Some referenced records are missing on '
                  'this device. They are listed here and in the original JSON.',
              isError: true,
            ),
            for (final String reference in snapshot.missingReferences)
              Text(reference),
          ],
        ],
      ),
      ..._status(),
      OutlinedButton(
        onPressed: _busy == null ? _syncFirst : null,
        child: const Text('Sync first'),
      ),
      const SizedBox(height: HearthSpacing.md),
      FilledButton(
        key: const Key('archive-share'),
        onPressed: _busy == null ? _share : null,
        child: const Text(
          'Export reviewed archive',
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: HearthSpacing.md),
      TextButton(
        onPressed: _busy == null
            ? () => setState(() {
                _options = true;
                _message = null;
                _pageVersion++;
              })
            : null,
        child: const Text('Change options'),
      ),
      TextButton(
        onPressed: _sharingArchive == null ? _close : null,
        child: const Text('Cancel'),
      ),
    ];
  }

  List<Widget> _status() => <Widget>[
    const SizedBox(height: HearthSpacing.lg),
    if (_message case final String message) ...<Widget>[
      SettingsMessage(text: message, isError: _error),
      const SizedBox(height: HearthSpacing.lg),
    ],
    if (_busy case final String busy) ...<Widget>[
      SettingsMessage(
        isError: false,
        text: _progress == null
            ? busy
            : '${_progress!.message}${_progress!.totalPhotos == 0 ? '' : ' · ${_progress!.completedPhotos} of ${_progress!.totalPhotos}'}',
      ),
      const SizedBox(height: HearthSpacing.lg),
    ],
  ];

  List<Widget> _receiptContent(
    PreparedFoodArchive archive,
    FileShareOutcome outcome,
  ) => <Widget>[
    _heading(context, 'Archive export receipt'),
    const SizedBox(height: HearthSpacing.lg),
    _ArchiveSection(
      title: 'Reviewed archive',
      children: <Widget>[
        Text(archive.name),
        Text('${_size(archive.bytes)} · ${archive.files.length} files'),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ArchiveSection(
      title: switch (outcome) {
        FileShareOutcome.actionSelected => 'An export action was selected',
        FileShareOutcome.dismissed => 'Sharing was dismissed',
        FileShareOutcome.unavailable => 'The outcome is unavailable',
      },
      children: <Widget>[
        Text(switch (outcome) {
          FileShareOutcome.actionSelected =>
            'The operating system reported that '
                'an action was selected. It did not confirm the file was saved or '
                'delivered. Check your chosen destination for the archive.',
          FileShareOutcome.dismissed =>
            'The operating system reported that '
                'sharing was dismissed. Hearth has no confirmation of a saved or delivered copy.',
          FileShareOutcome.unavailable =>
            'This device did not report whether an '
                'export action was completed. Check your chosen destination before '
                'relying on a saved copy.',
        }),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    OutlinedButton(
      onPressed: () => setState(() {
        _receipt = null;
        _message = null;
        _pageVersion++;
      }),
      child: const Text('Review archive again', textAlign: TextAlign.center),
    ),
    const SizedBox(height: HearthSpacing.md),
    FilledButton(onPressed: _close, child: const Text('Done')),
  ];
}

Widget _heading(BuildContext context, String title) => Semantics(
  header: true,
  child: Text(title, style: context.text.sectionHeader),
);

class _ArchiveSection extends StatelessWidget {
  const _ArchiveSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: context.text.label),
            const SizedBox(height: HearthSpacing.md),
            ...children,
          ],
        ),
      ),
    ],
  );
}

String _size(int bytes) => bytes < 1024
    ? '$bytes bytes'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

String _captureTime(BuildContext context, DateTime capturedAt) {
  final DateTime local = capturedAt.toLocal();
  final MaterialLocalizations words = MaterialLocalizations.of(context);
  return '${words.formatShortDate(local)} at '
      '${words.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _loggedDays(BuildContext context, ExportSnapshot snapshot) {
  final DateTime? start = snapshot.loggedDayStart;
  final DateTime? end = snapshot.loggedDayEnd;
  if (start == null || end == null) return 'Logged days: none on this device.';
  final MaterialLocalizations words = MaterialLocalizations.of(context);
  return start == end
      ? 'Logged day: ${words.formatShortDate(start)}.'
      : 'Logged days: ${words.formatShortDate(start)} to ${words.formatShortDate(end)}.';
}

String _countLabel(String key) => switch (key) {
  'recipes' => 'Recipes',
  'foods' => 'Foods',
  'global_foods_referenced' => 'Referenced global foods (within foods)',
  'meal_plan_days' => 'Plan days',
  'meal_plan_entries' => 'Plan and log entries',
  'logged_entries' => 'Logged entries',
  'planned_entries' => 'Planned entries',
  'macro_targets' => 'Nutrition targets',
  'ongoing_macro_targets' => 'Ongoing target decisions',
  'plan_templates' => 'Saved weeks',
  'collections' => 'Collections',
  'favorite_recipes' => 'Favourite recipes',
  'ingredient_matches' => 'Ingredient matches',
  'shopping_lists' => 'Shopping lists',
  'shopping_items' => 'Shopping items',
  'food_profiles' => 'Food profiles',
  _ => key.replaceAll('_', ' '),
};

String _syncMessage(ExportSyncAttempt attempt) {
  if (!attempt.canRefresh) {
    return 'Sync ${switch (attempt.outcome) {
      ExportSyncOutcome.timedOut => 'has not finished yet',
      ExportSyncOutcome.abandoned => 'was interrupted',
      ExportSyncOutcome.failed => 'could not start',
      _ => 'is unavailable right now',
    }}. This review is unchanged. Try Sync first again, or export the archive already reviewed.';
  }
  return switch (attempt.outcome) {
    ExportSyncOutcome.finished =>
      'Sync finished. This review has been refreshed from this device.',
    ExportSyncOutcome.pending => 'Sync finished with changes still waiting. This review has been refreshed from this device.',
    _ => 'Sync could not finish. This review has been refreshed from this device; server data may still be missing.',
  };
}
