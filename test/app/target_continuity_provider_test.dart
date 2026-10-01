import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/sync/remote_rows.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/target_schedule.dart';

const MacroTargets initial = MacroTargets(
  kcal: 2100,
  proteinG: 145,
  carbG: 225,
  fatG: 70,
  fiberG: 0,
  sodiumMg: null,
  cholesterolMg: 225,
);
const MacroTargets revised = MacroTargets(
  kcal: 2300,
  proteinG: 160,
  carbG: 260,
  fatG: 75,
  fiberG: null,
  sodiumMg: 0,
  cholesterolMg: null,
);

Map<String, Object?> targetRow({
  required String id,
  String userId = 'alice',
  String week = '2026-09-28',
  MacroTargets? targets = initial,
  bool ongoing = true,
  required DateTime at,
}) => <String, Object?>{
  'id': id,
  'user_id': userId,
  'week_start_date': week,
  if (ongoing) 'is_stopped': targets == null,
  'kcal': targets?.kcal,
  'protein_g': targets?.proteinG,
  'carb_g': targets?.carbG,
  'fat_g': targets?.fatG,
  'fiber_g': targets?.fiberG,
  'sodium_mg': targets?.sodiumMg,
  'cholesterol_mg': targets?.cholesterolMg,
  'updated_at': at.toIso8601String(),
};

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late RemoteRows rows;
  late ProviderContainer container;
  late String currentUser;
  final DateTime monday = DateTime(2026, 9, 28);
  final DateTime t0 = DateTime.utc(2026, 9, 28, 12);
  final DateTime t1 = DateTime.utc(2026, 9, 28, 13);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    rows = RemoteRows(db);
    currentUser = 'alice';
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWith((Ref ref) => currentUser),
      ],
    );
    container.read(selectedDateProvider.notifier).select(monday);
    // Keep the actual screen-facing provider mounted. No target provider or
    // change stream is overridden, and target writes never invalidate it by
    // hand: the production dependency chain has to deliver the new values.
    container.listen(
      dayTargetsProvider,
      (AsyncValue<MacroTargets?>? before, AsyncValue<MacroTargets?> after) {},
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<MacroTargets?> displayed(MacroTargets? expected) async {
    final Completer<MacroTargets?> result = Completer<MacroTargets?>();
    final ProviderSubscription<AsyncValue<MacroTargets?>> subscription =
        container.listen(dayTargetsProvider, (
          AsyncValue<MacroTargets?>? before,
          AsyncValue<MacroTargets?> after,
        ) {
          if (result.isCompleted) return;
          if (after.hasError) {
            result.completeError(after.error!, after.stackTrace);
          } else if (!after.isLoading &&
              after.hasValue &&
              after.value == expected) {
            result.complete(after.value);
          }
        }, fireImmediately: true);
    try {
      return await result.future.timeout(const Duration(seconds: 5));
    } finally {
      subscription.close();
    }
  }

  Future<void> applyBoundary(Map<String, Object?> row) =>
      rows.applyOngoingTargets(row, hasPendingWrite: queue.hasPendingFor);

  test(
    'a local target save refreshes the displayed values without a meal edit',
    () async {
      await displayed(null);
      final Future<MacroTargets?> first = displayed(initial);
      await container.read(planRepositoryProvider).setTargets(monday, initial);
      expect(await first, initial);

      final Future<MacroTargets?> changed = displayed(revised);
      await container.read(planRepositoryProvider).setTargets(monday, revised);
      expect(await changed, revised);
      final ResolvedTargets result = await container.read(
        dayTargetResolutionProvider.future,
      );
      expect(result.source, TargetSource.exactWeek);
      expect(result.weekStart, monday);
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(await db.select(db.mealPlanDays).get(), isEmpty);
    },
  );

  test(
    'remote ongoing changes refresh values even when the row count is stable',
    () async {
      await displayed(null);
      final Future<MacroTargets?> first = displayed(initial);
      await applyBoundary(targetRow(id: 'ongoing', at: t0));
      expect(await first, initial);
      expect(
        (await container.read(dayTargetResolutionProvider.future)).source,
        TargetSource.ongoing,
      );

      final Future<MacroTargets?> changed = displayed(revised);
      await applyBoundary(targetRow(id: 'ongoing', targets: revised, at: t1));
      expect(await changed, revised);
      expect(await db.select(db.ongoingMacroTargets).get(), hasLength(1));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(await queue.count(), 0);
    },
  );

  test(
    'a remote stop removes the fallback while a saved future exception wins',
    () async {
      container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2026, 10, 5));
      await applyBoundary(targetRow(id: 'ongoing', at: t0));
      await rows.applyTargets(
        targetRow(
          id: 'future-week',
          week: '2026-10-12',
          targets: revised,
          ongoing: false,
          at: t0,
        ),
        hasPendingWrite: queue.hasPendingFor,
      );
      await displayed(initial);

      final Future<MacroTargets?> stopped = displayed(null);
      await applyBoundary(targetRow(id: 'ongoing', targets: null, at: t1));
      expect(await stopped, isNull);
      expect(
        (await container.read(dayTargetResolutionProvider.future))
            .ongoingBoundary!
            .isStopped,
        isTrue,
      );

      container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2026, 10, 12));
      expect(await displayed(revised), revised);
      final ResolvedTargets exception = await container.read(
        dayTargetResolutionProvider.future,
      );
      expect(exception.source, TargetSource.exactWeek);
      expect(exception.ongoingBoundary!.isStopped, isTrue);
      container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2026, 10, 19));
      expect(await displayed(null), isNull);
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  test(
    'a captured week keeps its own answer as selection and future targets move',
    () async {
      await applyBoundary(targetRow(id: 'first', week: '2026-09-21', at: t0));
      await displayed(initial);
      container.listen(
        targetResolutionProvider(monday),
        (
          AsyncValue<ResolvedTargets>? before,
          AsyncValue<ResolvedTargets> after,
        ) {},
      );
      expect(
        (await container.read(targetResolutionProvider(monday).future)).targets,
        initial,
      );

      container
          .read(selectedDateProvider.notifier)
          .select(DateTime(2026, 10, 12));
      await displayed(initial);
      final Future<MacroTargets?> changed = displayed(revised);
      await applyBoundary(
        targetRow(id: 'future', week: '2026-10-05', targets: revised, at: t1),
      );
      expect(await changed, revised);

      final ResolvedTargets captured = await container.read(
        targetResolutionProvider(monday).future,
      );
      expect(captured.weekStart, monday);
      expect(captured.targets, initial);
      expect(captured.ongoingBoundary!.weekStart, DateTime(2026, 9, 21));
    },
  );

  test(
    'switching users replaces the target providers with the new private scope',
    () async {
      await applyBoundary(targetRow(id: 'alice', at: t0));
      await applyBoundary(
        targetRow(id: 'bob', userId: 'bob', targets: revised, at: t0),
      );
      expect(await displayed(initial), initial);

      currentUser = 'bob';
      container.invalidate(currentUserIdProvider);
      expect(await displayed(revised), revised);
      expect(
        (await container.read(dayTargetResolutionProvider.future)).userId,
        'bob',
      );

      await applyBoundary(targetRow(id: 'alice', targets: null, at: t1));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await container.read(dayTargetsProvider.future), revised);

      currentUser = 'alice';
      container.invalidate(currentUserIdProvider);
      expect(await displayed(null), isNull);
      expect(
        (await container.read(dayTargetResolutionProvider.future)).userId,
        'alice',
      );
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );
}
