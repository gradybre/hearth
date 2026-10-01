import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/auth/auth_gateway.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_contributors.dart';
import '../foods/food_detail_screen.dart';
import '../foods/food_draft.dart';
import '../foods/food_editor_screen.dart';
import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipe_editor_screen.dart';
import 'entry_resolver.dart';
import 'log_sheet.dart';
import 'logged_details_sheet.dart';
import 'nutrient_contributors_screen.dart';

/// Captures one day's receipt and one continuous account/household lifetime.
/// Current-source reads and explicit editors cannot change its saved values.
Future<void> showDailyNutrientContributors(
  BuildContext context, {
  required DateTime date,
  required SupportedNutrient nutrient,
  required Iterable<MealPlanEntry> entries,
}) async {
  final DailyNutrientContributors captured = DailyNutrientContributors(
    date: date,
    nutrient: nutrient,
    entries: entries,
  );
  final _ContributorScope scope = _ContributorScope(
    ProviderScope.containerOf(context, listen: false),
  );
  final NavigatorState outer = Navigator.of(context);
  try {
    late final MaterialPageRoute<_ContributorHandoff> route;
    route = MaterialPageRoute<_ContributorHandoff>(
      settings: const RouteSettings(name: 'daily-nutrient-contributors'),
      builder: (BuildContext context) => _ContributorHost(
        captured: captured,
        scope: scope,
        onClose: () async {
          if (route.isCurrent) outer.pop();
        },
        onHandoff: (_ContributorHandoff handoff) {
          if (scope.active && route.isCurrent) outer.pop(handoff);
        },
      ),
    );
    final _ContributorHandoff? handoff = await outer.push<_ContributorHandoff>(
      route,
    );
    if (handoff != null && context.mounted && scope.active) {
      // Established editor/detail flows take over only after the receipt is
      // closed. Their later child routes and saves retain their existing
      // lifecycle behavior; this receipt does not claim to cancel a write
      // already started by one of those editors.
      await _ContributorActions(
        captured,
        scope,
        (_) {},
      ).launch(context, handoff);
    }
  } finally {
    scope.close();
  }
}

/// The receipt and its frozen-details sheet share a disposable stack. Editors
/// are deliberate handoffs to the established outer flows after fresh checks.
class _ContributorHost extends StatefulWidget {
  const _ContributorHost({
    required this.captured,
    required this.scope,
    required this.onClose,
    required this.onHandoff,
  });
  final DailyNutrientContributors captured;
  final _ContributorScope scope;
  final Future<void> Function() onClose;
  final void Function(_ContributorHandoff) onHandoff;

  @override
  State<_ContributorHost> createState() => _ContributorHostState();
}

class _ContributorHostState extends State<_ContributorHost> {
  late final _ContributorActions actions = _ContributorActions(
    widget.captured,
    widget.scope,
    widget.onHandoff,
  );
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.scope.available,
    builder: (BuildContext context, bool active, Widget? child) => !active
        ? _ExpiredView(onClose: widget.onClose)
        : NavigatorPopHandler<void>(
            onPopWithResult: (_) async {
              // Let the receipt root close its outer route; a direct pop
              // would remove that root and leave an empty inner navigator.
              await navigator.currentState?.maybePop();
            },
            child: Navigator(
              key: navigator,
              onGenerateRoute: (RouteSettings settings) =>
                  MaterialPageRoute<void>(
                    settings: settings,
                    builder: (BuildContext context) => PopScope<void>(
                      canPop: false,
                      onPopInvokedWithResult: (bool didPop, _) async {
                        if (!didPop) await widget.onClose();
                      },
                      child: Consumer(
                        builder:
                            (
                              BuildContext context,
                              WidgetRef ref,
                              Widget? child,
                            ) {
                              // Only source availability refreshes. The date, log list,
                              // names, amounts and coverage remain the captured receipt.
                              ref.watch(foodLibraryProvider);
                              ref.watch(recipeLibraryProvider);
                              return NutrientContributorsScreen(
                                contributors: widget.captured,
                                onOpenLoggedDetails: (MealPlanEntry entry) =>
                                    actions.details(context, entry),
                                onImproveFuture: (MealPlanEntry entry) =>
                                    actions.improve(context, entry),
                                isSourceAvailable: actions.sourceAvailable,
                              );
                            },
                      ),
                    ),
                  ),
            ),
          ),
  );
}

class _ContributorActions {
  _ContributorActions(this.captured, this.scope, this.onHandoff);
  final DailyNutrientContributors captured;
  final _ContributorScope scope;
  final void Function(_ContributorHandoff) onHandoff;
  bool busy = false;
  bool handedOff = false;

