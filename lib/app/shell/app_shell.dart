import 'package:flutter/material.dart';

import '../../features/recipes/timer_bar.dart';
import '../theme/hearth_colors.dart';
import '../theme/hearth_spacing.dart';
import '../theme/hearth_theme.dart';
import 'destinations.dart';

/// The pillar-level app shell (spec §6.2).
///
/// Desktop gets a sidebar, phone gets bottom tabs — "phone is capture and log,
/// desktop is plan and manage". The switch is on available width, not on
/// platform, so a narrow macOS window behaves like a phone rather than
/// squeezing a sidebar into nothing.
class AppShell extends StatelessWidget {
  const AppShell({
    required this.child,
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  /// Width at or above which the sidebar replaces bottom tabs.
  static const double sidebarBreakpoint = 840;

  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: wide ? _wideLayout(context) : child,
      // The timer bar sits above the tabs rather than inside a screen: a
      // running timer belongs to the app, not to the recipe you happen to be
      // looking at (spec §5.2). It renders nothing when nothing is on.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CookTimerBar(),
          if (!wide) _bottomTabs(context),
        ],
      ),
    );
  }

  Widget _wideLayout(BuildContext context) {
    final HearthColors colors = context.colors;
    return Row(
      children: <Widget>[
        _Sidebar(
          currentIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
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
          for (final AppDestination d in foodDestinations)
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
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  static const double width = 208;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Container(
      width: width,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(
        vertical: HearthSpacing.lg,
        horizontal: HearthSpacing.sm,
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < foodDestinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
                child: _SidebarItem(
                  destination: foodDestinations[i],
                  selected: i == currentIndex,
                  onTap: () => onDestinationSelected(i),
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
