import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/cook_session_store.dart';
import 'package:hearth/domain/cooking/cook_session.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';

import 'app_harness.dart';
import 'fake_kitchen.dart';

/// Everything the app can put in front of you that a sweep has to visit.
///
/// The sweep used to be a hand-written list of journeys, which meant it could
/// only ever cover what somebody had remembered to add. Three times in one
/// package a surface was put behind a tap — the rings behind Details, the log
/// sheet's confirm view, the ways to add a recipe — and each time it left the
/// swept surface silently, because a sweep cannot miss what it was never told
/// about.
///
/// So the list is declared here, and `every_surface_is_swept_test.dart` reads
/// the source of `lib/` and fails when something opens a sheet or a dialog
/// that this list does not mention.
///
/// **What that guard can and cannot see.** It finds sheets and dialogs,
/// because those are a call it can recognise. It cannot find a surface that
/// is a *branch* — the rings behind Details are `if (expanded)` inside a
/// card, and the log sheet's confirm view is the other side of a ternary in
/// a builder. Two of the three misses that prompted this were exactly that
/// shape, and no amount of reading the source would have caught them.
///
/// So the guard closes one door and this list is the other. Anything reached
/// by a tap, a long press, or a toggle belongs here whether or not the guard
/// could have asked for it.
///
/// **And the doors are not the same strength.** Delete a sheet-backed surface
/// from this list and the guard notices, because its file goes unaccounted
/// for. Delete a *branch* surface and nothing fails — the sweep simply runs
/// fewer cases. That happened in the very change that introduced this file:
/// the expanded day summary was covered before it and not after, and only
/// comparing the two lists by hand found it. A shorter list is not a smaller
/// app.
@immutable
class SweptSurface {
  const SweptSurface({
    required this.name,
    required this.opensFrom,
    required this.open,
    required this.arrived,
    this.farEnd,
    this.waypoints = const <Finder>[],
    this.isInline = false,
    this.withOngoingTargets = false,
    this.withLoggedMeal = false,
    this.createOverrides,
  });

  /// What it is, in the words the test failure will use.
  final String name;

  /// The file in `lib/` that opens or toggles it.
  final String opensFrom;

  /// A view toggled within a page, rather than a sheet or dialog. Its source
  /// must exist, but it cannot account for an unswept overlay in that file.
  final bool isInline;

  /// Exercises the ongoing editor's distinct scope and stop controls.
  final bool withOngoingTargets;

  /// History surfaces need a saved snapshot, not the plan fixture.
  final bool withLoggedMeal;

  /// A fresh synthetic failure for each walk, without sharing mutable fakes.
  final List<Object> Function()? createOverrides;

  /// How to get there from a freshly opened app.
  final Future<void> Function(WidgetTester tester, SweepTools tools) open;

  /// Something only this surface shows.
  ///
  /// Asserted after [open], because "no exception" is equally true of a
  /// journey that never arrived — which is how three of the first flows in
  /// this sweep reported success from a screen they had never left.
  final Finder arrived;

  /// Something at the bottom of it, when it has a bottom worth reaching.
  ///
  /// A lazy list does not build what is off the screen, and a row that is
  /// never built cannot overflow — so a sweep that only looks at the first
  /// viewport passes on a sheet whose last control is unreachable.
  final Finder? farEnd;

  /// Long reviews are read section by section before reaching the action.
  /// Each waypoint is checked, so large text never silently skips a section.
  final List<Finder> waypoints;
}

/// The scrolling and tapping a sweep needs, shared by every surface.
class SweepTools {
  const SweepTools(this._tester);

  final WidgetTester _tester;

