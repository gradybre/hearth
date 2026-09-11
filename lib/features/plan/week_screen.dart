import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/a11y/accessibility.dart';
import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/macro_rings.dart';
import '../../app/widgets/minor_nutrient_bars.dart';
import '../../app/widgets/reading_column.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/planning/week.dart';
import '../../domain/planning/week_summary.dart';
import '../../domain/planning/week_template.dart';
import 'entry_resolver.dart';
import 'week_template_sheet.dart';

/// The week, as seven days you can read against each other (spec §5.6,
/// review §7.2).
///
/// This is the step-back view. It used to be a day selector wearing a week's
/// name: a strip of seven thirty-point rings above one day's four large ones,
/// which spent 290 points of a 390x844 phone on one day and 116 on all seven,
/// and pushed the week's only aggregate off the bottom of the screen
/// entirely. Comparing two days meant selecting each in turn.
///
/// Seven rows now, each carrying its own figures, with the detail behind an
/// expansion rather than in front of it. Tapping a row still selects the day
/// without leaving the week, and `Open this day` is still the way into
/// logging.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  /// The day whose detail is showing, if any.
  ///
  /// Nothing is open to begin with, and that is the point: seven rows and the
  /// week's average all fit a phone, and one expansion is 400 points of rings
  /// and bars that pushed the average out of the list entirely. §7.2 makes
  /// expanding an action — "expand a row or open Day for details" — rather
  /// than a state the screen starts in.
  ///
  /// Local rather than derived from the selected day, which persists across
  /// visits: coming back to the week should show the week.
  DateTime? _open;

  @override
  Widget build(BuildContext context) {
    final DateTime selected = ref.watch(selectedDateProvider);
    final List<DateTime> days = weekOf(selected);
    final MacroTargets? targets = ref.watch(dayTargetsProvider).value;

    final Map<String, Recipe> recipes = <String, Recipe>{
      for (final Recipe r
          in ref.watch(recipeLibraryProvider).value ?? const <Recipe>[])
        r.id: r,
    };
    final Map<String, Food> foods = <String, Food>{
      for (final Food f
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        f.id: f,
    };

    final AsyncValue<Map<DateTime, List<MealPlanEntry>>> week = ref.watch(
      weekEntriesProvider,
    );
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return week.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace s) =>
          Center(child: Text('The week could not be read.\n$e')),
      data: (Map<DateTime, List<MealPlanEntry>> byDay) {
        // The parts rather than the totals, so a day can say how much of
        // itself its minor-nutrient numbers actually cover. A total reads the
        // same from six foods as from one of six (spec §5.6).
        final Map<DateTime, List<ResolvedEntry>> resolved =
            <DateTime, List<ResolvedEntry>>{
              for (final DateTime day in days)
                day: EntryResolver.resolveAll(
                  byDay[day] ?? const <MealPlanEntry>[],
                  recipes: recipes,
                  foods: foods,
                ),
            };
        final Map<DateTime, List<Macros>> eatenParts = <DateTime, List<Macros>>{
          for (final MapEntry<DateTime, List<ResolvedEntry>> day
              in resolved.entries)
            day.key: EntryResolver.eatenParts(day.value),
        };
        // Beside the parts, never inferred from them. `fromParts` falls back
        // to reading coverage off each total, which is the very inference this
        // exists to replace — so a caller that forgets fails quietly, and this
        // screen forgot once already.
        final Map<DateTime, List<NutrientCoverage>> eatenCoverage =
            <DateTime, List<NutrientCoverage>>{
              for (final MapEntry<DateTime, List<ResolvedEntry>> day
                  in resolved.entries)
                day.key: EntryResolver.eatenCoverage(day.value),
            };
        final Map<DateTime, Macros> eaten = <DateTime, Macros>{
          for (final MapEntry<DateTime, List<Macros>> day in eatenParts.entries)
            day.key: Macros.sum(day.value),
        };

        // What each day amounts to, in the four states §7.2 asks the week to
        // keep apart. The counts are of *logged* entries rather than of
        // entries: a Friday with a planned dinner and nothing eaten is not a
        // day that has been logged, and a day logged as nothing is.
        final WeekSummary summary = WeekSummary(<WeekDay>[
          for (final DateTime day in days)
            WeekDay(
              date: day,
              eaten: eaten[day] ?? Macros.zero,
              planned: EntryResolver.stillPlanned(
                resolved[day] ?? const <ResolvedEntry>[],
              ),
              loggedCount: (byDay[day] ?? const <MealPlanEntry>[])
                  .where((MealPlanEntry e) => e.isLogged)
                  .length,
              plannedCount: (byDay[day] ?? const <MealPlanEntry>[])
                  .where((MealPlanEntry e) => !e.isLogged)
                  .length,
            ),
        ]);

        // Bounded like the other section screens (review §6.2.7): seven rows
        // of figures stretched across a 1280-point window is not a column
        // anybody reads down.
        return ReadingColumn(
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 3),
            children: <Widget>[
              _WeekHeader(days: days),
              const SizedBox(height: HearthSpacing.lg),
              // Seven rows, each with its own figures, and the one that is
              // selected opened in place. Selecting stays here rather than
              // dropping into the day: the point of the week is to be able to
              // look across it without leaving it.
              _DayRows(
                summary: summary,
                selected: selected,
                targets: targets,
                eatenParts: eatenParts,
                eatenCoverage: eatenCoverage,
                open: _open,
                onSelect: (DateTime day) {
                  ref.read(selectedDateProvider.notifier).select(day);
                  // A second tap closes it again, so a row is a disclosure
                  // rather than a one-way door.
                  setState(
                    () => _open = _open != null && isSameDay(_open!, day)
                        ? null
                        : day,
                  );
                },
                // The row's own day, not whichever the week has selected. The
                // open row is remembered across a change of week and the
                // selection is not, so stepping to next week and back with
                // the today button re-opened Wednesday's detail above a
                // button that opened Thursday.
                onOpen: (DateTime day) {
                  ref.read(selectedDateProvider.notifier).select(day);
                  ref.read(planViewProvider.notifier).show(PlanView.day);
                },
              ),
              const SizedBox(height: HearthSpacing.lg),
              _WeekTotals(summary: summary, targets: targets),
            ],
          ),
        );
      },
    );
  }
}

