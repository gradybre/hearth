import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/features/account/export_review_screen.dart';
import 'package:hearth/features/account/settings_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/fake_auth.dart';

ExportSnapshot snapshot({
  String name = 'hearth-2026-10-01.json',
  String contents = '{"reviewed": true}',
  int recipes = 2,
  int pending = 3,
  bool logged = true,
  List<String> missing = const <String>[],
}) => ExportSnapshot(
  file: ExportedFile(name: name, contents: contents),
  householdId: 'household-1',
  userId: 'user-1',
  capturedAt: DateTime.utc(2026, 10, 1, 16),
  counts: <String, int>{
    'recipes': recipes,
    'foods': 5,
    'global_foods_referenced': 1,
    'meal_plan_entries': 4,
    'logged_entries': logged ? 3 : 0,
    'planned_entries': 1,
  },
  loggedDayStart: logged ? DateTime.utc(2026, 9, 28) : null,
  loggedDayEnd: logged ? DateTime.utc(2026, 9, 30) : null,
  pendingChanges: pending,
  exclusions: const <String>[
    'Recipe photos are not included.',
    'Other household members’ private food data is not included.',
  ],
  missingReferences: missing,
);

class ReviewAuth extends FakeAuthGateway {
  ReviewAuth({this.offline = false});

  final bool offline;
  HearthAccount? account = FakeAuthGateway.anAccount;
  final StreamController<HearthAccount?> changes =
      StreamController<HearthAccount?>.broadcast(sync: true);

  @override
  Stream<HearthAccount?> watchAccount() async* {
    yield account;
    yield* changes.stream;
  }

  void change(HearthAccount? next) {
    account = next;
    changes.add(next);
  }

  @override
  Future<HearthAccount?> currentAccount() async {
    if (offline) throw const SocketException('private network diagnostics');
    return account;
  }
}

class ReviewExport extends DataExport {
  ReviewExport(HearthDatabase db, this.next)
    : super(database: db, recipes: RecipeStore(db), foods: FoodStore(db));

  ExportSnapshot next;
  int prepares = 0;
  Completer<void>? gate;
  Object? failure;

  @override
  Future<ExportSnapshot> prepare({
    required String householdId,
    required String userId,
  }) async {
    prepares++;
    await gate?.future;
    if (failure case final Object error) throw error;
    return next;
  }
}

class ReviewShare implements FileShare {
  ReviewShare({this.outcome = FileShareOutcome.actionSelected});

  FileShareOutcome outcome;
  final List<ExportedFile> files = <ExportedFile>[];
  Completer<FileShareOutcome>? gate;
  Object? failure;

  @override
  Future<FileShareOutcome> share(ExportedFile file) async {
    files.add(file);
    if (failure case final Object error) throw error;
    return gate?.future ?? outcome;
  }
}

class ReviewSync extends FakeSyncController {
  ReviewSync({this.initial = const SyncStatus.idle()});

  final SyncStatus initial;
  int requests = 0;
  Completer<void>? gate;
  bool noOp = false;
  bool throwBeforeStart = false;
  SyncStatus result = const SyncStatus.done(
    SyncResult(pushed: 0, failed: 0, stillQueued: 0),
    pulled: PullResult(applied: 0, skipped: 0),
  );

  @override
  SyncStatus build() => initial;

  void emit(SyncStatus next) => state = next;

  @override
  Future<void> sync() async {
    requests++;
    if (throwBeforeStart) throw StateError('private sync diagnostics');
    if (noOp) return;
    state = const SyncStatus.syncing();
    await gate?.future;
    state = result;
  }
}

class ReviewHarness {
  ReviewHarness(this.auth, this.export, this.share, this.sync);
  final ReviewAuth auth;
  final ReviewExport export;
  final ReviewShare share;
  final ReviewSync sync;
}