  /// The last vertical scroll view that accepts a person's drag.
  ///
  /// Text fields contain an editable scrollable of their own, vertical for
  /// multiline input, so "the last scrollable" on a sheet full of fields is
  /// a text box and dragging that goes nowhere. The shopping list's store groups
  /// also contain Scrollables, but those have scrolling disabled: the outer
  /// list owns the gesture, and an inner group's center can be off screen.
  static Finder get verticalScroller => find
      .byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable &&
            widget.restorationId != 'editable' &&
            widget.physics?.allowUserScrolling != false &&
            (widget.axisDirection == AxisDirection.down ||
                widget.axisDirection == AxisDirection.up),
      )
      .last;

  /// Brings [finder] onto the screen, scrolling if it is not built yet.
  ///
  /// Returns the finder narrowed to the *last* match, not the first: with a
  /// sheet open the row behind the modal matches too and comes first, so
  /// acting on `.first` acts on the page underneath.
  Future<Finder> bring(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await _tester.dragUntilVisible(
        // The unfiltered finder: `dragUntilVisible` asks it whether it is
        // empty on every step, and `.first` of nothing throws rather than
        // answering.
        finder,
        verticalScroller,
        const Offset(0, -120),
      );
      await pumpFrames(_tester, frames: 4);
    }

    final Finder one = finder.last;
    // Present is not the same as on screen: an off-screen widget still
    // matches a finder, which is the trap this whole file exists to point at.
    await _tester.ensureVisible(one);
    await pumpFrames(_tester, frames: 4);
    return one;
  }

  /// Brings [finder] on screen and taps it.
  Future<void> reach(Finder finder) async {
    await _tester.tap(await bring(finder));
    await pumpFrames(_tester, frames: 12);
  }

  /// Scrolls until [finder] matches at least [atLeast] widgets.
  ///
  /// `dragUntilVisible` stops at the first match, which is no use when the
  /// thing wanted is the *second* — "Today" is the page's title as well as
  /// the card's heading, and only the card opens the targets sheet.
  Future<void> bringNth(Finder finder, int atLeast) async {
    for (int i = 0; i < 40 && finder.evaluate().length < atLeast; i++) {
      await _tester.drag(verticalScroller, const Offset(0, -120));
      await pumpFrames(_tester, frames: 2);
    }
  }

  /// Opens a tab of the shell by its label.
  Future<void> tab(String label) async {
    await _tester.tap(find.text(label).last);
    await pumpFrames(_tester, frames: 12);
  }

  /// Selects the real Day/Week control in its direct or compact menu form.
  Future<void> planView(String label) async {
    if (label != 'Day' && label != 'Week') {
      throw ArgumentError.value(label, 'label', 'Expected Day or Week');
    }
    final Finder control = find.byKey(
      const ValueKey<String>('plan-view-control'),
    );
    expect(control, findsOneWidget);
    if (label == 'Week' &&
        find
            .byKey(const ValueKey<String>('week-content-control'))
            .evaluate()
            .isNotEmpty) {
      return;
    }
    if (_tester.widget(control) is PopupMenuButton<Object?>) {
      await reach(control);
      // The menu entry owns the tap; its checked label ignores pointers.
      await reach(
        find.byKey(ValueKey<String>('plan-view-${label.toLowerCase()}')),
      );
    } else {
      await reach(find.descendant(of: control, matching: find.text(label)));
    }
  }

  Future<void> weekContent(String label) async {
    if (label != 'Meals' && label != 'Nutrition') {
      throw ArgumentError.value(label, 'label', 'Expected Meals or Nutrition');
    }
    final Finder control = find.byKey(
      const ValueKey<String>('week-content-control'),
    );
    await bring(control);
    final bool popup =
        _tester.widget(control) is PopupMenuButton<Object?> ||
        find
            .descendant(
              of: control,
              matching: find.byWidgetPredicate(
                (Widget widget) => widget is PopupMenuButton<Object?>,
              ),
            )
            .evaluate()
            .isNotEmpty;
    if (popup) {
      await reach(control);
      await reach(
        find.byKey(ValueKey<String>('week-content-${label.toLowerCase()}')),
      );
    } else {
      await reach(find.descendant(of: control, matching: find.text(label)));
    }
  }
}

/// The surfaces this sweep visits.
///
/// Everything in `lib/` that opens a sheet or a dialog is either named here
/// or listed in [notSweptYet] with a reason. There is no third option: that
/// is the whole point.
Future<void> _openTimerTray(WidgetTester tester, SweepTools tools) async {
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).last),
  );
  await container
      .read(cookTimersProvider.notifier)
      .start(
        CookTimer(
          id: 'sweep-timer',
          label: 'Simmer the beans',
          duration: const Duration(minutes: 10),
          startedAt: DateTime.now(),
        ),
      );
  await pumpFrames(tester, frames: 8);
  await tools.reach(find.text('Simmer the beans'));
}

