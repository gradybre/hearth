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
      // Nine tenths rather than all of it, so there is still a scrim to tap
      // to dismiss. This is not what makes the sheet scroll —
      // `isScrollControlled` already caps the child at the screen height —
      // it is only about leaving a way out.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
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

  /// The minor three. Left empty means the Daily Value, which is why these
  /// are never seeded with one — a field showing 28 is indistinguishable
  /// afterwards from a 28 somebody typed (spec §5.6).
  final TextEditingController _fibre = TextEditingController();
  final TextEditingController _sodium = TextEditingController();
  final TextEditingController _cholesterol = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fibre,
      _sodium,
      _cholesterol,
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
    // Only where the household set one. A blank field is the Daily Value.
    if (existing.fiberG case final double v) _fibre.text = _trim(v);
    if (existing.sodiumMg case final double v) _sodium.text = _trim(v);
    if (existing.cholesterolMg case final double v) {
      _cholesterol.text = _trim(v);
    }
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
              // No `?? 0` — an empty field means the Daily Value, and a zero
              // would be a target of nothing.
              fiberG: double.tryParse(_fibre.text.trim()),
              sodiumMg: double.tryParse(_sodium.text.trim()),
              cholesterolMg: double.tryParse(_cholesterol.text.trim()),
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
        // Scrollable: at three times the text this sheet is 462 points taller
        // than the screen, so Save was off the bottom with no way to reach it
        // (spec §6.3). `shrinkWrap` keeps the sheet the height of its content
        // while that fits, so it stays a short sheet at ordinary text rather
        // than becoming a full-height one.
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(HearthSpacing.lg),
            children: <Widget>[
              Text('Weekly targets', style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.xs),
              Text(
                'Daily targets for this week. You can change them week to '
                'week.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
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
              Text('Fibre, sodium, cholesterol', style: context.text.body),
              const SizedBox(height: HearthSpacing.xxs),
              Text(
                'Leave blank for the Daily Values — 28 g, 2,300 mg and '
                '300 mg. Fibre is one to reach; the other two are budgets.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: HearthSpacing.sm),
              // These stay a Row of Expanded fields, which cannot overflow:
              // each child is given a tight width and the labels wrap inside
              // it. A LayoutBuilder that stacked them "when they no longer
              // fit" was solving a problem this row does not have, and its
              // threshold stacked all four macro fields on every iPhone at
              // ordinary text.
              Row(
                children: <Widget>[
                  _TargetField(controller: _fibre, label: 'Fibre g'),
                  const SizedBox(width: HearthSpacing.sm),
                  _TargetField(controller: _sodium, label: 'Sodium mg'),
                  const SizedBox(width: HearthSpacing.sm),
                  _TargetField(controller: _cholesterol, label: 'Chol. mg'),
                ],
              ),
              const SizedBox(height: HearthSpacing.lg),
              // "Cancel" and "Save targets" side by side are 36 points wider
              // than the sheet at three times the text, which puts Save off
              // the right-hand edge. Stacked when they do not fit.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: HearthSpacing.sm,
                overflowSpacing: HearthSpacing.sm,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
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