  bool sourceAvailable(MealPlanEntry entry) {
    if (!scope.active) return false;
    return switch (entry.refType) {
      PlanRefType.food =>
        (scope.container.read(foodLibraryProvider).value ?? <Food>[]).any(
          (Food food) => food.id == entry.refId && _foodAvailable(food),
        ),
      PlanRefType.recipe =>
        (scope.container.read(recipeLibraryProvider).value ?? <Recipe>[]).any(
          (Recipe recipe) =>
              recipe.id == entry.refId && _recipeAvailable(recipe),
        ),
    };
  }

  bool _foodAvailable(Food food) =>
      !food.isDeleted &&
      (food.isGlobal || food.householdId == scope.householdId);
  bool _recipeAvailable(Recipe recipe) =>
      !recipe.isDeleted && recipe.householdId == scope.householdId;

  Future<void> _run(
    BuildContext context,
    MealPlanEntry entry,
    Future<void> Function() action,
  ) async {
    if (!context.mounted ||
        !scope.active ||
        busy ||
        handedOff ||
        !captured.entries.any(
          (MealPlanEntry saved) => identical(saved, entry),
        )) {
      return;
    }
    busy = true;
    try {
      await action();
    } catch (_) {
      if (context.mounted && scope.active) {
        _say(context, 'Could not open this meal. Try again.');
      }
    } finally {
      busy = false;
    }
  }

  Future<void> details(BuildContext context, MealPlanEntry entry) =>
      _run(context, entry, () async {
        final LoggedDetailsAction? action = await showLoggedDetailsSheet(
          context,
          entry: entry,
          sourceAvailable: sourceAvailable(entry),
        );
        if (!context.mounted || !scope.active || action == null) return;
        if (!await _unchanged(context, entry) ||
            !context.mounted ||
            !scope.active) {
          return;
        }
        _handoff(entry, switch (action) {
          LoggedDetailsAction.editPortion => _HandoffKind.portion,
          LoggedDetailsAction.viewCurrent => _HandoffKind.current,
        });
      });

  Future<void> improve(BuildContext context, MealPlanEntry entry) =>
      _run(context, entry, () async {
        if (!await _unchanged(context, entry) ||
            !context.mounted ||
            !scope.active) {
          return;
        }
        if (await _currentDestination(context, entry, edit: true) == null ||
            !context.mounted ||
            !scope.active) {
          return;
        }
        _handoff(entry, _HandoffKind.improve);
      });

  void _handoff(MealPlanEntry entry, _HandoffKind kind) {
    if (!scope.active || handedOff) return;
    handedOff = true;
    onHandoff(_ContributorHandoff(entry, kind));
  }

