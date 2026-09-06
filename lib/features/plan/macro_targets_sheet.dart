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
      // Capped, so a sheet that has grown taller than the screen stops at
      // something the content can scroll inside. Without a ceiling the
      // shrink-wrapped list simply takes its content's height and is clipped,
      // which looks identical to not scrolling at all.
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
        // (spec §6.3). `shrinkWrap` keeps it the height of its content on an
        // ordinary phone, where it is a short sheet rather than a full one.
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
              _TargetFields(
                fields: <Widget>[
                  _TargetField(controller: _kcal, label: 'kcal'),
                  _TargetField(controller: _protein, label: 'Protein'),
                  _TargetField(controller: _carbs, label: 'Carbs'),
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
              // Three fields side by side stop fitting well before the
              // text is at its largest — 36 points over at 3x — and a
              // field pushed off the edge is one nobody can fill in.
              _TargetFields(
                fields: <Widget>[
                  _TargetField(controller: _fibre, label: 'Fibre g'),
                  _TargetField(controller: _sodium, label: 'Sodium mg'),
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
  Widget build(BuildContext context) => Column(
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
  );
}

/// Lays a group of target fields out side by side, or one per line when they
/// no longer fit.
///
/// A Row of `Expanded` fields shares the width evenly, which sounds like it
/// cannot overflow — but a field's label has a width of its own below which
/// it will not go, and at three times the text three of them together are 36
/// points wider than the sheet. The share each field gets has to be big
/// enough to be a field, and when it cannot be, they belong on their own
/// lines.
class _TargetFields extends StatelessWidget {
  const _TargetFields({required this.fields});

  final List<Widget> fields;

  /// The narrowest a field is worth being, at ordinary text.
  static const double _minFieldWidth = 96;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final double needed =
        _minFieldWidth * scale * fields.length +
        HearthSpacing.sm * (fields.length - 1);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= needed) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < fields.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: HearthSpacing.sm),
                Expanded(child: fields[i]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < fields.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: HearthSpacing.sm),
              fields[i],
            ],
          ],
        );
      },
    );
  }
}
