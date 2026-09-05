import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/sections.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../recipes/timer_bar.dart';

/// The way into the house (spec §6.2).
///
/// Hearth is one app with several rooms in it, and this is the landing that
/// says so. Nutrition is the only room that is built; the rest are named in a
/// single line at the bottom rather than laid out as tiles you cannot press.
///
/// That is the whole design argument. A grid with one live tile in it reads as
/// a screen that failed to load, and a grid padded out with dead ones teaches
/// people that tapping does nothing — which is worse, because it is a lesson
/// they will carry into the tiles that *do* work. A single wide card, under a
/// masthead, with a sentence underneath saying what is coming, reads as
/// deliberate at one section and still reads as deliberate at four.
///
/// Deliberately no live data. A card showing today's remaining calories would
/// be the obvious next thing and would also wire the home screen to Nutrition's
/// providers — the exact coupling the section registry exists to avoid. When a
/// section wants to say something on this screen it should say it through the
/// registry, not by being special.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// The column stops widening here. On a Mac a single card stretched across
  /// 1400px reads as a stray banner; a centred column reads as a page.
  static const double maxContentWidth = 640;

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
                for (final BuiltSection section in builtSections) ...<Widget>[
                  _SectionCard(section: section),
                  const SizedBox(height: HearthSpacing.md),
                ],
                const SizedBox(height: HearthSpacing.sm),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                container: true,
                child: Text('Hearth', style: context.text.recipeTitle),
              ),
              const SizedBox(height: HearthSpacing.xxs),
              Text(
                'Everything the house keeps track of.',
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: HearthSpacing.sm),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/household'),
        ),
      ],
    );
  }
}

/// One room, and the way into it.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  /// Built, because the card's whole job is to be the way in. A room that is
  /// only named has no `path` to offer, and the type says so.
  final BuiltSection section;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      button: true,
      label: section.semanticLabel,
      onTap: () => context.go(section.path),
      container: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          border: Border.all(color: colors.outline),
        ),
        // So the ink stays inside the rounded corner, the way a settings card
        // does.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HearthRadius.lg),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go(section.path),
              child: Padding(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The accent, used once per card and nowhere else on this
                    // screen — 60/30/10 (spec §6.1).
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken,
                        borderRadius: BorderRadius.circular(HearthRadius.md),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(HearthSpacing.md),
                        child: Icon(
                          section.icon,
                          size: 28,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: HearthSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            section.label,
                            style: context.text.recipeTitle.copyWith(
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: HearthSpacing.xs),
                          Text(
                            section.blurb,
                            style: context.text.body.copyWith(
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
        ),
      ),
    );
  }
}

/// What the house does not have yet.
///
/// A sentence, not a control: nothing here can be tapped, so nothing here can
/// disappoint. Its words come from the registry, so building Fitness moves it
/// out of this line and into a card of its own with no copy to rewrite — and
/// when the last one is built the line stops rendering entirely.
class _ComingLater extends StatelessWidget {
  const _ComingLater();

  @override
  Widget build(BuildContext context) {
    final List<PlannedSection> later = unbuiltSections;
    if (later.isEmpty) return const SizedBox.shrink();

    final HearthColors colors = context.colors;
    // A colon and commas rather than a sentence with "and" in it: the names
    // are proper nouns, and one of them is "The house" — which reads as a
    // typo halfway through a sentence and as a list item perfectly well.
    final String listed = <String>[
      for (final PlannedSection section in later) section.label,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.foundation_outlined, size: 18, color: colors.textMuted),
          const SizedBox(width: HearthSpacing.sm),
          Expanded(
            child: Text(
              'Still being built: $listed.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
