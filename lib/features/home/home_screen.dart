import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/shell/sections.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../recipes/timer_bar.dart';

/// The way into the house (spec §6.2, and the November 2026 templates).
///
/// Hearth is one app with several rooms in it, and this is the landing that
/// says so. Four cards of equal weight said something untrue about it: the
/// rooms are not equal, one of them is the reason the app exists, and the
/// screen read as a menu of four equivalent choices.
///
/// So the first room leads — its name in the serif, what is in it, and the
/// one thing it offers from the front door — and the rest are rows under it.
/// A row is still a door; what it is not is a claim to the same share of the
/// screen.
///
/// **Still no live data.** A hero showing today's remaining calories would be
/// the obvious next thing and would wire this screen to Nutrition's providers
/// — the exact coupling the registry exists to avoid. The button is not that:
/// it is an action the registry declares, so this screen knows that a section
/// may have one and how to draw it, and does not know what logging is or
/// which room does it.
///
/// One thing the templates draw that is not here yet: the illustrations. They
/// are hand-authored vector paths and their own change.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// The column stops widening here. On a Mac a single card stretched across
  /// 1400px reads as a stray banner; a centred column reads as a page.
  ///
  /// Held in the theme beside the width the *lists* use, so the two are one
  /// decision rather than two numbers in two files that happen to differ.
  static const double maxContentWidth = HearthLayout.launcherWidth;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      // A running timer belongs to the app, not to the recipe you happen to be
      // looking at (spec §5.2) — and going home is a route swap, which takes
      // the shell and the bar it carries with it. So every screen that can be
      // the whole of what you are looking at carries one: the shell, the recipe
      // you opened from it, and this. It renders nothing when nothing is on.
      bottomNavigationBar: const CookTimerBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                HearthSpacing.xl,
                gutter,
                HearthSpacing.xxl,
              ),
              children: <Widget>[
                const _Masthead(),
                const SizedBox(height: HearthSpacing.xl),
                // The first built room leads. Registry order already means
                // "what is built first, then what is coming", so which room
                // that is stays a fact about the registry rather than a
                // name written into this screen.
                //
                // Guarded, because `builtSections` is a runtime filter over
                // editable data and the type system does not promise it
                // anything: a registry of nothing but planned rooms is one
                // line away, and `.first` on the app's root screen would
                // throw before its first frame. The loop this replaced
                // degraded to a masthead and a footer, and so does this.
                if (builtSections.isNotEmpty) ...<Widget>[
                  _SectionHero(section: builtSections.first),
                  const SizedBox(height: HearthSpacing.xl),
                ],
                for (final BuiltSection section in builtSections.skip(1))
                  _SectionRow(section: section),
                const SizedBox(height: HearthSpacing.xl),
                const _ComingLater(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's own name, and the way to its settings.
///
/// Settings live here because they belong to the app rather than to any one
/// room. The recipe library keeps its own way in as well: that is the only
/// route to settings from inside a section, and taking it away would mean
/// leaving the section to change the theme.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // The strapline under the wordmark is gone. It said what the app is for
    // directly above a hero that says what the first room is for, and two
    // sentences of orientation in a column is one more than anybody reads.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Semantics(
                header: true,
                container: true,
                child: Text('Hearth', style: context.text.recipeTitle),
              ),
            ),
            const SizedBox(width: HearthSpacing.sm),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.sm),
        Divider(height: 1, thickness: 1, color: colors.outlineStrong),
      ],
    );
  }
}

/// The room that leads, and the one thing it offers from the front door.
///
/// Its name in the serif at the size the templates draw it, what is in it,
/// a primary action if the registry gave it one, and the way in under that.
///
/// The way in is the link, not the whole block. A hero whose every pixel is
/// a button swallows the button inside it: the only thing on this screen
/// that should be bigger than "open the room" is "log a meal", and nesting
/// one tap target inside another is how a press lands on the wrong one.
class _SectionHero extends ConsumerWidget {
  const _SectionHero({required this.section});