Finder _weekAction(String prefix, {String? suffix}) => find
    .byWidgetPredicate(
      (Widget widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(prefix) &&
          (suffix == null ||
              (widget.key! as ValueKey<String>).value.endsWith(suffix)),
    )
    .first;

Future<void> _openWeekMeals(WidgetTester tester, SweepTools tools) async {
  await tools.tab('Plan');
  await tools.planView('Week');
  await tools.weekContent('Meals');
}

final List<SweptSurface> sweptSurfaces = <SweptSurface>[
  SweptSurface(
    name: 'adjustable cooking timers',
    opensFrom: 'lib/features/recipes/timer_bar.dart',
    open: _openTimerTray,
    arrived: find.text('Timers'),
    waypoints: <Finder>[
      find.byKey(const ValueKey<String>('timer-add-1-sweep-timer')),
      find.byKey(const ValueKey<String>('timer-add-5-sweep-timer')),
      find.byKey(const ValueKey<String>('timer-set-sweep-timer')),
    ],
    farEnd: find.text('Done'),
  ),
  SweptSurface(
    name: 'setting a timer’s remaining time',
    opensFrom: 'lib/features/recipes/timer_controls.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await _openTimerTray(tester, tools);
      await tools.reach(
        find.byKey(const ValueKey<String>('timer-set-sweep-timer')),
      );
    },
    arrived: find.text('Minutes'),
    waypoints: <Finder>[find.text('Seconds'), find.text('Save time')],
    farEnd: find.text('Cancel'),
  ),
  for (final bool reset in <bool>[false, true])
    SweptSurface(
      name: reset
          ? 'retrying a cooking reset'
          : 'retrying saved cooking progress',
      opensFrom: 'lib/features/recipes/cook_along_screen.dart',
      isInline: true,
      createOverrides: () => <Object>[
        cookSessionStoreProvider.overrideWithValue(
          _InterruptedCookProgress(reset: reset),
        ),
      ],
      open: (WidgetTester tester, SweepTools tools) async {
        await tools.tab('Recipes');
        await tools.reach(find.text('Slow chilli with all the trimmings'));
        await tools.reach(find.text('Cook'));
        if (reset) {
          await tools.reach(find.text('Mark done'));
          await tools.reach(find.byTooltip('Start over'));
          await tools.reach(find.widgetWithText(FilledButton, 'Start over'));
        }
        await tools.reach(find.byTooltip('Ingredients'));
        await tools.bring(
          find.text(reset ? 'Retry Start over' : 'Retry saved progress'),
        );
      },
      arrived: find.text(reset ? 'Retry Start over' : 'Retry saved progress'),
      farEnd: find.text('Reset ingredients'),
    ),
  SweptSurface(
    name: 'the cooking ingredient checklist',
    opensFrom: 'lib/features/recipes/cook_along_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Cook'));
      await tools.reach(find.byTooltip('Ingredients'));
      final Finder row = find.byWidgetPredicate(
        (Widget widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'cook-ingredient-',
            ) &&
            (widget.key! as ValueKey<String>).value !=
                'cook-ingredient-checklist',
      );
      await tools.reach(row.first);
    },
    arrived: find.text('Prepared / added'),
    farEnd: find.text('Reset ingredients'),
  ),
  SweptSurface(
    name: 'the recipe nutrition calculation receipt',
    opensFrom: 'lib/features/recipes/recipe_nutrition_receipt.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(
        find.byKey(const ValueKey<String>('recipe-nutrition-receipt')),
      );
    },
    arrived: find.text('Nutrition details'),
    waypoints: <Finder>[
      find.byKey(const ValueKey<String>('receipt-ingredient-0')),
    ],
    farEnd: find.byKey(const ValueKey<String>('receipt-back')),
  ),
  SweptSurface(
    name: 'starting the whole cook over',
    opensFrom: 'lib/features/recipes/cook_along_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Cook'));
      await tools.reach(find.text('Mark done'));
      await tools.reach(find.byTooltip('Start over'));
    },
    arrived: find.text('Start this recipe over?'),
    farEnd: find.text('Start over'),
  ),
  SweptSurface(
    name: 'the food data export review',
    opensFrom: 'lib/features/account/settings_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Export food data (JSON)'));
      await pumpFrames(tester, frames: 20);
    },
    arrived: find.text('Review food export'),
    waypoints: <Finder>[
      find.byKey(const Key('export-review-counts')),
      find.byKey(const Key('export-review-exclusions')),
    ],
    farEnd: find.text('Export this device now'),
  ),
  SweptSurface(
    name: 'the readable food archive options',
    opensFrom: 'lib/features/account/settings_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Readable food archive'));
    },
    arrived: find.text('Readable food archive'),
    waypoints: <Finder>[find.text('Include recipe photos')],
    farEnd: find.text('Prepare archive'),
  ),
  SweptSurface(
    name: 'the readable food archive review with unavailable photos',
    opensFrom: 'lib/features/account/food_archive_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Readable food archive'));
      await tools.reach(find.text('Include recipe photos'));
      await tools.reach(find.text('Prepare archive'));
    },
    arrived: find.text('Review food archive'),
    waypoints: <Finder>[
      find.text('Inside the ZIP'),
      find.text('1 included · 1 unavailable'),
      find.text('Whose data and what is left out'),
      find.text('This device at capture'),
    ],
    farEnd: find.text('Export reviewed archive'),
  ),
  SweptSurface(
    name: 'the readable food archive receipt',
    opensFrom: 'lib/features/account/food_archive_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Readable food archive'));
      await tools.reach(find.text('Prepare archive'));
      // The harness replaces both preparation and sharing with synthetic fakes.
      // At 3× the review is several screens long. Read through its sections
      // rather than exhausting the bounded one-drag search for the last button.
      await tools.bring(find.text('Inside the ZIP'));
      await tools.bring(find.text('Whose data and what is left out'));
      await tools.bring(find.text('This device at capture'));
      await tools.reach(find.text('Export reviewed archive'));
    },
    arrived: find.text('Archive export receipt'),
    farEnd: find.text('Done'),
  ),
  SweptSurface(
    name: 'the food data export receipt',
    opensFrom: 'lib/features/account/export_review_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Export food data (JSON)'));
      await pumpFrames(tester, frames: 20);
      await tools.bring(find.byKey(const Key('export-review-counts')));
      await tools.bring(find.byKey(const Key('export-review-exclusions')));
      // pumpHearthApp always replaces the OS adapter with a fake. The
      // receipt is reached without sending a file outside this test.
      await tools.reach(find.text('Export this device now'));
    },
    arrived: find.text('Export receipt'),
    farEnd: find.text('Done'),
  ),
  SweptSurface(
    name: 'changing Plan to the week',
    opensFrom: 'lib/features/plan/plan_view_control.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.planView('Week');
    },
    arrived: find.byTooltip('Previous week'),
  ),
  SweptSurface(
    name: 'the weekly nutrition comparison',
    opensFrom: 'lib/features/plan/week_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.planView('Week');
      await tools.weekContent('Nutrition');
    },
    arrived: find.byTooltip('Previous week'),
  ),
  SweptSurface(
    name: 'weekly meals and expanded slots',
    opensFrom: 'lib/features/plan/week_meals_view.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _openWeekMeals(tester, tools);
      await tools.reach(_weekAction('week-other-meals-'));
    },
    arrived: find.text('Breakfast'),
    waypoints: <Finder>[
      _weekAction('week-meal-open-'),
      _weekAction('week-add-', suffix: '-breakfast'),
      _weekAction('week-add-', suffix: '-lunch'),
    ],
    farEnd: _weekAction('week-add-', suffix: '-snack'),
  ),
  SweptSurface(
    name: 'adding dinner from its week card',
    opensFrom: 'lib/features/plan/week_meals_view.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _openWeekMeals(tester, tools);
      await tools.reach(_weekAction('week-add-', suffix: '-dinner'));
    },
    arrived: find.text('Add to this meal'),
  ),
  SweptSurface(
    name: 'opening a recipe from the week',
    opensFrom: 'lib/features/plan/meal_source_actions.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _openWeekMeals(tester, tools);
      await tools.reach(_weekAction('week-other-meals-'));
      await tools.reach(_weekAction('week-meal-open-'));
    },
    arrived: find.byType(RecipeDetailScreen),
    farEnd: find.text('Directions'),
  ),
  SweptSurface(
    name: 'cooking directly from the week',
    opensFrom: 'lib/features/plan/meal_source_actions.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await _openWeekMeals(tester, tools);
      await tools.reach(_weekAction('week-other-meals-'));
      await tools.reach(_weekAction('week-meal-cook-'));
    },
    arrived: find.byType(CookAlongScreen),
    farEnd: find.text('Mark done'),
  ),
  SweptSurface(
    name: 'choosing where to copy a day',
    opensFrom: 'lib/features/plan/day_picker_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byTooltip('Copy this day to other days'));
    },
    arrived: find.text('Copy this day to'),
    farEnd: find.text('Cancel'),
  ),
  SweptSurface(
    name: "the day's targets",
    opensFrom: 'lib/features/plan/macro_targets_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      // The visible Change action remains available even when the compact
      // layout omits a redundant summary heading.
      await tools.reach(find.text('This week’s targets · Change'));
    },
    arrived: find.text('Weekly targets'),
    waypoints: <Finder>[find.text('Use these targets each new week')],
    farEnd: find.text('Save targets'),
  ),
  SweptSurface(
    name: 'ongoing target scope and stop controls',
    opensFrom: 'lib/features/plan/macro_targets_sheet.dart',
    isInline: true,
    withOngoingTargets: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.text('Using ongoing targets · Change'));
    },
    arrived: find.text('Weekly targets'),
    waypoints: <Finder>[
      find.text('This week only'),
      find.text('From this week onward'),
      find.text('Save targets'),
    ],
    farEnd: find.text('Stop carrying forward after this week'),
  ),
  SweptSurface(
    name: 'the unsaved-work question',
    opensFrom: 'lib/app/widgets/unsaved_work_guard.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
      await tools.reach(find.text('Write a recipe'));
      // Dirty first: a clean editor leaves without asking, which is the
      // point of it, and would sweep nothing.
      await tester.enterText(find.byType(TextField).first, 'Short ribs');
      await tools.reach(find.text('Cancel'));
    },
    arrived: find.text('Keep editing'),
    farEnd: find.text('Discard'),
  ),
  SweptSurface(
    name: 'what you picked from a menu',
    opensFrom: 'lib/features/recipes/eat_out_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
      await tools.reach(find.text('Eat out'));
      await tools.reach(find.text('Chopt'));
      // Something has to be picked before there is anything to review.
      await tools.reach(find.text('Harvest Bowl'));
      await tools.reach(find.textContaining('item ·'));
    },
    arrived: find.text('What you picked'),
    farEnd: find.byTooltip('Drop Harvest Bowl'),
  ),
  SweptSurface(
    name: "the shopping list's setup",
    opensFrom: 'lib/features/shopping/shopping_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('More'));
      await tools.reach(find.text('Manage list'));
    },
    arrived: find.text('Include seasonings'),
    // The build's explanation, which is last now that clearing has moved out
    // to the list itself. Still the thing furthest down: a sheet whose bottom
    // nobody has looked at is a sheet that overflows at three times the text
    // without anybody finding out.
    farEnd: find.textContaining('Replaces what the plan put here'),
  ),
  SweptSurface(
    name: 'the shopping list with completed items included',
    opensFrom: 'lib/features/shopping/shopping_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('All'));
    },
    arrived: find.text('1 item'),
    farEnd: find.text('At home 0'),
  ),
  SweptSurface(
    name: 'the shopping list options and help',
    opensFrom: 'lib/features/shopping/shopping_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('More'));
      await tools.reach(find.text('List help'));
    },
    arrived: find.textContaining('Tap an item when bought.'),
    farEnd: find.text('Clear the list'),
  ),
  SweptSurface(
    name: 'needed, have and buy amounts',
    opensFrom: 'lib/features/shopping/shopping_amount_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('2 lb'));
    },
    arrived: find.text('Total needed'),
    farEnd: find.text('Remove from list'),
  ),
  SweptSurface(
    name: 'the shopping export review',
    opensFrom: 'lib/features/shopping/shopping_export_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('More'));
      await tools.reach(find.text('Share or export'));
    },
    arrived: find.text('Take the list with you'),
    // Read the handoff explanation without copying or opening anything.
    farEnd: find.textContaining('Copy keeps the whole remaining list'),
  ),
  SweptSurface(
    name: 'putting something on the shopping list',
    opensFrom: 'lib/features/shopping/add_to_list_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('Add item'));
    },
    arrived: find.text('What do you need?'),
    // The recipe the sweep fixture carries, which with nothing typed is the
    // last row the sheet offers. Reaching it is the whole question at three
    // times the text: the heading, the explanation and the search field are
    // together taller than the sheet is allowed to be, so the results are
    // off the bottom unless the sheet scrolls as one thing.
    farEnd: find.text('Slow chilli with all the trimmings'),
  ),
  SweptSurface(
    name: 'an optional amount before adding a plain shopping item',
    opensFrom: 'lib/features/shopping/add_to_list_sheet.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('Add item'));
      await tester.enterText(
        await tools.bring(find.byKey(const Key('manual-item-name'))),
        'Coffee',
      );
      await pumpFrames(tester, frames: 4);
      await tools.reach(find.byKey(const Key('manual-item-add-amount')));
      await tester.enterText(
        await tools.bring(find.byKey(const Key('manual-item-amount'))),
        '1/2',
      );
      await pumpFrames(tester, frames: 4);
    },
    arrived: find.byKey(const Key('manual-item-amount')),
    waypoints: <Finder>[find.byKey(const Key('manual-item-unit'))],
    farEnd: find.byKey(const Key('manual-item-add')),
  ),
  SweptSurface(
    name: 'pasting shopping items before review',
    opensFrom: 'lib/features/shopping/paste_items_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('Add item'));
      await tools.reach(find.byKey(const Key('paste-items-open')));
      await tester.enterText(
        await tools.bring(find.byKey(const Key('paste-items-input'))),
        'Ground beef\nEggs\nEggs\nCoffee 500g',
      );
      // Read the enabled button after its disabled-to-enabled transition.
      await pumpFrames(tester, frames: 20);
    },
    arrived: find.byKey(const Key('paste-items-input')),
    farEnd: find.byKey(const Key('paste-items-review')),
  ),
  SweptSurface(
    name: 'reviewing pasted shopping items and their amounts',
    opensFrom: 'lib/features/shopping/paste_items_sheet.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Shopping');
      await tools.reach(find.text('Add item'));
      await tools.reach(find.byKey(const Key('paste-items-open')));
      await tester.enterText(
        await tools.bring(find.byKey(const Key('paste-items-input'))),
        'Ground beef\nEggs\nEggs\nCoffee 500g',
      );
      await pumpFrames(tester, frames: 4);
      await tools.reach(find.byKey(const Key('paste-items-review')));
      await tools.bring(find.text('Already on the list · will skip'));
      expect(find.text('Already on the list · will skip'), findsOneWidget);
      await tools.reach(find.byKey(const Key('paste-add-amount-1')));
      await tester.enterText(
        await tools.bring(find.byKey(const Key('paste-1-amount'))),
        '12',
      );
      await pumpFrames(tester, frames: 4);
    },
    arrived: find.byKey(const Key('paste-1-amount')),
    waypoints: <Finder>[
      find.byKey(const Key('paste-1-unit')),
      find.text('Repeated in this paste · will skip'),
      find.byKey(const Key('paste-name-3')),
    ],
    farEnd: find.byKey(const Key('paste-items-save')),
  ),
  SweptSurface(
    name: 'choosing something to log',
    opensFrom: 'lib/features/plan/log_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byTooltip('Add to breakfast'));
    },
    arrived: find.text('Add to this meal'),
  ),
  SweptSurface(
    name: 'the saved daily calorie contributors',
    opensFrom: 'lib/features/plan/nutrient_contributors_flow.dart',
    isInline: true,
    withLoggedMeal: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byKey(const Key('macro-total-calories')));
    },
    arrived: find.text('Calories contributors'),
    waypoints: <Finder>[
      find.text('Logged meals'),
      find.byKey(const Key('contributor-known-open-e1')),
    ],
    farEnd: find.byKey(const Key('contributor-known-improve-e1')),
  ),
  SweptSurface(
    name: 'missing information in a daily nutrient receipt',
    opensFrom: 'lib/features/plan/nutrient_contributors_screen.dart',
    isInline: true,
    withLoggedMeal: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byKey(const Key('minor-total-fiber')));
    },
    arrived: find.text('Fibre contributors'),
    waypoints: <Finder>[
      find.text('Missing information'),
      find.byKey(const Key('contributor-missing-open-e1')),
    ],
    farEnd: find.byKey(const Key('contributor-missing-improve-e1')),
  ),
  SweptSurface(
    name: 'frozen details from a daily nutrient contributor',
    opensFrom: 'lib/features/plan/nutrient_contributors_flow.dart',
    isInline: true,
    withLoggedMeal: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byKey(const Key('macro-total-calories')));
      await tools.reach(find.byKey(const Key('contributor-known-open-e1')));
    },
    arrived: find.text('Logged details'),
    waypoints: <Finder>[
      find.textContaining('Calories:'),
      find.textContaining('Cholesterol:'),
      find.text('Edit portion'),
      find.text('View current recipe'),
    ],
    farEnd: find.text('Close'),
  ),
  SweptSurface(
    name: 'improving the current recipe from a daily nutrient receipt',
    opensFrom: 'lib/features/plan/nutrient_contributors_flow.dart',
    isInline: true,
    withLoggedMeal: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.byKey(const Key('minor-total-fiber')));
      await tools.reach(
        find.byKey(const Key('contributor-missing-improve-e1')),
      );
      // The established editor loads the synthetic recipe asynchronously.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await pumpFrames(tester, frames: 20);
    },
    arrived: find.text('Edit recipe'),
    farEnd: find.text('Cancel'),
  ),
  SweptSurface(
    name: 'frozen logged nutrition and its actions',
    opensFrom: 'lib/features/plan/logged_details_sheet.dart',
    withLoggedMeal: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(
        find.byTooltip('Edit Slow chilli with all the trimmings'),
      );
      await tools.reach(find.text('View logged details'));
    },
    arrived: find.text('Logged details'),
    waypoints: <Finder>[
      find.textContaining('Calories:'),
      find.textContaining('Protein:'),
      find.textContaining('Carbohydrate:'),
      find.textContaining('Fat:'),
      find.textContaining('Fibre:'),
      find.textContaining('Sodium:'),
      find.textContaining('Cholesterol:'),
      find.text('Edit portion'),
      find.text('View current recipe'),
    ],
    farEnd: find.text('Close'),
  ),
  SweptSurface(
    name: "a meal's own options",
    opensFrom: 'lib/features/plan/day_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      // Long press keeps the options shortcut; tapping now opens the source.
      final Finder meal = await tools.bring(
        find.text('Slow chilli with all the trimmings'),
      );
      await tester.longPress(meal);
      await pumpFrames(tester, frames: 12);
    },
    arrived: find.text('Edit portion'),
  ),
  for (final String state in <String>[
    'current',
    'removed serving',
    'unavailable',
    'lookup error',
  ])
    SweptSurface(
      name: 'read-only food details: $state',
      opensFrom: 'lib/features/foods/food_detail_screen.dart',
      isInline: true,
      createOverrides: state == 'lookup error'
          ? () => <Object>[
              foodByIdProvider('f-yoghurt').overrideWith(
                (ref) async => throw StateError('Synthetic lookup failure'),
              ),
            ]
          : null,
      open: (WidgetTester tester, SweepTools tools) async {
        // The Plan navigation contract has dedicated interaction coverage.
        // Reuse the sweep's food fixture to walk every detail branch itself.
        Navigator.of(tester.element(find.byType(Scaffold).last)).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FoodDetailScreen(
              foodId: state == 'unavailable' ? 'missing-food' : 'f-yoghurt',
              servingOptionId: state == 'removed serving' ? 'removed' : null,
            ),
          ),
        );
        await pumpFrames(tester, frames: 20);
      },
      arrived: find.text(switch (state) {
        'unavailable' => 'Food unavailable',
        'lookup error' => 'Could not open this food',
        _ => 'Current default serving',
      }),
      waypoints: state == 'current' || state == 'removed serving'
          ? <Finder>[find.text('Calories'), find.text('Cholesterol')]
          : <Finder>[],
      farEnd: find.text('Go back'),
    ),
  SweptSurface(
    // Not a sheet: a branch inside the day's summary card. The guard cannot
    // find this one by reading the source, which is exactly why the list is
    // written by hand rather than generated from it.
    name: 'the expanded day summary',
    opensFrom: 'lib/features/plan/day_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      await tools.reach(find.text('Details'));
    },
    arrived: find.text('Less'),
    farEnd: find.text('Cholesterol'),
  ),
  SweptSurface(
    name: 'per-serving recipe nutrition',
    opensFrom: 'lib/features/recipes/recipe_detail_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.bring(find.text('Per serving'));
    },
    arrived: find.ancestor(
      of: find.text('Per serving'),
      matching: find.byWidgetPredicate(
        (Widget widget) => widget is ChoiceChip && widget.selected,
      ),
    ),
    farEnd: find.text('Directions'),
  ),
  SweptSurface(
    name: 'whole-dish recipe nutrition',
    opensFrom: 'lib/features/recipes/recipe_detail_screen.dart',
    isInline: true,
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Whole dish'));
    },
    arrived: find.ancestor(
      of: find.text('Whole dish'),
      matching: find.byWidgetPredicate(
        (Widget widget) => widget is ChoiceChip && widget.selected,
      ),
    ),
    farEnd: find.text('Directions'),
  ),
  SweptSurface(
    name: 'planning the recipe being read',
    opensFrom: 'lib/features/recipes/recipe_plan_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Plan'));
    },
    arrived: find.text('My plan'),
    farEnd: find.text('Cancel'),
  ),
  SweptSurface(
    name: 'choosing the recipe plan date',
    opensFrom: 'lib/features/recipes/recipe_plan_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Plan'));
      await tools.reach(find.byKey(const ValueKey<String>('recipe-plan-date')));
    },
    arrived: find.text('Plan date'),
    farEnd: find.text('Cancel'),
  ),
  SweptSurface(
    name: 'shopping for the recipe being read',
    opensFrom: 'lib/features/shopping/add_to_list_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Slow chilli with all the trimmings'));
      await tools.reach(find.text('Shop'));
    },
    arrived: find.text('How many'),
    farEnd: find.text('Add to the list'),
  ),
  SweptSurface(
    name: 'the recipe filters',
    opensFrom: 'lib/features/recipes/recipe_filters_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.textContaining(RegExp(r'^Filters')));
    },
    arrived: find.text('Filter recipes'),
    farEnd: find.text('Done'),
  ),
  SweptSurface(
    name: 'the ways to add a recipe',
    opensFrom: 'lib/features/recipes/add_recipe_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
    },
    arrived: find.text('Write a recipe'),
    farEnd: find.text('Generate with AI'),
  ),
  SweptSurface(
    name: 'the ways to add a food',
    opensFrom: 'lib/features/foods/add_food_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Foods');
      await tools.reach(find.text('Add food'));
    },
    arrived: find.text('Scan a barcode'),
    // The last row, and the one a short screen loses first. The harness has
    // no label reader, so the middle row is not there to reach.
    farEnd: find.text('Enter it by hand'),
  ),
];

