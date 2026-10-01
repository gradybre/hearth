import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/data_export.dart';
import '../../data/auth/auth_gateway.dart';
import 'export_review_sync.dart';
import 'settings_kit.dart';

/// Reviews a frozen local file. Only an explicit sync-and-refresh replaces it.
class ExportReviewScreen extends ConsumerStatefulWidget {
  const ExportReviewScreen({required this.snapshot, super.key});

  final ExportSnapshot snapshot;

  @override
  ConsumerState<ExportReviewScreen> createState() => _ExportReviewScreenState();
}

class _ExportReviewScreenState extends ConsumerState<ExportReviewScreen> {
  late ExportSnapshot _snapshot = widget.snapshot;
  ExportReviewSync? _sync;
  String? _busy;
  String? _message;
  bool _messageIsError = false;
  bool _expired = false;
  bool _sharing = false;
  FileShareOutcome? _receipt;
  int _pageVersion = 0;

  bool _matches(HearthAccount? account) =>
      account?.userId == _snapshot.userId &&
      account?.householdId == _snapshot.householdId;

  @override
  void initState() {
    super.initState();
    ref.listenManual(accountProvider, (_, AsyncValue<HearthAccount?> next) {
      // Once a change is seen, switching back cannot resurrect this review.
      if (next.hasValue && !_matches(next.value)) _expire();
    });
  }

