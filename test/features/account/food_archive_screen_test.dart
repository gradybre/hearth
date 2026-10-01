import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/sync_controller.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/food_data_archive.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/sync/sync_engine.dart';
import 'package:hearth/features/account/food_archive_screen.dart';
import 'package:hearth/features/account/settings_screen.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/fake_auth.dart';
import '../../support/fake_food_archive.dart';

class ArchiveAuth extends FakeAuthGateway {
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
  Future<HearthAccount?> currentAccount() async =>
      throw const SocketException('Offline synthetic test');
}

class ArchiveSync extends FakeSyncController {
  int requests = 0;
  Completer<void>? gate;
  bool noOp = false;
  @override
  Future<void> sync() async {
    requests++;
    if (noOp) return;
    state = const SyncStatus.syncing();
    await gate?.future;
    state = const SyncStatus.done(
      SyncResult(pushed: 0, failed: 0, stillQueued: 0),
      pulled: PullResult(applied: 0, skipped: 0),
    );
  }
}

Future<
  ({
    FakeFoodDataArchive builder,
    FakeArchiveFileShare share,
    ArchiveAuth auth,
    ArchiveSync sync,
  })
>
pumpArchive(
  WidgetTester tester, {
  FakeFoodDataArchive? builder,
  FakeArchiveFileShare? share,
  ArchiveSync? sync,
  bool settings = false,
  bool ready = true,
  Size size = const Size(500, 1800),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final FakeFoodDataArchive archiveBuilder = builder ?? FakeFoodDataArchive();
  final FakeArchiveFileShare sharing = share ?? FakeArchiveFileShare();
  final ArchiveAuth auth = ArchiveAuth();
  final ArchiveSync syncing = sync ?? ArchiveSync();
  addTearDown(auth.changes.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authGatewayProvider.overrideWithValue(auth),
        foodDataArchiveProvider.overrideWithValue(archiveBuilder),
        archiveFileShareProvider.overrideWithValue(sharing),
        syncControllerProvider.overrideWith(() => syncing),
        supabaseReadyProvider.overrideWithValue(ready),
      ],
      child: MaterialApp(
        theme: dark ? HearthTheme.dark() : HearthTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => settings
                      ? const DataSettingsScreen()
                      : const FoodArchiveScreen(
                          account: FakeAuthGateway.anAccount,
                        ),
                ),
              ),
              child: const Text('Open data'),
            ),
          ),
        ),
      ),
    ),
  );
  await pumpFrames(tester);
  await tapArchive(tester, find.text('Open data'));
  await tester.pumpAndSettle();
  return (builder: archiveBuilder, share: sharing, auth: auth, sync: syncing);
}