class _InterruptedCookProgress extends FakeCookSessionStore {
  _InterruptedCookProgress({required this.reset});

  final bool reset;
  bool _failed = false;

  @override
  Future<StoredCookProgress?> read(String recipeId, {required DateTime now}) {
    if (!reset && !_failed) {
      _failed = true;
      return Future<StoredCookProgress?>.error(
        StateError('Synthetic interrupted cook read'),
      );
    }
    return super.read(recipeId, now: now);
  }

  @override
  Future<void> clear(String recipeId) {
    if (reset && !_failed) {
      _failed = true;
      return Future<void>.error(StateError('Synthetic interrupted cook reset'));
    }
    return super.clear(recipeId);
  }
}

/// Surfaces that open a sheet or a dialog and are **not** swept yet.
///
/// Each needs a reason, and the reason is meant to be uncomfortable to write.
/// The list exists so that what is uncovered is *enumerated* rather than
/// unknown — and so that adding a new sheet has to pass through a decision
/// rather than through nobody noticing.
const Map<String, String> notSweptYet = <String, String>{
  'lib/features/account/settings_screen.dart':
      'Confirmation dialogs for sign-out and delete. Reaching them needs a '
      'signed-in session the widget harness does not have.',
  'lib/features/foods/food_editor_screen.dart':
      'A discard-changes dialog, reachable only from a dirty editor. The '
      'duplicate warning in the same file *is* reachable and is walked at '
      'three times the text by use_existing_test.dart — this guard is per '
      'file, so one entry covers both and the second one would have '
      'shipped unwalked without somebody noticing. Task e31da6f0.',
  'lib/features/foods/menu_import_screen.dart':
      'The reimport review, which asks what to do with menu rows the new '
      'document does not mention. Its behaviour is covered by '
      'menu_reimport_screen_test.dart; it is NOT walked at large text by '
      'anything. Reaching it takes two screens and a pasted document, and at '
      'twice the text on a 320-point phone the lazy lists on the way have '
      'not built the controls the walk needs — the attempt spent its time '
      'scrolling rather than saying anything about the dialog. Said plainly '
      'rather than left as a test that looks like coverage. It is an '
      'AlertDialog with `scrollable: true`, the shape that held for the '
      'duplicate warning at three times the text, so the risk is low and '
      'unmeasured rather than unknown.',
  'lib/features/foods/merge_screen.dart':
      'The merge review sheet. Walked at three times the text by '
      'merge_screen_test.dart instead — it needs two foods that look '
      'alike in the library, which the sweep fixture has no reason to '
      'carry, and the flow sweep cannot make one up.',
  'lib/features/foods/food_picker.dart':
      'Opened from the recipe editor while matching an ingredient — several '
      'screens in, and needs a library with an unmatched line in it.',
  'lib/features/foods/read_walmart_link_sheet.dart':
      'Dedicated walmart_link_sheet_test.dart and walmart_link_render_test.dart '
      'exercise picker, read, cancel, miss and retry with synthetic responses, '
      'including 320px at 200% and 300%; the general sweep has no reader.',
  'lib/features/foods/read_label_sheet.dart':
      'Needs a photo picker and a label-reading response to get past its '
      'first frame.',
  'lib/features/plan/week_template_sheet.dart':
      'Saving and applying a week both need a week with something in it.',
  'lib/features/recipes/collections_sheet.dart':
      'Opened from a recipe that is in the library, on its detail screen.',
  'lib/features/recipes/recipe_editor_screen.dart':
      'A discard-changes dialog, reachable only from a dirty editor.',
};
