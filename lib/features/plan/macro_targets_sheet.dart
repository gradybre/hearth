import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/planning/day_progress.dart';

/// Sets the macro targets for the selected day's week (spec §5.6).
///
/// Targets are fixed daily numbers set per week, entered by hand. Calculating
/// them from body stats is explicitly a later option (spec §5.6, §12), so this
/// asks for four numbers and nothing else.
Future<void> showMacroTargetsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const _MacroTargetsSheet(),
    );

class _MacroTargetsSheet extends ConsumerStatefulWidget {
  const _MacroTargetsSheet();

  @override
  ConsumerState<_MacroTargetsSheet> createState() => _MacroTargetsSheetState();
}

class _MacroTargetsSheetState extends ConsumerState<_MacroTargetsSheet> {
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _kcal,
      _protein,
      _carbs,
      _fat,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(MacroTargets? existing) {
    if (_seeded || existing == null) return;
    _kcal.text = _trim(existing.kcal);
    _protein.text = _trim(existing.proteinG);
    _carbs.text = _trim(existing.carbG);
    _fat.text = _trim(existing.fatG);
    _seeded = true;
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .setTargets(
            ref.read(selectedDateProvider),
            MacroTargets(
              kcal: double.tryParse(_kcal.text.trim()) ?? 0,
              proteinG: double.tryParse(_protein.text.trim()) ?? 0,
              carbG: double.tryParse(_carbs.text.trim()) ?? 0,
              fatG: double.tryParse(_fat.text.trim()) ?? 0,
            ),
          );
      ref.invalidate(dayTargetsProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    _seed(ref.watch(dayTargetsProvider).value);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(HearthRadius.xl),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Weekly targets', style: context.text.sectionHeader),
                const SizedBox(height: HearthSpacing.xs),
                Text(
                  'Daily targets for this week. You can change them week to '
                  'week.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: HearthSpacing.lg),
                Row(
                  children: <Widget>[
                    _TargetField(controller: _kcal, label: 'kcal'),
                    const SizedBox(width: HearthSpacing.sm),
                    _TargetField(controller: _protein, label: 'Protein'),
                    const SizedBox(width: HearthSpacing.sm),
                    _TargetField(controller: _carbs, label: 'Carbs'),
                    const SizedBox(width: HearthSpacing.sm),
                    _TargetField(controller: _fat, label: 'Fat'),
                  ],
                ),
                const SizedBox(height: HearthSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: HearthSpacing.sm),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save targets'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: context.text.metadata.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        TextField(
          controller: controller,
          // A target of 162.5 g of protein is an ordinary number; a plain
          // number pad on iOS cannot type the point.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: context.text.body,
        ),
      ],
    ),
  );
}