/// The seven days, one row each, with the selected one opened in place.
///
/// One card with hairlines between the rows rather than seven cards: the week
/// is one object and the days are its rows, and seven bordered boxes is the
/// "a card for nearly everything" complaint (review §6.2.2).
class _DayRows extends StatelessWidget {
  const _DayRows({
    required this.summary,
    required this.selected,
    required this.open,
    required this.targets,
    required this.eatenParts,
    required this.eatenCoverage,
    required this.onSelect,
    required this.onOpen,
  });

  final WeekSummary summary;

  /// The day the week is pointing at, marked but not expanded.
  final DateTime selected;

  /// The day whose detail is showing, if any.
  final DateTime? open;

  final MacroTargets? targets;
  final Map<DateTime, List<Macros>> eatenParts;
  final Map<DateTime, List<NutrientCoverage>> eatenCoverage;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpen;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      // So a row's ink stays inside the rounded corner.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < summary.days.length; i++) ...<Widget>[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: colors.outline),
              _DayRow(
                day: summary.days[i],
                targets: targets,
                selected: isSameDay(summary.days[i].date, selected),
                open: open != null && isSameDay(open!, summary.days[i].date),
                eatenParts:
                    eatenParts[summary.days[i].date] ?? const <Macros>[],
                eatenCoverage:
                    eatenCoverage[summary.days[i].date] ??
                    const <NutrientCoverage>[],
                onSelect: () => onSelect(summary.days[i].date),
                onOpen: () => onOpen(summary.days[i].date),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One day, as a line you can read against the six above and below it.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.targets,
    required this.selected,
    required this.open,
    required this.eatenParts,
    required this.eatenCoverage,
    required this.onSelect,
    required this.onOpen,
  });

  final WeekDay day;
  final MacroTargets? targets;

  /// Whether the week is pointing at this day.
  final bool selected;

  /// Whether its detail is showing.
  final bool open;

  final List<Macros> eatenParts;
  final List<NutrientCoverage> eatenCoverage;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  /// What this day says about itself, beside the figures.
  ///
  /// Four different facts, and the words are the whole of how they are told
  /// apart — never the colour of a bar (spec §6.3).
  String get _state => switch (day.state) {
    DayLogState.logged => '${day.loggedCount} logged',
    // Said in full rather than as a zero: a fast and a forgotten day both
    // show 0, and only one of them is a statement about what was eaten.
    DayLogState.loggedAsNothing => 'logged as nothing',
    DayLogState.plannedOnly => 'nothing logged yet',
    DayLogState.untouched => 'nothing logged',
  };

  /// The eaten figure, or a dash where there is no figure to give.
  ///
  /// A planned day shows what the plan would come to, marked as a plan. An
  /// untouched one shows nothing at all, because zero is a claim.
  String _eatenText() => switch (day.state) {
    DayLogState.logged || DayLogState.loggedAsNothing =>
      targets?.kcal == null
          ? '${day.eaten.kcal.round()} kcal'
          : '${day.eaten.kcal.round()} / ${targets!.kcal.round()} kcal',
    // Only when the plan actually projects something. An entry whose food
    // was never matched contributes no calories, and "planned 0 kcal" says
    // the plan comes to nothing — which is a claim, and a different one.
    DayLogState.plannedOnly =>
      day.planned.kcal > 0 ? 'planned ${day.planned.kcal.round()} kcal' : '—',
    DayLogState.untouched => '—',
  };

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // One read of the clock for the row, not one for the label and one for
    // the weight: two calls can straddle midnight and disagree about which
    // day is today, on the one screen whose job is attributing food to days.
    final bool today = day.isToday(DateTime.now());
    final String name =
        '${shortWeekdayName(day.date)} ${day.date.day}'
        '${today ? ' · Today' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          selected: selected,
          expanded: open,
          // The whole row in one announcement, in the order it is read:
          // which day, what it came to, and which kind of day it was. The
          // weekday is spelled out and the date carries its month — a bare
          // "1" is unreadable in a week that straddles two, and the screen
          // shows three letters and a numeral.
          label:
              '${weekdayName(day.date)} ${shortDate(day.date)}'
              '${today ? ', today' : ''}. '
              '${_eatenText()}. $_state',
          onTap: onSelect,
          container: true,
          excludeSemantics: true,
          child: Material(
            color: selected ? colors.surfaceSunken : Colors.transparent,
            child: InkWell(
              onTap: onSelect,
              child: ConstrainedBox(
                // Android's 48 rather than the shared 44: this is a bare
                // InkWell, so nothing pads it the way a ListTile pads itself,
                // and the §6.3 sweep checks both guidelines.
                constraints: const BoxConstraints(
                  minHeight: HearthTouch.androidTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.md,
                    vertical: HearthSpacing.sm,
                  ),
                  // A wrap, not a row: at three times the text a date, a pair
                  // of calorie figures and a protein figure are far wider
                  // than a 320-point phone, and honouring type means the
                  // layout gives way rather than the words (spec §6.3).
                  child: Wrap(
                    spacing: HearthSpacing.md,
                    runSpacing: HearthSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      // A floor, not a fixed width. 84 points lines the seven
                      // names up at ordinary text; at three times it, "Mon 7"
                      // does not fit in 84 and a fixed box wrapped every row
                      // to three lines. The column alignment is worth having
                      // and is not worth honouring dynamic type less for
                      // (spec §6.3).
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 84),
                        child: Text(
                          name,
                          style: context.text.body.copyWith(
                            fontWeight: today
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Text(
                        _eatenText(),
                        style: context.text.body.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      // §7.2 names protein among the four things a row
                      // carries: it is the number this household steers by,
                      // and the one a day can miss while its calories look
                      // right.
                      if (day.state == DayLogState.logged)
                        if (targets?.proteinG case final double protein)
                          Text(
                            'P ${day.eaten.proteinG.round()}/'
                            '${protein.round()}',
                            style: context.text.metadata.copyWith(
                              color: colors.textSecondary,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      Text(
                        _state,
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HearthSpacing.md,
              0,
              HearthSpacing.md,
              HearthSpacing.md,
            ),
            child: _DayDetail(
              targets: targets,
              eatenParts: eatenParts,
              eatenCoverage: eatenCoverage,
              onOpen: onOpen,
            ),
          ),
      ],
    );
  }
}

/// The rings and the minor nutrients, for the row that is open.
///
/// The same widgets the day view uses, so the same four numbers cannot come
/// to read two different ways on two screens. §7.2 asks for exactly this:
/// "existing rings/minors move into that expansion".
class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.targets,
    required this.eatenParts,
    required this.eatenCoverage,
    required this.onOpen,
  });

  final MacroTargets? targets;
  final List<Macros> eatenParts;
  final List<NutrientCoverage> eatenCoverage;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (targets == null)
          Text(
            'No targets set for this week.',
            style: context.text.body.copyWith(color: colors.textSecondary),
          )
        else if (DayProgress.fromParts(
              parts: eatenParts,
              coverage: eatenCoverage,
              targets: targets!,
            )
            case final DayProgress progress) ...<Widget>[
          MacroRings(progress: progress),
          // The same three, on the day the week has selected. A trend is
          // where these actually mean something, and the week is the only
          // screen that shows one (spec §5.6).
          const SizedBox(height: HearthSpacing.lg),
          MinorNutrientBars(progress: progress),
        ],
        const SizedBox(height: HearthSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onOpen,
            // A row selects rather than navigates, so the way in has to be
            // said out loud rather than left as a thing you discover.
            child: const Text('Open this day'),
          ),
        ),
      ],
    );
  }
}

