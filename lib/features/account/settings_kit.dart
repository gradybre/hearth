/// The pieces a settings screen is made of.
///
/// Their own file because there are seven settings screens now rather than
/// one — an index and the six pages behind it (review §7.8) — and a shared
/// vocabulary that lives inside one of them is a vocabulary the other six
/// import from a page.
library;

import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/reading_column.dart';

/// The card the rows of a section sit in, hairlines between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      // So a row's ink and highlight stay inside the rounded corner.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: colors.outline),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row that states something rather than doing something.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      label: '$title $value',
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: colors.textMuted),
            const SizedBox(width: HearthSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: HearthSpacing.xxs),
                  Text(value, style: context.text.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that goes somewhere.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Where this setting currently stands, shown before the chevron.
  ///
  /// The whole of what makes an index an index (review §7.8): the page it
  /// leads to is where a thing is *changed*, and this is where it is read.
  /// Empty while the answer is still being fetched, because a placeholder
  /// that later turns into a different word is worse than a gap.
  final String? value;

  /// What activating this says out loud. Says what the destination *is*
  /// rather than repeating the visible word (spec §6.3).
  final String? semanticLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SettingsTappableRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    value: value,
    semanticLabel: semanticLabel ?? _spoken,
    trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
    onTap: onTap,
  );

  /// The row read out as one sentence, so the value is not left behind.
  ///
  /// Without it a screen reader announces the label and the chevron and says
  /// nothing about where the setting stands, which is the one thing the row
  /// was added to carry.
  String? get _spoken => value == null || value!.isEmpty
      ? null
      : subtitle == null
      ? '$title. $value'
      : '$title. $value. $subtitle';
}

/// A row that does something here and now.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.semanticLabel,
    this.isDestructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? semanticLabel;

  /// Draws the row in the error tone. Never the only signal: the row keeps
  /// its own icon and its words say what it does (spec §6.3).
  final bool isDestructive;

  /// Null while the action is already running. The row goes quiet and stops
  /// answering rather than pretending — a second tap on an export in flight
  /// builds the file twice.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _SettingsTappableRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    semanticLabel: semanticLabel,
    tone: isDestructive ? context.colors.error : null,
    onTap: onTap,
  );
}

class _SettingsTappableRow extends StatelessWidget {
  const _SettingsTappableRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.semanticLabel,
    this.trailing,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final String? semanticLabel;
  final Widget? trailing;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool enabled = onTap != null;
    // Muted rather than merely paler: a row that cannot be activated is also
    // reported as disabled to a screen reader, so the dimming is a second
    // signal and never the only one (spec §6.3).
    final Color foreground = enabled
        ? (tone ?? colors.textPrimary)
        : colors.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? <String?>[title, subtitle].nonNulls.join('. '),
      onTap: onTap,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 20,
                    color: enabled
                        ? (tone ?? colors.textSecondary)
                        : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // A wrap rather than a row with the value pushed to
                        // the far edge. Side by side, each half gets a
                        // fraction of a 320-point phone, and at twice the
                        // text "Follow the device" came out three words tall
                        // — one 504-point row. Wrapped, the value drops to a
                        // line of its own with the whole width to use, and
                        // the row is 120 points again. Dynamic type is
                        // honoured by the layout giving way (spec §6.3).
                        Wrap(
                          spacing: HearthSpacing.md,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              title,
                              style: context.text.body.copyWith(
                                color: foreground,
                              ),
                            ),
                            if (value case final String value
                                when value.isNotEmpty)
                              Text(
                                value,
                                style: context.text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                        if (subtitle case final String subtitle) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            subtitle,
                            style: context.text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing case final Widget trailing) ...<Widget>[
                    const SizedBox(width: HearthSpacing.sm),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of feedback, spoken as well as shown.
class SettingsMessage extends StatelessWidget {
  const SettingsMessage({required this.text, required this.isError, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // An icon as well as the colour, so a problem and a note are not
          // told apart by hue alone (spec §6.3).
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: isError ? colors.error : colors.textSecondary,
          ),
          const SizedBox(width: HearthSpacing.sm),
          Expanded(child: Text(text, style: context.text.body)),
        ],
      ),
    );
  }
}

/// What a device that refused the write gets told.
class SettingsCouldNotSave extends StatelessWidget {
  const SettingsCouldNotSave({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(HearthSpacing.md),
    child: SettingsMessage(
      text:
          'That could not be saved on this device, so Hearth has gone back '
          'to the last choice that was.',
      isError: true,
    ),
  );
}

/// One answer in a list of mutually exclusive ones, ticked when it is the one
/// in force.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.blurb,
    super.key,
  });

  final String label;

  /// A sentence under the label, where the label alone cannot say what the
  /// answer does. Usually null now: §6.2.4's complaint was that this screen
  /// explained "Light" and "Dark", which is the word said twice.
  final String? blurb;

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: blurb == null ? label : '$label. $blurb',
      onTap: onTap,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label, style: context.text.body),
                        if (blurb case final String blurb) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            blurb,
                            style: context.text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  // The tick is the signal, not the colour of the row: which
                  // option is chosen must survive being seen in greyscale
                  // (spec §6.3).
                  if (selected)
                    Icon(Icons.check, size: 20, color: colors.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One settings page: a title, a back arrow, and a bounded column of groups.
///
/// The index and all six pages behind it are the same object with different
/// contents, so the chrome is written once. [ReadingColumn] is here rather
/// than on each page for the reason §6.2.7 gives: a window is as wide as
/// somebody dragged it and a row of settings is not, and seven screens
/// bounding themselves separately is seven chances to drift.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.title,
    required this.children,
    this.blurb,
    super.key,
  });

  final String title;

  /// A sentence under the title, for a page whose consequence the controls
  /// cannot state themselves — joining a household, or a choice that stops at
  /// this device. Not for explaining a label (review §6.2.4).
  final String? blurb;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: context.text.label),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              HearthSpacing.lg,
              gutter,
              HearthSpacing.xxl,
            ),
            children: <Widget>[
              if (blurb case final String blurb) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: HearthSpacing.xs),
                  child: Text(
                    blurb,
                    style: context.text.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: HearthSpacing.lg),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// How long ago [at] was, in words.
///
/// Rough on purpose. A timestamp to the second invites somebody to compare
/// two devices' clocks, which is a question this answers badly — the phones
/// disagree by seconds anyway. "About an hour ago" is the resolution the fact
/// actually has, and the resolution somebody deciding whether to worry needs.
///
/// Shared rather than private to the sync page: the index says the same fact
/// in the same words, and two spellings of "yesterday" on two screens about
/// one timestamp is a bug waiting to be reported.
String describeAgo(DateTime at) {
  final Duration since = DateTime.now().toUtc().difference(at.toUtc());
  if (since.inMinutes < 1) return 'just now';
  if (since.inMinutes < 60) return '${since.inMinutes} min ago';
  if (since.inHours < 24) {
    return since.inHours == 1 ? 'an hour ago' : '${since.inHours} hours ago';
  }
  return since.inDays == 1 ? 'yesterday' : '${since.inDays} days ago';
}