  final BuiltSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    void enter() => context.go(
      // Back where you were in it, not to its first tab (U08).
      ref.read(lastDestinationProvider.notifier).pathFor(section),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // A heading, not merely heading-sized. The masthead above marks
        // itself as one, so without this a screen reader navigating by
        // headings finds the app's name and nothing for the room filling
        // most of the screen (spec §6.3).
        Semantics(
          header: true,
          child: Text(section.label, style: context.text.recipeTitle),
        ),
        const SizedBox(height: HearthSpacing.xs),
        Text(
          section.blurb,
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
        if (section.primaryAction case final SectionAction action) ...<Widget>[
          const SizedBox(height: HearthSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              // Sized for a kitchen rather than to the 48pt floor, like the
              // day screen's: it is the same action and the same hands
              // (spec §5.6, §6.3).
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(HearthTouch.kitchenTarget),
              ),
              onPressed: () => action.onTap(context),
              icon: Icon(action.icon),
              label: Text(action.label, style: context.text.label),
            ),
          ),
        ],
        const SizedBox(height: HearthSpacing.sm),
        // No hand-written semantics over this one. It used to carry
        // [AppSection.semanticLabel] with the button's own label excluded,
        // which left a control reading "Open Nutrition" answering to
        // "Nutrition. Recipes, meal plans, shopping lists, and nutrition
        // logs." — so saying the words on it did nothing, which is what
        // WCAG 2.5.3 is about. The button's own label is the right one,
        // and the room's name and sentence are read as themselves above.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enter,
            // The arrow after the words, which is the direction it goes.
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(section.openLabel),
          ),
        ),
      ],
    );
  }
}

/// One of the other rooms, and the way into it.
///
/// A row rather than a card. The cards were all the same size, which said
/// the rooms were of the same importance — and on the one screen whose job
/// is to point at the room you want, that is the wrong thing to say.
class _SectionRow extends ConsumerWidget {
  const _SectionRow({required this.section});

  /// Built, because the row's whole job is to be the way in. A room that is
  /// only named has no `path` to offer, and the type says so.
  final BuiltSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    void enter() => context.go(
      // Back where you were in it, not to its first tab (U08).
      ref.read(lastDestinationProvider.notifier).pathFor(section),
    );

    return Semantics(
      button: true,
      label: section.semanticLabel,
      onTap: enter,
      container: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Divider(height: 1, thickness: 1, color: colors.outline),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enter,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: HearthSpacing.md),
                child: Row(
                  children: <Widget>[
                    // Muted, not accent. The hero below the masthead already
                    // spends the accent twice — the button and the link —
                    // and a tinted icon on every row after it is the 60/30/10
                    // leak §6.1 is about.
                    Icon(section.icon, size: 28, color: colors.textSecondary),
                    const SizedBox(width: HearthSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            section.label,
                            style: context.text.sectionHeader,
                          ),
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            section.blurb,
                            style: context.text.metadata.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: HearthSpacing.sm),
                    Icon(Icons.chevron_right, color: colors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the house does not have yet.
///
/// A sentence, not a control: nothing here can be tapped, so nothing here can
/// disappoint. Its words come from the registry, so furnishing Fitness takes
/// it out of this line with no copy to rewrite — and when the last one is
/// furnished the line stops rendering entirely.
///
/// It reads [AppSection.isFurnished] rather than `unbuiltSections`, which is
/// the narrower question of whether a room has tabs at all. Since spec §11
/// every room has tabs, so `unbuiltSections` is empty and this line had
/// stopped rendering while three of the four cards above it still opened on
/// "Not built yet." — four identical doors and no way to tell which rooms are
/// empty, which is precisely what this line exists to prevent.
class _ComingLater extends StatelessWidget {
  const _ComingLater();

  @override
  Widget build(BuildContext context) {
    final List<AppSection> later = appSections
        .where((AppSection s) => !s.isFurnished)
        .toList(growable: false);
    if (later.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    // A proper list, because the middot has taken over the job the old
    // colon was doing. The names used to be joined by commas alone to stop
    // "Fitness and Health" reading as the sentence continuing — after a
    // separator there is no sentence left to continue.
    final List<String> names = <String>[
      for (final AppSection section in later) section.label,
    ];
    final String listed = names.length < 2
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.xs),
      child: Text(
        'In development · $listed',
        textAlign: TextAlign.center,
        // Upright, although the templates draw it in italic. Hearth bundles
        // one roman face per family and no italic, so `FontStyle.italic`
        // here is a synthesised slant — and at twelve points in the muted
        // tone it is thin enough that the §6.3 contrast guideline cannot
        // find a glyph pixel anywhere near the text colour: it measured the
        // darkest thing in the line at 1.64:1 against the page. The middot
        // and the muted tone already say "aside"; a faux italic was only
        // ever going to say it worse.
        //
        // Not caught here, either. The guideline reads painted pixels, so
        // what it measures depends on how the glyphs rasterise, and this
        // failed on CI's fonts while passing on a Mac's.
        style: context.text.metadata.copyWith(color: colors.textMuted),
      ),
    );
  }
}
