import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

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
  });

  /// What it is, in the words the test failure will use.
  final String name;

  /// The file in `lib/` that opens it. This is what the guard matches on.
  final String opensFrom;

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
}

/// The scrolling and tapping a sweep needs, shared by every surface.
class SweepTools {
  const SweepTools(this._tester);

  final WidgetTester _tester;

  /// The last *vertical* scroll view.
  ///
  /// Every text field contains a horizontal one of its own for its editable,
  /// so "the last scrollable" on a sheet full of fields is a text box, and
  /// dragging that goes nowhere.
  static Finder get verticalScroller => find
      .byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable &&
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
}

/// The surfaces this sweep visits.
///
/// Everything in `lib/` that opens a sheet or a dialog is either named here
/// or listed in [notSweptYet] with a reason. There is no third option: that
/// is the whole point.
final List<SweptSurface> sweptSurfaces = <SweptSurface>[
  SweptSurface(
    name: "the day's targets",
    opensFrom: 'lib/features/plan/macro_targets_sheet.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      // The card's own caption, and now the only thing wearing it: it used to
      // read "Today" — the page's title as well — so this had to reach for
      // the second one and hope the order held (review F05).
      await tools.reach(find.text('Daily totals'));
    },
    arrived: find.text('Weekly targets'),
    farEnd: find.text('Save targets'),
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
      // The harness seeds a line, because the list screen has two shapes: an
      // empty one still leads with its setup, and `Manage list` is what
      // replaces that once there is something to shop for (review §6.2.5).
      await tools.reach(find.text('Manage list'));
    },
    arrived: find.text('Include seasonings'),
    farEnd: find.text('Rebuild from the plan'),
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
    name: "a meal's own options",
    opensFrom: 'lib/features/plan/day_screen.dart',
    open: (WidgetTester tester, SweepTools tools) async {
      await tools.tab('Plan');
      // Behind a long press, not a tap: tapping the row toggles it logged and
      // leaves the day screen exactly where it was.
      final Finder meal = await tools.bring(
        find.text('Slow chilli with all the trimmings'),
      );
      await tester.longPress(meal);
      await pumpFrames(tester, frames: 12);
    },
    arrived: find.text('Edit portion'),
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
  'lib/features/foods/merge_screen.dart':
      'The merge review sheet. Walked at three times the text by '
      'merge_screen_test.dart instead — it needs two foods that look '
      'alike in the library, which the sweep fixture has no reason to '
      'carry, and the flow sweep cannot make one up.',
  'lib/features/foods/food_picker.dart':
      'Opened from the recipe editor while matching an ingredient — several '
      'screens in, and needs a library with an unmatched line in it.',
  'lib/features/foods/read_label_sheet.dart':
      'Needs a photo picker and a label-reading response to get past its '
      'first frame.',
  'lib/features/plan/day_picker_sheet.dart':
      'Reached from "Add to several days", which is itself inside the log '
      'sheet\'s confirm view.',
  'lib/features/plan/week_template_sheet.dart':
      'Saving and applying a week both need a week with something in it.',
  'lib/features/recipes/collections_sheet.dart':
      'Opened from a recipe that is in the library, on its detail screen.',
  'lib/features/recipes/cook_along_screen.dart':
      'A finish dialog at the end of a cook-along, which needs a recipe with '
      'steps and a cook actually started.',
  'lib/features/recipes/recipe_editor_screen.dart':
      'A discard-changes dialog, reachable only from a dirty editor.',
  'lib/features/recipes/timer_bar.dart':
      'The timers sheet only exists while a timer is running.',
  'lib/features/shopping/shopping_amount_sheet.dart':
      'Needs a built shopping list with a line on it.',
  'lib/features/shopping/shopping_export_sheet.dart':
      'Needs a built shopping list and an export destination.',
};