class _WeekHeader extends ConsumerWidget {
  const _WeekHeader({required this.days});

  final List<DateTime> days;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get _range {
    final DateTime from = days.first;
    final DateTime to = days.last;
    if (from.month == to.month) {
      return '${from.day}–${to.day} ${_months[from.month - 1]}';
    }
    return '${from.day} ${_months[from.month - 1]} – '
        '${to.day} ${_months[to.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: <Widget>[
      // The range, and no page title above it. "This week" sat under a
      // Day/Week toggle that already says Week, under a "Nutrition" section
      // header, under "Home" — four headings before any food (review
      // §6.2.1) — and at twice the text on a 320-point phone those two words
      // alone were 490 points tall in a 380-point viewport.
      Expanded(
        child: Text(
          _range,
          style: context.text.sectionHeader.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(-7),
        tooltip: 'Previous week',
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).today(),
        tooltip: 'Go to this week',
        icon: const Icon(Icons.today_outlined),
      ),
      IconButton(
        onPressed: () => ref.read(selectedDateProvider.notifier).shiftDays(7),
        tooltip: 'Next week',
        icon: const Icon(Icons.chevron_right),
      ),
      // The two template actions, in words. They were icon-only with their
      // meaning in a tooltip — a hover, on a device with no pointer — and a
      // bookmark and a bookmark-with-a-plus are not two things anybody tells
      // apart at sixteen points (review §7.2, spec §6.3). The three arrows
      // beside them stay as arrows: previous, today and next are
      // conventional and unambiguous.
      PopupMenuButton<VoidCallback>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'More',
        onSelected: (VoidCallback run) => run(),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
          PopupMenuItem<VoidCallback>(
            value: () => _save(context, ref),
            child: Text(
              'Save this week to use again',
              style: context.text.body,
            ),
          ),
          PopupMenuItem<VoidCallback>(
            value: () => _apply(context, ref),
            child: Text('Use a saved week', style: context.text.body),
          ),
        ],
      ),
    ],
  );

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final String? name = await showSaveTemplateSheet(context);
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final WeekTemplate? saved = await ref
        .read(planRepositoryProvider)
        .saveWeekAsTemplate(anchor: ref.read(selectedDateProvider), name: name);
    ref.invalidate(weekTemplatesProvider);
    if (!context.mounted) return;

    // Cleared first: these two actions sit next to each other, and a stale
    // "Saved" message queued in front of a fresh "Added" one means waiting
    // four seconds to find out what just happened.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved == null
                // Saving an empty week is something you would only do by
                // accident, so it says so rather than making a template of
                // nothing.
                ? 'Nothing is planned this week yet.'
                : 'Saved "${saved.name}" — ${saved.entries.length} '
                      '${saved.entries.length == 1 ? 'meal' : 'meals'}.',
          ),
        ),
      );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final WeekTemplate? template = await showApplyTemplateSheet(context);
    if (template == null || !context.mounted) return;

    final int added = await ref
        .read(planRepositoryProvider)
        .applyTemplate(
          template: template,
          anchor: ref.read(selectedDateProvider),
        );
    if (!context.mounted) return;

    ref.invalidate(dayEntriesProvider);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // Says how many it added rather than "done": applying is additive, so
          // the count is how you tell it landed on a week that already had
          // things on it.
          content: Text(
            'Added $added ${added == 1 ? 'meal' : 'meals'} '
            'from "${template.name}".',
          ),
        ),
      );
  }
}