Future<void> bringArchive(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      400,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 150,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> tapArchive(WidgetTester tester, Finder finder) async {
  await bringArchive(tester, finder);
  await tester.tap(finder);
  await pumpFrames(tester);
}

Future<void> prepareArchive(WidgetTester tester) =>
    tapArchive(tester, find.byKey(const Key('archive-prepare')));
Future<void> shareArchive(WidgetTester tester) =>
    tapArchive(tester, find.byKey(const Key('archive-share')));

void main() {
  testWidgets('settings opens photo-off options without preparing or sharing', (
    WidgetTester tester,
  ) async {
    final harness = await pumpArchive(tester, settings: true);
    expect(find.text('Export food data (JSON)'), findsOneWidget);
    await tapArchive(tester, find.text('Readable food archive'));
    expect(harness.builder.photoRequests, isEmpty);
    expect(harness.share.archives, isEmpty);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('archive-include-photos')),
          )
          .value,
      isFalse,
    );
    await prepareArchive(tester);
    expect(find.text('Review food archive'), findsOneWidget);
    expect(harness.builder.photoRequests, <bool>[false]);
    expect(harness.share.archives, isEmpty);
    final PreparedFoodArchive reviewed = harness.builder.prepared.single;
    harness.builder.next = TestFoodArchive(name: 'later-data.zip');
    await shareArchive(tester);
    expect(harness.builder.photoRequests, hasLength(1));
    expect(identical(harness.share.archives.single, reviewed), isTrue);
    expect(find.text('An export action was selected'), findsOneWidget);
    expect(
      find.textContaining('did not confirm the file was saved'),
      findsOneWidget,
    );
  });

  testWidgets('optional photos report omissions without losing readable data', (
    WidgetTester tester,
  ) async {
    final harness = await pumpArchive(tester);
    await tapArchive(tester, find.byKey(const Key('archive-include-photos')));
    await prepareArchive(tester);
    expect(harness.builder.photoRequests, <bool>[true]);
    await bringArchive(tester, find.text('1 included · 1 unavailable'));
    expect(
      find.textContaining('Sunday soup: The photo is offline'),
      findsOneWidget,
    );
    await shareArchive(tester);
    expect(harness.share.archives.single.photosRequested, isTrue);
  });

  testWidgets('preparation failure keeps options and supports retry', (
    WidgetTester tester,
  ) async {
    final FakeFoodDataArchive builder = FakeFoodDataArchive()
      ..failure = StateError('private diagnostics');
    final harness = await pumpArchive(tester, builder: builder);
    await prepareArchive(tester);
    expect(
      find.textContaining('Could not prepare the archive'),
      findsOneWidget,
    );
    expect(find.textContaining('private diagnostics'), findsNothing);
    expect(harness.share.archives, isEmpty);
    builder.failure = null;
    await prepareArchive(tester);
    expect(find.text('Review food archive'), findsOneWidget);
  });

  for (final bool useBack in <bool>[false, true]) {
    testWidgets(
      '${useBack ? 'Back' : 'Cancel'} discards a late archive without reopening',
      (WidgetTester tester) async {
        final Completer<PreparedFoodArchive> gate =
            Completer<PreparedFoodArchive>();
        final FakeFoodDataArchive builder = FakeFoodDataArchive()..gate = gate;
        final harness = await pumpArchive(tester, builder: builder);
        await prepareArchive(tester);
        final FilledButton prepare = tester.widget(
          find.byKey(const Key('archive-prepare')),
        );
        expect(prepare.onPressed, isNull);
        await tapArchive(
          tester,
          useBack ? find.byTooltip('Back') : find.text('Cancel'),
        );
        final TestFoodArchive result = TestFoodArchive();
        gate.complete(result);
        await tester.pumpAndSettle();
        expect(result.discards, 1);
        expect(builder.isCurrent!(), isFalse);
        expect(find.text('Open data'), findsOneWidget);
        expect(find.text('Review food archive'), findsNothing);
        expect(harness.share.archives, isEmpty);
      },
    );
  }

  testWidgets('account away and back expires the prepared file permanently', (
    WidgetTester tester,
  ) async {
    final TestFoodArchive prepared = TestFoodArchive();
    final harness = await pumpArchive(
      tester,
      builder: FakeFoodDataArchive()..next = prepared,
    );
    await prepareArchive(tester);
    harness.auth.change(null);
    await tester.pump();
    harness.auth.change(FakeAuthGateway.anAccount);
    await pumpFrames(tester);
    expect(find.text('Review expired'), findsOneWidget);
    expect(prepared.discards, 1);
    expect(find.byKey(const Key('archive-share')), findsNothing);
    expect(harness.share.archives, isEmpty);
  });

  testWidgets('changed household during preparation discards late result', (
    WidgetTester tester,
  ) async {
    final Completer<PreparedFoodArchive> gate =
        Completer<PreparedFoodArchive>();
    final harness = await pumpArchive(
      tester,
      builder: FakeFoodDataArchive()..gate = gate,
    );
    await prepareArchive(tester);
    harness.auth.change(
      const HearthAccount(
        userId: 'user-1',
        email: 'cook@example.com',
        householdId: 'household-2',
      ),
    );
    await tester.pump();
    final TestFoodArchive result = TestFoodArchive();
    gate.complete(result);
    await pumpFrames(tester);
    expect(find.text('Review expired'), findsOneWidget);
    expect(result.discards, 1);
    expect(harness.share.archives, isEmpty);
  });

  testWidgets('sharing failure retries the same reviewed archive', (
    WidgetTester tester,
  ) async {
    final FakeArchiveFileShare share = FakeArchiveFileShare()
      ..failure = StateError('synthetic failure');
    final harness = await pumpArchive(tester, share: share);
    await prepareArchive(tester);
    await shareArchive(tester);
    expect(find.textContaining('Could not open sharing'), findsOneWidget);
    share.failure = null;
    await shareArchive(tester);
    expect(share.archives, hasLength(2));
    expect(identical(share.archives.first, share.archives.last), isTrue);
    expect(harness.builder.photoRequests, hasLength(1));
  });

  for (final FileShareOutcome outcome in <FileShareOutcome>[
    FileShareOutcome.dismissed,
    FileShareOutcome.unavailable,
  ]) {
    testWidgets('receipt honestly reports ${outcome.name}', (
      WidgetTester tester,
    ) async {
      final harness = await pumpArchive(
        tester,
        share: FakeArchiveFileShare()..outcome = outcome,
      );
      await prepareArchive(tester);
      await shareArchive(tester);
      expect(
        find.text(
          outcome == FileShareOutcome.dismissed
              ? 'Sharing was dismissed'
              : 'The outcome is unavailable',
        ),
        findsOneWidget,
      );
      await tapArchive(tester, find.text('Review archive again'));
      await shareArchive(tester);
      expect(harness.share.archives, hasLength(2));
      expect(
        identical(harness.share.archives.first, harness.share.archives.last),
        isTrue,
      );
    });
  }

  testWidgets(
    'sharing protects its source file through Back and account changes',
    (WidgetTester tester) async {
      final Completer<FileShareOutcome> gate = Completer<FileShareOutcome>();
      final FakeArchiveFileShare share = FakeArchiveFileShare()..gate = gate;
      final TestFoodArchive result = TestFoodArchive();
      final harness = await pumpArchive(
        tester,
        builder: FakeFoodDataArchive()..next = result,
        share: share,
      );
      await prepareArchive(tester);
      await shareArchive(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(FoodArchiveScreen), findsOneWidget);
      expect(result.discards, 0);
      harness.auth.change(null);
      await tester.pump();
      expect(find.text('Review expired'), findsOneWidget);
      expect(result.discards, 0);
      gate.complete(FileShareOutcome.dismissed);
      await pumpFrames(tester);
      expect(result.discards, 1);
      expect(find.text('Archive export receipt'), findsNothing);
      await tapArchive(tester, find.text('Back to your data'));
      expect(result.discards, 1);
    },
  );

  testWidgets('route teardown defers cleanup until a pending share settles', (
    WidgetTester tester,
  ) async {
    final Completer<FileShareOutcome> gate = Completer<FileShareOutcome>();
    final TestFoodArchive result = TestFoodArchive();
    await pumpArchive(
      tester,
      builder: FakeFoodDataArchive()..next = result,
      share: FakeArchiveFileShare()..gate = gate,
    );
    await prepareArchive(tester);
    await shareArchive(tester);
    await tester.pumpWidget(const SizedBox());
    expect(result.discards, 0);
    gate.complete(FileShareOutcome.dismissed);
    await pumpFrames(tester);
    expect(result.discards, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changed options cannot share old bytes and can return to exact review',
    (WidgetTester tester) async {
      final harness = await pumpArchive(tester);
      await prepareArchive(tester);
      final PreparedFoodArchive first = harness.builder.prepared.single;
      await tapArchive(tester, find.text('Change options'));
      await tapArchive(tester, find.byKey(const Key('archive-include-photos')));
      expect(find.byKey(const Key('archive-share')), findsNothing);
      await tapArchive(tester, find.text('Return to reviewed archive'));
      await shareArchive(tester);
      expect(identical(harness.share.archives.single, first), isTrue);
      expect(harness.share.archives.single.photosRequested, isFalse);
    },
  );

  testWidgets('Sync first waits, refreshes once and never shares', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    final ArchiveSync sync = ArchiveSync()..gate = gate;
    final harness = await pumpArchive(tester, sync: sync);
    await prepareArchive(tester);
    final TestFoodArchive first =
        harness.builder.prepared.single as TestFoodArchive;
    final TestFoodArchive next = TestFoodArchive(name: 'refreshed.zip');
    harness.builder.next = next;
    await tapArchive(tester, find.text('Sync first'));
    expect(sync.requests, 1);
    expect(harness.builder.photoRequests, hasLength(1));
    expect(harness.share.archives, isEmpty);
    gate.complete();
    await pumpFrames(tester);
    expect(harness.builder.photoRequests, hasLength(2));
    expect(first.discards, 1);
    expect(find.text('refreshed.zip'), findsOneWidget);
    expect(harness.share.archives, isEmpty);
    await shareArchive(tester);
    expect(identical(harness.share.archives.single, next), isTrue);
  });

  for (final bool ready in <bool>[false, true]) {
    testWidgets(
      'unavailable or no-op sync keeps the reviewed archive (ready $ready)',
      (WidgetTester tester) async {
        final harness = await pumpArchive(
          tester,
          ready: ready,
          sync: ArchiveSync()..noOp = true,
        );
        await prepareArchive(tester);
        await tapArchive(tester, find.text('Sync first'));
        expect(harness.builder.photoRequests, hasLength(1));
        expect(find.textContaining('This review is unchanged'), findsOneWidget);
        await shareArchive(tester);
        expect(
          identical(
            harness.share.archives.single,
            harness.builder.prepared.single,
          ),
          isTrue,
        );
      },
    );
  }

  for (final bool dark in <bool>[false, true]) {
    testWidgets(
      'small screen at 3× text reaches options, omissions and share ($dark)',
      (WidgetTester tester) async {
        final harness = await pumpArchive(
          tester,
          size: const Size(320, 568),
          scale: 3,
          dark: dark,
        );
        await tapArchive(
          tester,
          find.byKey(const Key('archive-include-photos')),
        );
        await prepareArchive(tester);
        await bringArchive(tester, find.text('1 included · 1 unavailable'));
        await shareArchive(tester);
        await bringArchive(tester, find.text('Done'));
        expect(find.text('Done').hitTestable(), findsOneWidget);
        expect(harness.share.archives, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