  void _expire() {
    _sync?.cancel();
    if (mounted && !_expired) {
      setState(() {
        _expired = true;
        _pageVersion++;
      });
    }
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  bool _stillCurrent() {
    if (_expired || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    // The observed account includes the offline cache. currentAccount also
    // queries the server profile, which would make a local export need a
    // connection. Recheck this local identity at each async boundary instead.
    if (!_matches(ref.read(accountProvider).value)) {
      _expire();
      return false;
    }
    return true;
  }

  Future<void> _share() async {
    if (_busy != null || _expired) return;
    setState(() {
      _busy = 'Opening sharing…';
      _sharing = true;
      _message = null;
    });
    try {
      if (!_stillCurrent()) return;
      // No rebuild here: these exact immutable bytes are what was reviewed.
      final FileShareOutcome outcome = await ref
          .read(fileShareProvider)
          .share(_snapshot.file);
      if (mounted && !_expired) {
        setState(() {
          _receipt = outcome;
          _pageVersion++;
        });
      }
    } on Object {
      if (mounted && !_expired) {
        setState(() {
          _message =
              'Could not open sharing. Your reviewed file is still here; '
              'try exporting it again.';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _sharing = false;
        });
      }
    }
  }

  Future<void> _syncFirst() async {
    if (_busy != null || _expired) return;
    setState(() {
      _busy = 'Syncing before a fresh review…';
      _message = null;
    });
    try {
      if (!_stillCurrent()) return;
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
      final ExportSyncAttempt attempt = await sync.run(
        canSync: () =>
            mounted &&
            !_expired &&
            _matches(ref.read(accountProvider).value) &&
            ref.read(supabaseReadyProvider),
      );
      if (!_stillCurrent()) return;
      if (attempt.canRefresh) {
        setState(() => _busy = 'Refreshing this review…');
        final ExportSnapshot refreshed = await ref
            .read(dataExportProvider)
            .prepare(
              householdId: _snapshot.householdId,
              userId: _snapshot.userId,
            );
        if (!_stillCurrent()) return;
        setState(() {
          _snapshot = refreshed;
          _pageVersion++;
        });
      }
      if (!mounted || _expired) return;
      setState(() {
        _message =
            attempt.outcome == ExportSyncOutcome.failed && !attempt.canRefresh
            ? 'Sync could not start. This review is unchanged. Try Sync '
                  'first again, or export the file already reviewed.'
            : _syncMessage(attempt.outcome);
        _messageIsError = switch (attempt.outcome) {
          ExportSyncOutcome.failed ||
          ExportSyncOutcome.abandoned ||
          ExportSyncOutcome.timedOut => true,
          _ => false,
        };
      });
    } on Object {
      if (mounted && !_expired) {
        setState(() {
          _message =
              'Could not refresh this review. The earlier file is unchanged. '
              'Try Sync first again, or export the file already reviewed.';
          _messageIsError = true;
        });
      }
    } finally {
      _sync = null;
      if (mounted) setState(() => _busy = null);
    }
  }

  void _close() {
    _sync?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountProvider);
    return PopScope(
      canPop: !_sharing,
      child: SettingsPage(
        // A shorter receipt must not inherit the bottom of a long review.
        // Likewise, new snapshot facts need to be read from their beginning.
        key: ValueKey<int>(_pageVersion),
        // The long title belongs in the scroll view so large type can grow.
        title: 'Your data',
        children: switch ((_expired, _receipt)) {
          (true, _) => _expiredContent(context),
          (false, final FileShareOutcome outcome) => _receiptContent(
            context,
            outcome,
          ),
          _ => _reviewContent(context),
        },
      ),
    );
  }

  List<Widget> _expiredContent(BuildContext context) => <Widget>[
    _heading(context, 'Review expired'),
    const SizedBox(height: HearthSpacing.lg),
    const _ExportMessage(
      text:
          'Your account or household changed. Return to Your data and build '
          'a new review before exporting.',
      isError: true,
    ),
    const SizedBox(height: HearthSpacing.xl),
    FilledButton(onPressed: _close, child: const Text('Back to your data')),
  ];

  List<Widget> _reviewContent(BuildContext context) => <Widget>[
    _heading(context, 'Review food export'),
    const SizedBox(height: HearthSpacing.sm),
    Text(
      'A JSON copy of the food data held on this device. '
      'Nothing is shared until you choose Export this device now.',
      style: context.text.body,
    ),
    const SizedBox(height: HearthSpacing.xl),
    _ExportSection(
      title: 'This file',
      children: <Widget>[
        Text(_snapshot.file.name, style: context.text.body),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'Captured ${_captureTime(context, _snapshot.capturedAt)}',
          style: context.text.body,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'This snapshot stays fixed while you review it. Sync first makes '
          'a new review after the sync attempt finishes.',
          style: context.text.body,
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    const _ExportSection(
      title: 'Whose data is included',
      children: <Widget>[
        Text(
          'Your personal data: plans, logged meals, nutrition targets, saved '
          'weeks, favourites and food profile.',
        ),
        SizedBox(height: HearthSpacing.md),
        Text(
          'Your household’s shared data: recipes, foods, collections, shopping '
          'lists and ingredient matches. Referenced global foods and deleted '
          'records held on this device are included.',
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ExportSection(
      key: const Key('export-review-counts'),
      title: 'Records in this file',
      children: <Widget>[
        Text(
          'Counts include retained deleted records, so they may differ from '
          'your current library and plan. Planned and logged entries are '
          'parts of the total plan and log entries.',
          style: context.text.body,
        ),
        const SizedBox(height: HearthSpacing.md),
        for (final MapEntry<String, int> count in _snapshot.counts.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
            child: Text(
              '${_countLabel(count.key)}: ${count.value}',
              style: context.text.body,
            ),
          ),
        const SizedBox(height: HearthSpacing.md),
        Text(_loggedDays(context, _snapshot), style: context.text.body),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ExportSection(
      title: 'Device sync status at capture',
      children: <Widget>[
        _ExportMessage(
          text: _snapshot.pendingChanges == 0
              ? 'No unsynced changes were queued on this device. This does '
                    'not confirm that every record from the server is here.'
              : '${_snapshot.pendingChanges} unsynced '
                    '${_snapshot.pendingChanges == 1 ? 'change was' : 'changes were'} '
                    'queued across this device. This count is device-wide, '
                    'and may include changes outside this export.',
        ),
        const SizedBox(height: HearthSpacing.md),
        Text(
          'Records that have not reached this device are not in this file. '
          'You can sync first or export this local snapshot now.',
          style: context.text.body,
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ExportSection(
      key: const Key('export-review-exclusions'),
      title: 'Left out of this file',
      children: <Widget>[
        for (final String exclusion in _snapshot.exclusions)
          Padding(
            padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
            child: Text(exclusion, style: context.text.body),
          ),
        Text(
          'This is a JSON food-data export. It is not a full app backup, '
          'and Hearth cannot restore it into the app.',
          style: context.text.body,
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ExportSection(
      title: 'Reference check',
      children: <Widget>[
        if (_snapshot.localReferencesComplete)
          const Text('All local references in this file could be resolved.')
        else ...<Widget>[
          const _ExportMessage(
            text:
                'Some records point to data this device does not hold. '
                'These missing references are also listed in the file.',
            isError: true,
          ),
          const SizedBox(height: HearthSpacing.sm),
          for (final String reference in _snapshot.missingReferences)
            Padding(
              padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
              child: Text(reference, style: context.text.body),
            ),
        ],
      ],
    ),
    const SizedBox(height: HearthSpacing.xl),
    if (_message case final String message) ...<Widget>[
      _ExportMessage(text: message, isError: _messageIsError),
      const SizedBox(height: HearthSpacing.lg),
    ],
    if (_busy case final String busy) ...<Widget>[
      _ExportMessage(text: busy),
      const SizedBox(height: HearthSpacing.lg),
    ],
    OutlinedButton(
      onPressed: _busy == null ? _syncFirst : null,
      child: const Text('Sync first', textAlign: TextAlign.center),
    ),
    const SizedBox(height: HearthSpacing.md),
    FilledButton(
      key: const Key('export-review-share'),
      onPressed: _busy == null ? _share : null,
      child: const Text('Export this device now', textAlign: TextAlign.center),
    ),
    const SizedBox(height: HearthSpacing.md),
    TextButton(
      key: const Key('export-review-cancel'),
      onPressed: _sharing ? null : _close,
      child: const Text('Cancel'),
    ),
  ];

  List<Widget> _receiptContent(
    BuildContext context,
    FileShareOutcome outcome,
  ) => <Widget>[
    _heading(context, 'Export receipt'),
    const SizedBox(height: HearthSpacing.xl),
    _ExportSection(
      title: 'Reviewed file',
      children: <Widget>[
        Text(_snapshot.file.name, style: context.text.body),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          'Captured ${_captureTime(context, _snapshot.capturedAt)}',
          style: context.text.body,
        ),
      ],
    ),
    const SizedBox(height: HearthSpacing.lg),
    _ExportSection(
      title: switch (outcome) {
        FileShareOutcome.actionSelected => 'An export action was selected',
        FileShareOutcome.dismissed => 'Sharing was dismissed',
        FileShareOutcome.unavailable => 'The outcome is unavailable',
      },
      children: <Widget>[
        Text(switch (outcome) {
          FileShareOutcome.actionSelected =>
            'The operating system reported that an action was selected. '
                'It did not confirm that the file was saved or delivered. '
                'Check your chosen destination for the file.',
          FileShareOutcome.dismissed =>
            'The operating system reported that sharing was dismissed. '
                'Hearth has no confirmation of a saved or delivered copy.',
          FileShareOutcome.unavailable =>
            'This device did not report whether an export action was '
                'completed. Check your chosen destination before relying '
                'on a saved copy.',
        }, style: context.text.body),
      ],
    ),
    const SizedBox(height: HearthSpacing.xl),
    OutlinedButton(
      onPressed: () => setState(() {
        _receipt = null;
        _message = null;
        _pageVersion++;
      }),
      child: const Text('Review this file again', textAlign: TextAlign.center),
    ),
    const SizedBox(height: HearthSpacing.md),
    FilledButton(onPressed: _close, child: const Text('Done')),
  ];
}

Widget _heading(BuildContext context, String title) => Semantics(
  header: true,
  child: Text(title, style: context.text.sectionHeader),
);

class _ExportSection extends StatelessWidget {
  const _ExportSection({
    required this.title,
    required this.children,
    super.key,
  });

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

class _ExportMessage extends StatelessWidget {
  const _ExportMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: text,
    excludeSemantics: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          isError ? Icons.error_outline : Icons.info_outline,
          size: 20,
          color: isError ? context.colors.error : context.colors.textSecondary,
        ),
        const SizedBox(width: HearthSpacing.sm),
        Expanded(child: Text(text, style: context.text.body)),
      ],
    ),
  );
}

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
  if (start == end) return 'Logged day: ${words.formatShortDate(start)}.';
  return 'Logged days: ${words.formatShortDate(start)} to '
      '${words.formatShortDate(end)}.';
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
  'plan_templates' => 'Saved weeks',
  'collections' => 'Collections',
  'favorite_recipes' => 'Favourite recipes',
  'ingredient_matches' => 'Ingredient matches',
  'shopping_lists' => 'Shopping lists',
  'shopping_items' => 'Shopping items',
  'food_profiles' => 'Food profiles',
  _ => key.replaceAll('_', ' '),
};

String _syncMessage(ExportSyncOutcome outcome) => switch (outcome) {
  ExportSyncOutcome.finished =>
    'Sync finished. This review has been refreshed from this device.',
  ExportSyncOutcome.pending =>
    'Sync finished with changes still waiting. This review has been '
        'refreshed from this device.',
  ExportSyncOutcome.offline =>
    'Sync could not finish while offline. This review has been refreshed '
        'from this device; server data may still be missing.',
  ExportSyncOutcome.failed =>
    'Sync could not finish. This review has been refreshed from this device; '
        'server data may still be missing.',
  ExportSyncOutcome.abandoned =>
    'Sync was interrupted. This review is unchanged. Try Sync first again.',
  ExportSyncOutcome.notStarted =>
    'Sync is unavailable right now. This review is unchanged. '
        'You can still export the file already reviewed.',
  ExportSyncOutcome.timedOut =>
    'Sync has not finished yet. This review is unchanged. '
        'You can wait and try Sync first again, or export this earlier file.',
  ExportSyncOutcome.cancelled => 'This review is unchanged.',
};
