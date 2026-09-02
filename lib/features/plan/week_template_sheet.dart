import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/week_template.dart';

/// Naming a week worth having again (spec §5.6).
Future<String?> showSaveTemplateSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _SaveSheet(),
    );

/// Choosing a saved week to put onto this one.
Future<WeekTemplate?> showApplyTemplateSheet(BuildContext context) =>
    showModalBottomSheet<WeekTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _ApplySheet(),
    );

class _SaveSheet extends StatefulWidget {
  const _SaveSheet();

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'Save this week',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Everything planned this week, kept by weekday so you can put it '
          'on another week later.',
          style: context.text.metadata.copyWith(
            color: context.colors.textMuted,
          ),
        ),
        const SizedBox(height: HearthSpacing.lg),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: context.text.body,
          decoration: const InputDecoration(
            labelText: 'Call it something',
            hintText: 'A good week',
          ),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        const SizedBox(height: HearthSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: HearthTouch.minTarget,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(_name.text),
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
}

class _ApplySheet extends ConsumerWidget {
  const _ApplySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WeekTemplate> templates =
        ref.watch(weekTemplatesProvider).value ?? const <WeekTemplate>[];

    return _Sheet(
      title: 'Use a saved week',
      child: templates.isEmpty
          ? Text(
              'No saved weeks yet. Plan a week you like, then save it from '
              'the bookmark button.',
              style: context.text.body.copyWith(
                color: context.colors.textSecondary,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final WeekTemplate template in templates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(template.name, style: context.text.body),
                    subtitle: Text(
                      '${template.entries.length} '
                      '${template.entries.length == 1 ? 'meal' : 'meals'}',
                      style: context.text.metadata.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () async {
                        await ref
                            .read(planRepositoryProvider)
                            .deleteTemplate(template.id);
                        ref.invalidate(weekTemplatesProvider);
                      },
                      tooltip: 'Forget ${template.name}',
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () => Navigator.of(context).pop(template),
                  ),
              ],
            ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Material rather than a DecoratedBox: a ListTile paints its background
      // and its tap ink onto the nearest Material ancestor, so a coloured box
      // in between hides the splash entirely. Flutter asserts on it, and a
      // widget test caught it before the device did.
      child: Material(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HearthRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.sm),
              child,
              const SizedBox(height: HearthSpacing.md),
            ],
          ),
        ),
      ),
    ),
  );
}