/// The week's average against target.
///
/// An average rather than a sum: targets are daily, so a total of seven days
/// against one day's target would be meaningless, and "you ate 15,000
/// calories" tells you nothing without dividing it back down yourself.
///
/// What counts is having *logged*, not having eaten. This used to filter on
/// `!macros.isZero`, which quietly dropped a day somebody fasted and stated —
/// so four days at 2,000 and a Saturday at nothing reported a daily average
/// of 2,000 rather than 1,600, four hundred calories a day of food nobody
/// ate. Days with nothing on them are excluded, because there is no number to
/// average, and the count says how many so an average over five is not read
/// as an average over seven (review §7.2).
class _WeekTotals extends StatelessWidget {
  const _WeekTotals({required this.summary, required this.targets});

  final WeekSummary summary;
  final MacroTargets? targets;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    if (summary.dailyAverage case final Macros average) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Daily average', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xxs),
            Text(
              <String>[
                summary.loggedDays == 1
                    ? 'over 1 logged day'
                    : 'over ${summary.loggedDays} logged days',
                if (summary.daysNotLogged > 0)
                  '${summary.daysNotLogged} not logged',
              ].join(' · '),
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.md),
            _MacroRow(macros: average, targets: targets),
          ],
        ),
      );
    }

    return _Card(
      child: Text(
        'Nothing logged this week yet.',
        style: context.text.body.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.macros, this.targets});

  final Macros macros;
  final MacroTargets? targets;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final int columns = A11y.macroColumns(context);

    final List<(String, double, double?)> values = <(String, double, double?)>[
      ('kcal', macros.kcal, targets?.kcal),
      ('protein', macros.proteinG, targets?.proteinG),
      ('carbs', macros.carbG, targets?.carbG),
      ('fat', macros.fatG, targets?.fatG),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = HearthSpacing.md;
        final double itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final (String label, double value, double? target) in values)
              SizedBox(
                width: itemWidth,
                child: Semantics(
                  label: target == null
                      ? '$label ${value.round()}'
                      : '$label ${value.round()} of ${target.round()}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        value.round().toString(),
                        style: context.text.ingredient.copyWith(fontSize: 22),
                      ),
                      Text(
                        target == null ? label : '$label of ${target.round()}',
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: child,
      ),
    );
  }
}