Future<ReviewHarness> pumpReview(
  WidgetTester tester, {
  ReviewAuth? auth,
  ReviewShare? share,
  ReviewSync? sync,
  ExportSnapshot? initial,
  bool settings = false,
  bool routed = false,
  bool ready = true,
  bool dark = false,
  Size size = const Size(500, 2200),
  double scale = 1,
  Completer<void>? prepareGate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final ReviewAuth gateway = auth ?? ReviewAuth();
  addTearDown(gateway.changes.close);
  final ExportSnapshot first = initial ?? snapshot();
  final ReviewExport export = ReviewExport(db, first)..gate = prepareGate;
  final ReviewShare sharing = share ?? ReviewShare();
  final ReviewSync syncing = sync ?? ReviewSync();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authGatewayProvider.overrideWithValue(gateway),
        dataExportProvider.overrideWithValue(export),
        fileShareProvider.overrideWithValue(sharing),
        syncControllerProvider.overrideWith(() => syncing),
        supabaseReadyProvider.overrideWithValue(ready),
      ],
      child: MaterialApp(
        theme: dark ? HearthTheme.dark() : HearthTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: routed
            ? Builder(
                builder: (BuildContext context) => Scaffold(
                  body: FilledButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const DataSettingsScreen(),
                      ),
                    ),
                    child: const Text('Open data'),
                  ),
                ),
              )
            : settings
            ? const DataSettingsScreen()
            : ExportReviewScreen(snapshot: first),
      ),
    ),
  );
  await pumpFrames(tester);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(syncControllerProvider);
  if (routed) {
    await reach(tester, 'Open data');
    await tester.pumpAndSettle();
  }
  return ReviewHarness(gateway, export, sharing, syncing);
}

