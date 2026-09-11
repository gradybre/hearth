import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/recipes/timer_bar.dart';
import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import 'destinations.dart';
import 'sections.dart';

/// The shell one section lives in (spec §6.2).
///
/// Desktop gets a sidebar, phone gets bottom tabs — "phone is capture and log,
/// desktop is plan and manage". The switch is on available width, not on
/// platform, so a narrow macOS window behaves like a phone rather than
/// squeezing a sidebar into nothing.
///
/// The shell shows one section's tabs, not the app's — it is handed a
/// [section] and reads its destinations. Which is why it also owns the way
/// back out: the four screens inside know nothing about there being a home
/// screen, and the way home has to be in the same place whichever one you are
/// looking at. It sits at the top of the sidebar on a wide window and in a
/// slim bar above the content on a narrow one, both of them saying "Home" in
/// words rather than trusting an icon to carry it (spec §6.3).
class AppShell extends StatelessWidget {
  const AppShell({
    required this.section,
    required this.child,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onLeaveSection,
    super.key,
  });

  /// Width at or above which the sidebar replaces bottom tabs.
  static const double sidebarBreakpoint = 840;

  /// Which room this is. Supplies the tabs and the name in the chrome — so it
  /// is a built one, which is the only kind with tabs to supply.
  final BuiltSection section;

  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Back to the home screen.
  final VoidCallback onLeaveSection;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;
    return PopScope(
      // Entering a section replaces the route rather than pushing onto it (see
      // the router), so there is no home screen underneath to pop back to —
      // and without this, a system back from Recipes would close the app. In a
      // launcher-shaped app that is the wrong answer: back goes up a level,
      // and up a level is home. From home itself, back leaves, which is where
      // this scope no longer exists.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) onLeaveSection();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: wide
            ? _wideLayout(context)
            : Column(
                children: <Widget>[
                  _SectionBar(section: section, onLeave: onLeaveSection),
                  // The section bar has already stood clear of the status bar,
                  // and every screen behind these tabs is a Scaffold whose body
                  // is a SafeArea with no app bar above it. Left alone they
                  // would each clear the same 47 points a second time, which
                  // reads as a band of empty paper under the bar. The wide
                  // layout has no bar above the content, so it keeps its inset.
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: child,
                    ),
                  ),
                ],
              ),
        // The timer bar sits above the tabs rather than inside a screen: a
        // running timer belongs to the app, not to the recipe you happen to be
        // looking at (spec §5.2). It renders nothing when nothing is on.
        //
        // Carried here rather than once around the whole router, because it is
        // laid out as a Scaffold's bottom bar — which is what keeps it clear of
        // the keyboard and the home indicator. So the screens that can be the
        // whole of what you are looking at each carry one: this, the recipe
        // detail screen, and the home screen.
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CookTimerBar(),
            if (!wide) _bottomTabs(context),
          ],
        ),
      ),
    );
  }

  Widget _wideLayout(BuildContext context) {
    final HearthColors colors = context.colors;
    return Row(
      // Stretched, so the rail is the height of the window. A Row centres its
      // children on the cross axis unless told otherwise, and the sidebar
      // sizes to its own content — so on a 900pt window it sat in a band down
      // the middle with empty paper above and below, and the way out of the
      // section began a third of the way down the screen (review §6.2.7:
      // "the sidebar floats around the vertical center").
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Sidebar(
          section: section,
          currentIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          onLeave: onLeaveSection,
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outline),
        Expanded(child: child),
      ],
    );
  }

  Widget _bottomTabs(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: HearthTouch.kitchenTarget,
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        indicatorColor: colors.surfaceSunken,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: <NavigationDestination>[
          for (final AppDestination d in section.destinations)
            NavigationDestination(
              icon: Icon(d.icon, color: colors.textSecondary),
              selectedIcon: Icon(d.selectedIcon, color: colors.accent),
              label: d.label,
              tooltip: d.label,
            ),
        ],
      ),
    );
  }
}