  Future<void> launch(BuildContext context, _ContributorHandoff handoff) async {
    final MealPlanEntry entry = handoff.entry;
    try {
      if (!context.mounted ||
          !scope.active ||
          !await _unchanged(context, entry) ||
          !context.mounted ||
          !scope.active) {
        return;
      }
      if (handoff.kind == _HandoffKind.portion) {
        final MacroSnapshot? snapshot = entry.macroSnapshot;
        if (snapshot == null ||
            !snapshot.servings.isFinite ||
            snapshot.servings <= 0) {
          _say(
            context,
            'The saved portion is unavailable. This log has not changed.',
          );
          return;
        }
        await showLogSheet(
          context,
          date: captured.date,
          slot: entry.slot,
          existing: ResolvedEntry(
            entry: entry,
            label: snapshot.label,
            perServing: snapshot.macros.scaledBy(1 / snapshot.servings),
            liveCoverage: snapshot.coverage,
            isResolvable: true,
          ),
        );
      } else {
        final Widget? destination = await _currentDestination(
          context,
          entry,
          edit: handoff.kind == _HandoffKind.improve,
        );
        if (destination == null || !context.mounted || !scope.active) return;
        // A source read may have waited while the meal was corrected, moved
        // or removed. It must still be the captured record at the handoff.
        if (!await _unchanged(context, entry) ||
            !context.mounted ||
            !scope.active) {
          return;
        }
        await Navigator.of(context).push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (BuildContext context) => destination,
          ),
        );
      }
      if (!context.mounted || !scope.active) return;
    } catch (_) {
      if (context.mounted && scope.active) {
        _say(context, 'Could not open this meal. Try again.');
      }
    }
  }

  Future<bool> _unchanged(BuildContext context, MealPlanEntry expected) async {
    if (!context.mounted || !scope.active) return false;
    final List<MealPlanEntry> current = await scope.plans.entriesFor(
      captured.date,
    );
    if (!context.mounted || !scope.active) return false;
    final bool same = current.any(
      (MealPlanEntry entry) => _sameSavedEntry(entry, expected),
    );
    if (!same) {
      _say(
        context,
        'This logged meal changed. Close this view and reopen the day.',
      );
    }
    return same;
  }

  Future<Widget?> _currentDestination(
    BuildContext context,
    MealPlanEntry entry, {
    required bool edit,
  }) async {
    if (!context.mounted || !scope.active) return null;
    final Widget destination;
    switch (entry.refType) {
      case PlanRefType.food:
        final Food? food = await scope.container
            .read(foodRepositoryProvider)
            .byId(entry.refId);
        if (!context.mounted || !scope.active) return null;
        if (food == null || !_foodAvailable(food)) {
          _say(
            context,
            'The current food is unavailable. Your saved log has not changed.',
          );
          return null;
        }
        destination = edit
            ? food.isGlobal
                  ? FoodEditorScreen(initialDraft: FoodDraft.fromLookup(food))
                  : FoodEditorScreen(foodId: food.id)
            : FoodDetailScreen(
                foodId: food.id,
                servingOptionId: entry.servingOptionId,
              );
      case PlanRefType.recipe:
        final Recipe? recipe = await scope.container
            .read(recipeRepositoryProvider)
            .byId(entry.refId);
        if (!context.mounted || !scope.active) return null;
        if (recipe == null || !_recipeAvailable(recipe)) {
          _say(
            context,
            'The current recipe is unavailable. Your saved log has not changed.',
          );
          return null;
        }
        destination = edit
            ? RecipeEditorScreen(recipeId: recipe.id)
            : RecipeDetailScreen(recipeId: recipe.id);
    }
    return context.mounted && scope.active ? destination : null;
  }

  void _say(BuildContext context, String message) {
    if (!context.mounted || !scope.active) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _HandoffKind { portion, current, improve }

class _ContributorHandoff {
  const _ContributorHandoff(this.entry, this.kind);
  final MealPlanEntry entry;
  final _HandoffKind kind;
}

bool _sameSavedEntry(MealPlanEntry current, MealPlanEntry expected) =>
    current.id == expected.id &&
    current.dayId == expected.dayId &&
    current.slot == expected.slot &&
    current.refType == expected.refType &&
    current.refId == expected.refId &&
    current.servings == expected.servings &&
    current.servingOptionId == expected.servingOptionId &&
    current.isPlanned == expected.isPlanned &&
    current.isLogged == expected.isLogged &&
    _storedSecond(current.loggedAt) == _storedSecond(expected.loggedAt) &&
    current.macroSnapshot == expected.macroSnapshot;

int? _storedSecond(DateTime? time) =>
    time == null ? null : time.millisecondsSinceEpoch ~/ 1000;

class _ContributorScope {
  _ContributorScope(this.container)
    : userId = container.read(currentUserIdProvider),
      householdId = container.read(currentHouseholdIdProvider),
      plans = container.read(planRepositoryProvider) {
    subscriptions.add(
      container.listen<String>(currentUserIdProvider, (
        String? before,
        String after,
      ) {
        if (after != userId) expire();
      }),
    );
    subscriptions.add(
      container.listen<String>(currentHouseholdIdProvider, (
        String? before,
        String after,
      ) {
        if (after != householdId) expire();
      }),
    );
    subscriptions.add(
      container.listen<PlanRepository>(planRepositoryProvider, (
        PlanRepository? before,
        PlanRepository after,
      ) {
        if (!identical(after, plans)) expire();
      }),
    );
    subscriptions.add(
      container.listen<AsyncValue<HearthAccount?>>(accountProvider, (
        before,
        after,
      ) {
        if (before?.hasValue == true &&
            after.hasValue &&
            ((before?.value == null) != (after.value == null) ||
                before?.value?.userId != after.value?.userId ||
                before?.value?.householdId != after.value?.householdId)) {
          expire();
        }
      }),
    );
  }

  final ProviderContainer container;
  final String userId;
  final String householdId;
  final PlanRepository plans;
  final ValueNotifier<bool> available = ValueNotifier<bool>(true);
  final List<ProviderSubscription<Object?>> subscriptions =
      <ProviderSubscription<Object?>>[];
  bool closed = false;

  bool get active {
    if (closed || !available.value) return false;
    if (container.read(currentUserIdProvider) != userId ||
        container.read(currentHouseholdIdProvider) != householdId ||
        !identical(container.read(planRepositoryProvider), plans)) {
      expire();
    }
    return available.value;
  }

  void expire() {
    if (!closed && available.value) available.value = false;
  }

  void close() {
    if (closed) return;
    closed = true;
    for (final ProviderSubscription<Object?> subscription in subscriptions) {
      subscription.close();
    }
    // The popped route can still be animating out. No notification is needed,
    // and its listener is detached before this notifier becomes unreachable.
  }
}

class _ExpiredView extends StatelessWidget {
  const _ExpiredView({required this.onClose});
  final Future<void> Function() onClose;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'This view expired. Open the day and try again.',
              style: context.text.body,
            ),
            const SizedBox(height: HearthSpacing.lg),
            TextButton(onPressed: onClose, child: const Text('Back')),
          ],
        ),
      ),
    ),
  );
}