Future<void> bring(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      450,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 100,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> reach(WidgetTester tester, String text) async {
  final Finder finder = find.text(text);
  await bring(tester, finder);
  await tester.tap(finder);
  await pumpFrames(tester);
}

void main() {
  testWidgets(
    'back during preparation cannot open review on the departed page',
    (WidgetTester tester) async {
      final Completer<void> prepared = Completer<void>();
      final ReviewHarness harness = await pumpReview(
        tester,
        routed: true,
        prepareGate: prepared,
      );
      await reach(tester, 'Export food data (JSON)');
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 20));
      prepared.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open data'), findsOneWidget);
      expect(find.text('Review food export'), findsNothing);
      expect(harness.share.files, isEmpty);
    },
  );

  testWidgets('review explains the captured scope, counts and local gaps', (
    WidgetTester tester,
  ) async {
    await pumpReview(
      tester,
      initial: snapshot(missing: <String>['foods/missing-food-id']),
    );
    expect(find.text('hearth-2026-10-01.json'), findsOneWidget);
    final Text capture = tester.widget<Text>(find.textContaining('Captured '));
    expect(capture.data, contains('Oct 1'));
    expect(capture.data, contains('2026'));
    expect(find.textContaining('Your personal data:'), findsOneWidget);
    expect(
      find.textContaining('Your household’s shared data:'),
      findsOneWidget,
    );
    expect(find.text('Recipes: 2'), findsOneWidget);
    expect(find.text('Logged entries: 3'), findsOneWidget);
    expect(find.textContaining('Logged days:'), findsOneWidget);
    expect(find.textContaining('Sep 28'), findsOneWidget);
    expect(find.textContaining('Sep 30'), findsOneWidget);
    expect(find.textContaining('device-wide'), findsOneWidget);
    await bring(tester, find.text('foods/missing-food-id'));
    expect(find.textContaining('not a full app backup'), findsOneWidget);
    expect(find.textContaining('cannot restore it'), findsOneWidget);
  });

  testWidgets('empty local queue is not presented as a complete account', (
    WidgetTester tester,
  ) async {
    await pumpReview(tester, initial: snapshot(pending: 0, logged: false));
    expect(find.text('Logged days: none on this device.'), findsOneWidget);
    await bring(tester, find.textContaining('No unsynced changes'));
    expect(find.textContaining('does not confirm'), findsOneWidget);
    expect(find.textContaining('up to date'), findsNothing);
  });

  testWidgets('preparing offline opens review without an external handoff', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(
      tester,
      settings: true,
      auth: ReviewAuth(offline: true),
    );
    await reach(tester, 'Export food data (JSON)');
    expect(find.text('Review food export'), findsOneWidget);
    expect(harness.export.prepares, 1);
    expect(harness.share.files, isEmpty);
  });

  testWidgets('cancel returns to data settings without sharing', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(tester, settings: true);
    await reach(tester, 'Export food data (JSON)');
    await reach(tester, 'Cancel');
    expect(find.text('Export food data (JSON)'), findsOneWidget);
    expect(harness.share.files, isEmpty);
  });

  testWidgets(
    'local and background sync updates cannot replace reviewed bytes',
    (WidgetTester tester) async {
      final ExportSnapshot first = snapshot();
      final ReviewHarness harness = await pumpReview(tester, initial: first);
      harness.export.next = snapshot(recipes: 19, contents: '{"later": true}');
      // A background sync ending is not the review's explicit refresh action.
      harness.sync.emit(harness.sync.result);
      await pumpFrames(tester);
      await reach(tester, 'Export this device now');
      expect(harness.export.prepares, 0);
      expect(harness.share.files.single, same(first.file));
    },
  );

  testWidgets('repeated taps prepare once and open sharing once', (
    WidgetTester tester,
  ) async {
    final Completer<void> prepared = Completer<void>();
    final Completer<FileShareOutcome> shared = Completer<FileShareOutcome>();
    final ReviewHarness harness = await pumpReview(
      tester,
      settings: true,
      prepareGate: prepared,
      share: ReviewShare()..gate = shared,
    );
    final Finder prepare = find.text('Export food data (JSON)');
    await tester.tap(prepare);
    await tester.tap(prepare);
    expect(harness.export.prepares, 1);
    prepared.complete();
    await pumpFrames(tester);
    await bring(tester, find.text('Export this device now'));
    await tester.tap(find.text('Export this device now'));
    await tester.tap(find.text('Export this device now'));
    expect(harness.share.files, hasLength(1));
    shared.complete(FileShareOutcome.actionSelected);
    await pumpFrames(tester);
    expect(find.text('Export receipt'), findsOneWidget);
  });

  for (final MapEntry<String, HearthAccount?> change
      in <String, HearthAccount?>{
        'sign-out': null,
        'household change': const HearthAccount(
          userId: 'user-1',
          householdId: 'household-2',
          email: 'cook@example.com',
        ),
        'account change': const HearthAccount(
          userId: 'user-2',
          householdId: 'household-1',
          email: 'other@example.com',
        ),
      }.entries) {
    testWidgets('${change.key} expires a review, even if the account returns', (
      WidgetTester tester,
    ) async {
      final ReviewHarness harness = await pumpReview(tester);
      await bring(tester, find.text('Export this device now'));
      harness.auth.change(change.value);
      await pumpFrames(tester);
      harness.auth.change(FakeAuthGateway.anAccount);
      await pumpFrames(tester);
      expect(find.text('Review expired').hitTestable(), findsOneWidget);
      expect(find.text('Export this device now'), findsNothing);
      expect(harness.share.files, isEmpty);
    });
  }

  testWidgets('scope changes while preparing cannot resurrect an old review', (
    WidgetTester tester,
  ) async {
    final Completer<void> prepared = Completer<void>();
    final ReviewHarness harness = await pumpReview(
      tester,
      settings: true,
      prepareGate: prepared,
    );
    await reach(tester, 'Export food data (JSON)');
    harness.auth.change(null);
    await pumpFrames(tester);
    harness.auth.change(FakeAuthGateway.anAccount);
    await pumpFrames(tester);
    prepared.complete();
    await pumpFrames(tester);
    expect(find.text('Review food export'), findsNothing);
    expect(find.textContaining('Build a new review'), findsOneWidget);
    expect(harness.share.files, isEmpty);
  });

  testWidgets(
    'a preparation failure is safe to retry without raw diagnostics',
    (WidgetTester tester) async {
      final ReviewHarness harness = await pumpReview(tester, settings: true);
      harness.export.failure = StateError('private database diagnostics');
      await reach(tester, 'Export food data (JSON)');
      expect(find.textContaining('Could not prepare'), findsOneWidget);
      expect(find.textContaining('private database diagnostics'), findsNothing);
      expect(harness.share.files, isEmpty);
      harness.export.failure = null;
      await reach(tester, 'Export food data (JSON)');
      expect(find.text('Review food export'), findsOneWidget);
      expect(harness.export.prepares, 2);
      expect(harness.share.files, isEmpty);
    },
  );

  testWidgets(
    'sync refreshes only after the pass completes and requires review',
    (WidgetTester tester) async {
      final Completer<void> synced = Completer<void>();
      final ReviewHarness harness = await pumpReview(
        tester,
        sync: ReviewSync()..gate = synced,
        size: const Size(320, 568),
        scale: 3,
      );
      final ExportSnapshot refreshed = snapshot(recipes: 7);
      harness.export.next = refreshed;
      await reach(tester, 'Sync first');
      expect(harness.export.prepares, 0);
      expect(harness.share.files, isEmpty);
      synced.complete();
      await tester.pumpAndSettle();
      expect(harness.export.prepares, 1);
      expect(find.text('Review food export').hitTestable(), findsOneWidget);
      await bring(tester, find.text('Recipes: 7'));
      expect(harness.share.files, isEmpty);
      await reach(tester, 'Export this device now');
      expect(harness.share.files.single, same(refreshed.file));
    },
  );

  testWidgets(
    'a sync no-op keeps the file and does not claim it is up to date',
    (WidgetTester tester) async {
      final ExportSnapshot first = snapshot();
      final ReviewHarness harness = await pumpReview(
        tester,
        initial: first,
        sync: ReviewSync()..noOp = true,
      );
      await reach(tester, 'Sync first');
      expect(harness.export.prepares, 0);
      expect(find.textContaining('This review is unchanged'), findsOneWidget);
      expect(find.textContaining('up to date'), findsNothing);
      await reach(tester, 'Export this device now');
      expect(harness.share.files.single, same(first.file));
    },
  );

  for (final MapEntry<SyncStatus, String> result in <SyncStatus, String>{
    const SyncStatus.done(
      SyncResult(pushed: 0, failed: 0, stillQueued: 0),
      pulled: PullResult(applied: 0, skipped: 0, stoppedBecauseOffline: true),
    ): 'Sync could not finish while offline',
    const SyncStatus.failed('private sync diagnostics'):
        'Sync could not finish.',
  }.entries) {
    testWidgets(
      '${result.value} refreshes local data without claiming success',
      (WidgetTester tester) async {
        final ReviewHarness harness = await pumpReview(
          tester,
          sync: ReviewSync()..result = result.key,
        );
        await reach(tester, 'Sync first');
        expect(harness.export.prepares, 1);
        await bring(tester, find.textContaining(result.value));
        expect(
          find.textContaining('server data may still be missing'),
          findsOneWidget,
        );
        expect(find.textContaining('private sync diagnostics'), findsNothing);
        expect(harness.share.files, isEmpty);
      },
    );
  }

  testWidgets('an abandoned sync leaves the earlier reviewed file in place', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(
      tester,
      sync: ReviewSync()
        ..result = const SyncStatus.done(
          SyncResult(pushed: 0, failed: 0, stillQueued: 0),
          pulled: PullResult(applied: 0, skipped: 0, abandonedScope: true),
        ),
    );
    await reach(tester, 'Sync first');
    expect(harness.export.prepares, 0);
    expect(find.textContaining('Sync was interrupted'), findsOneWidget);
  });

  testWidgets('scope changes during sync expire instead of refreshing', (
    WidgetTester tester,
  ) async {
    final Completer<void> synced = Completer<void>();
    final ReviewHarness harness = await pumpReview(
      tester,
      sync: ReviewSync()..gate = synced,
    );
    await reach(tester, 'Sync first');
    harness.auth.change(null);
    await pumpFrames(tester);
    synced.complete();
    await pumpFrames(tester);
    expect(find.text('Review expired'), findsOneWidget);
    expect(harness.export.prepares, 0);
    expect(harness.share.files, isEmpty);
  });

  testWidgets(
    'cancel during sync cannot reopen review when the pass finishes',
    (WidgetTester tester) async {
      final Completer<void> synced = Completer<void>();
      final ReviewHarness harness = await pumpReview(
        tester,
        settings: true,
        sync: ReviewSync()..gate = synced,
      );
      await reach(tester, 'Export food data (JSON)');
      await reach(tester, 'Sync first');
      await reach(tester, 'Cancel');
      synced.complete();
      await tester.pumpAndSettle();
      expect(find.text('Export food data (JSON)'), findsOneWidget);
      expect(find.text('Review food export'), findsNothing);
      expect(harness.export.prepares, 1);
      expect(harness.share.files, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed refresh retains the file and can be retried', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(tester);
    harness.export.failure = StateError('private refresh diagnostics');
    await reach(tester, 'Sync first');
    expect(
      find.textContaining('The earlier file is unchanged'),
      findsOneWidget,
    );
    expect(find.textContaining('private refresh diagnostics'), findsNothing);
    final ExportSnapshot refreshed = snapshot(recipes: 8);
    harness.export
      ..failure = null
      ..next = refreshed;
    await reach(tester, 'Sync first');
    await reach(tester, 'Export this device now');
    expect(harness.share.files.single, same(refreshed.file));
  });

  testWidgets('sharing failure keeps the exact file available for a retry', (
    WidgetTester tester,
  ) async {
    final ExportSnapshot first = snapshot();
    final ReviewHarness harness = await pumpReview(
      tester,
      initial: first,
      share: ReviewShare()..failure = StateError('private share diagnostics'),
    );
    await reach(tester, 'Export this device now');
    expect(find.textContaining('Could not open sharing'), findsOneWidget);
    expect(find.textContaining('private share diagnostics'), findsNothing);
    harness.share.failure = null;
    await reach(tester, 'Export this device now');
    expect(harness.share.files, <ExportedFile>[first.file, first.file]);
    expect(harness.export.prepares, 0);
    expect(find.text('Export receipt'), findsOneWidget);
  });

  for (final MapEntry<FileShareOutcome, String> outcome
      in <FileShareOutcome, String>{
        FileShareOutcome.actionSelected: 'An export action was selected',
        FileShareOutcome.dismissed: 'Sharing was dismissed',
        FileShareOutcome.unavailable: 'The outcome is unavailable',
      }.entries) {
    testWidgets(
      'receipt reports ${outcome.key.name} without claiming a saved file',
      (WidgetTester tester) async {
        final ReviewHarness harness = await pumpReview(
          tester,
          settings: true,
          share: ReviewShare(outcome: outcome.key),
        );
        await reach(tester, 'Export food data (JSON)');
        await reach(tester, 'Export this device now');
        expect(find.text('Export receipt'), findsOneWidget);
        expect(find.text('hearth-2026-10-01.json'), findsOneWidget);
        expect(find.text(outcome.value), findsOneWidget);
        expect(find.text('Export complete'), findsNothing);
        expect(find.text('File saved'), findsNothing);
        await reach(tester, 'Done');
        expect(find.text('Export food data (JSON)'), findsOneWidget);
        expect(harness.share.files, hasLength(1));
      },
    );
  }

  testWidgets('a sync request that never starts leaves the review unchanged', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(
      tester,
      sync: ReviewSync()..throwBeforeStart = true,
    );
    await reach(tester, 'Sync first');
    expect(harness.export.prepares, 0);
    expect(find.textContaining('This review is unchanged'), findsOneWidget);
    expect(find.textContaining('has been refreshed'), findsNothing);
    expect(find.textContaining('private sync diagnostics'), findsNothing);
  });

  testWidgets('large-text receipt and re-review start at their headings', (
    WidgetTester tester,
  ) async {
    await pumpReview(tester, size: const Size(320, 568), scale: 3);
    await reach(tester, 'Export this device now');
    expect(find.text('Export receipt').hitTestable(), findsOneWidget);
    await reach(tester, 'Review this file again');
    expect(find.text('Review food export').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached account can export while account lookup is offline', (
    WidgetTester tester,
  ) async {
    final ReviewHarness harness = await pumpReview(
      tester,
      auth: ReviewAuth(offline: true),
    );
    await reach(tester, 'Export this device now');
    expect(harness.share.files, hasLength(1));
    expect(find.text('Export receipt'), findsOneWidget);
  });
}