/// Hearth's own sidebar.
///
/// Built from primitives rather than [NavigationRail] because the rail's
/// semantics could not be made to expose a usable label per destination — and
/// screen-reader labels on every interactive element are a non-negotiable
/// (spec §6.3), not something to hand to a widget that might drop them.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onLeave,
  });

  static const double width = 208;

  final BuiltSection section;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final List<AppDestination> tabs = section.destinations;
    return Container(
      width: width,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(
        vertical: HearthSpacing.lg,
        horizontal: HearthSpacing.sm,
      ),
      child: SafeArea(
        right: false,
        // Scrollable, because the rail is a fixed 208pt column of text in a
        // window whose height the user chooses. A way home, a section heading
        // and four rows already run past the bottom of a 400pt window at 3x —
        // dynamic type is honoured, not capped (spec §6.3), so the rail has to
        // give way rather than the text.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The way out, above everything it is a way out of.
              _HomeItem(section: section, onTap: onLeave),
              const SizedBox(height: HearthSpacing.sm),
              // Which room you are in, so the tabs below are read as this
              // section's rather than as the whole app's.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HearthSpacing.md,
                  0,
                  HearthSpacing.md,
                  HearthSpacing.sm,
                ),
                child: Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    section.label,
                    style: context.text.sectionHeader,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              for (int i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
                  child: _SidebarItem(
                    destination: tabs[i],
                    selected: i == currentIndex,
                    onTap: () => onDestinationSelected(i),
                  ),
                ),
              // Below the tabs, not among them: it is not one of this
              // section's screens and should not read as one.
              const _SettingsButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into Settings, in whichever chrome is showing.
///
/// One widget rather than two spellings, because "the same place whichever
/// screen you are looking at" is the whole point of it: Settings used to live
/// on the home screen alone, so changing a preference about the screen you
/// were on meant leaving that screen and coming back.
///
/// It pushes rather than replacing, so Settings returns you to the section
/// you opened it from — which the home screen's own route does too.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({this.compact = false});

  /// Icon alone, for the slim bar above a phone's content. The sidebar has
  /// room for the word and uses it, the same way its other rows do.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    void open() => GoRouter.of(context).push('/settings');

    if (compact) {
      return IconButton(
        icon: Icon(Icons.settings_outlined, size: 20, color: colors.textMuted),
        tooltip: 'Settings',
        onPressed: open,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: HearthSpacing.sm),
      child: Tooltip(
        message: 'Settings',
        child: TextButton.icon(
          onPressed: open,
          icon: Icon(
            Icons.settings_outlined,
            size: 18,
            color: colors.textMuted,
          ),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Settings',
              style: context.text.body.copyWith(color: colors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: HearthSpacing.md,
              vertical: HearthSpacing.sm,
            ),
          ),
        ),
      ),
    );
  }
}

/// "‹ Home", at the top of the sidebar.
class _HomeItem extends StatelessWidget {
  const _HomeItem({required this.section, required this.onTap});

  final AppSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      button: true,
      // Says where it goes and what it leaves, because "Home" alone is
      // ambiguous in an app whose sections are rooms (spec §6.3).
      label: 'Home. Leave ${section.label} and go back to all of Hearth.',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.md,
                vertical: HearthSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      'Home',
                      style: context.text.label.copyWith(
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow-window equivalent: a slim bar above the section, carrying the way
/// home on the left and the room's name on the right.
///
/// It costs a row of vertical space on a phone, which is the price of the way
/// out being in one predictable place rather than repeated inside four screens
/// that would each have to remember to draw it.
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.section, required this.onLeave});

  final AppSection section;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        bottom: false,
        // Fixed shares rather than natural widths, so that turning dynamic
        // type all the way up ellipsises both halves instead of overflowing
        // the row (spec §6.3).
        child: Row(
          children: <Widget>[
            Flexible(
              flex: 3,
              child: _HomeItem(section: section, onTap: onLeave),
            ),
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  HearthSpacing.sm,
                  HearthSpacing.sm,
                  HearthSpacing.sm,
                ),
                // Hard against the right edge, balancing the way home on the
                // left rather than floating in the middle of its share.
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Icon(section.icon, size: 16, color: colors.textMuted),
                    const SizedBox(width: HearthSpacing.xs),
                    Flexible(
                      child: Text(
                        section.label,
                        style: context.text.metadata.copyWith(
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Beyond the section's own name, so the bar reads
                    // "where you are" and then "the app's own settings" —
                    // and it is in the same place on every one of the four
                    // screens, which is the whole of the fix.
                    const _SettingsButton(compact: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      label: destination.semanticLabel,
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.surfaceSunken : Colors.transparent,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HearthSpacing.md,
                vertical: HearthSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 20,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: context.text.label.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
